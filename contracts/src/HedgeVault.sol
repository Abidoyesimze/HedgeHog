// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IHedgeVault, HedgeInstruction} from "./interfaces/IHedgeVault.sol";
import {IAcrossBridge} from "./interfaces/IAcrossBridge.sol";

/// @title HedgeVault
/// @notice Holds USDC collateral and manages the hedge book.
///         Receives callbacks from HedgehogHook and executes hedge instructions from the AVS.
contract HedgeVault is IHedgeVault, ERC20, ReentrancyGuard, Ownable {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    IERC20 public immutable usdc;
    IAcrossBridge public immutable bridge;
    address public hook;

    /// @notice Arbitrum chain ID for bridging collateral
    uint256 public arbitrumChainId;

    /// @notice Address of HedgehogArbitrum on Arbitrum (receives bridged collateral)
    address public arbitrumReceiver;

    /// @notice Max relayer fee accepted when bridging (0.1% default)
    uint256 public maxBridgeFeePct = 1e15;

    bool public override paused;

    /// @notice Net ETH exposure per pool (in 1e18 ETH units)
    mapping(bytes32 => int256) public netDeltaByPool;

    /// @notice Last hedged notional per pool (in USDC 1e6)
    mapping(bytes32 => int256) public lastHedgedNotional;

    /// @notice Registered AVS operators
    mapping(address => bool) public registeredOperators;

    /// @notice Per-operator nonce to prevent instruction replay
    mapping(address => uint256) public operatorNonce;

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyHook() {
        require(msg.sender == hook, "HedgeVault: caller is not the hook");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "HedgeVault: paused");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        address _usdc,
        address _bridge
    ) ERC20("Hedgehog LP", "hhLP") {
        usdc = IERC20(_usdc);
        bridge = IAcrossBridge(_bridge);
        // OZ v4 Ownable sets owner to msg.sender automatically
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    function setHook(address _hook) external onlyOwner {
        hook = _hook;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function registerOperator(address operator, bool active) external onlyOwner {
        registeredOperators[operator] = active;
    }

    function setArbitrumConfig(
        uint256 _chainId,
        address _receiver,
        uint256 _maxFeePct
    ) external onlyOwner {
        arbitrumChainId  = _chainId;
        arbitrumReceiver = _receiver;
        maxBridgeFeePct  = _maxFeePct;
    }

    // -----------------------------------------------------------------------
    // LP deposit / withdrawal
    // -----------------------------------------------------------------------

    /// @notice Deposit USDC into the vault and receive hhLP shares
    function deposit(uint256 usdcAmount) external nonReentrant whenNotPaused returns (uint256 shares) {
        require(usdcAmount > 0, "HedgeVault: zero amount");
        uint256 supply = totalSupply();
        uint256 balance = totalCollateral();
        shares = supply == 0 ? usdcAmount : (usdcAmount * supply) / balance;
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        _mint(msg.sender, shares);
    }

    /// @notice Burn hhLP shares and receive proportional USDC
    function withdraw(uint256 shares) external nonReentrant returns (uint256 usdcAmount) {
        require(shares > 0, "HedgeVault: zero shares");
        uint256 supply = totalSupply();
        usdcAmount = (shares * totalCollateral()) / supply;
        _burn(msg.sender, shares);
        usdc.safeTransfer(msg.sender, usdcAmount);
    }

    // -----------------------------------------------------------------------
    // Hook callbacks
    // -----------------------------------------------------------------------

    function onLiquidityAdded(
        address lp,
        PoolKey calldata key,
        int256 exposureDelta
    ) external override onlyHook whenNotPaused {
        bytes32 poolId = PoolId.unwrap(key.toId());
        netDeltaByPool[poolId] += exposureDelta;
        emit LiquidityAdded(lp, poolId, exposureDelta);
        emit HedgeRequested(poolId, netDeltaByPool[poolId]);
    }

    function onLiquidityRemoved(
        address lp,
        PoolKey calldata key,
        int256 exposureDelta
    ) external override onlyHook whenNotPaused {
        bytes32 poolId = PoolId.unwrap(key.toId());
        netDeltaByPool[poolId] += exposureDelta;
        emit LiquidityRemoved(lp, poolId, exposureDelta);
        emit HedgeRequested(poolId, netDeltaByPool[poolId]);
    }

    function requestRebalance(PoolKey calldata key) external override onlyHook whenNotPaused {
        bytes32 poolId = PoolId.unwrap(key.toId());
        int256 drift = netDeltaByPool[poolId] - lastHedgedNotional[poolId];
        emit RebalanceRequested(poolId, drift);
    }

    // -----------------------------------------------------------------------
    // AVS operator — hedge instruction execution
    // -----------------------------------------------------------------------

    function executeHedgeInstruction(
        HedgeInstruction calldata instruction,
        bytes calldata operatorSignature
    ) external override nonReentrant whenNotPaused {
        require(block.timestamp <= instruction.deadline, "HedgeVault: instruction expired");

        bytes32 structHash = keccak256(abi.encode(
            instruction.poolId,
            instruction.targetNotional,
            instruction.maxSlippageBps,
            instruction.deadline,
            instruction.nonce
        ));
        // OZ v4: ECDSA.recover on the eth-prefixed hash
        address operator = structHash.toEthSignedMessageHash().recover(operatorSignature);

        require(registeredOperators[operator], "HedgeVault: operator not registered");
        require(instruction.nonce == operatorNonce[operator], "HedgeVault: invalid nonce");
        operatorNonce[operator]++;

        int256 notionalDelta = instruction.targetNotional - lastHedgedNotional[instruction.poolId];
        lastHedgedNotional[instruction.poolId] = instruction.targetNotional;

        emit HedgeExecuted(instruction.poolId, notionalDelta, operator);

        // Bridge collateral delta to Arbitrum for the PerpsAdapter to use
        _bridgeCollateral(instruction.poolId, notionalDelta);
    }

    function _bridgeCollateral(bytes32 poolId, int256 notionalDelta) internal {
        // Only bridge if we have an Arbitrum receiver configured and there's a positive delta
        if (arbitrumReceiver == address(0) || arbitrumChainId == 0) return;
        if (notionalDelta <= 0) return; // decreasing/closing hedge — P&L bridges back from Arbitrum

        // notionalDelta is in USDC (1e6). Bridge that amount to HedgehogArbitrum.
        uint256 bridgeAmount = uint256(notionalDelta);
        uint256 vaultBalance = usdc.balanceOf(address(this));
        if (bridgeAmount > vaultBalance) bridgeAmount = vaultBalance;
        if (bridgeAmount == 0) return;

        usdc.approve(address(bridge), bridgeAmount);
        bytes32 depositId = bridge.bridgeUSDC(
            bridgeAmount,
            arbitrumChainId,
            arbitrumReceiver,
            maxBridgeFeePct
        );

        emit CollateralBridged(poolId, bridgeAmount, arbitrumChainId);
    }

    // -----------------------------------------------------------------------
    // View functions
    // -----------------------------------------------------------------------

    function netDelta(bytes32 poolId) external view override returns (int256) {
        return netDeltaByPool[poolId];
    }

    function deltaDriftBps(bytes32 poolId) external view override returns (uint256) {
        int256 current = netDeltaByPool[poolId];
        int256 hedged = lastHedgedNotional[poolId];
        if (hedged == 0) return current == 0 ? 0 : type(uint256).max;
        int256 drift = current - hedged;
        uint256 absDrift = drift >= 0 ? uint256(drift) : uint256(-drift);
        uint256 absHedged = hedged >= 0 ? uint256(hedged) : uint256(-hedged);
        return (absDrift * 10_000) / absHedged;
    }

    function totalCollateral() public view override returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
