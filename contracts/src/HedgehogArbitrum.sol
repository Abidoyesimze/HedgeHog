// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IPerpsAdapter} from "./interfaces/IPerpsAdapter.sol";

/// @title HedgehogArbitrum
/// @notice Arbitrum-side contract that:
///         1. Receives USDC bridged from HedgeVault on Unichain via Across
///         2. Holds USDC collateral for active hedge positions
///         3. Is called by the AVS operator to open/modify/close GMX positions
///         4. Bridges P&L back to Unichain on position close
contract HedgehogArbitrum is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    IERC20 public immutable usdc;
    IPerpsAdapter public perpsAdapter;

    /// @notice Registered AVS operators (same set as Unichain side)
    mapping(address => bool) public registeredOperators;

    /// @notice Tracks which GMX positionId is open for each Hedgehog poolId
    mapping(bytes32 => bytes32) public poolToPosition;

    /// @notice Unichain HedgeVault address (for bridge-back validation)
    address public unichainVault;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event HedgeOpened(bytes32 indexed poolId, bytes32 positionId, int256 size);
    event HedgeModified(bytes32 indexed poolId, bytes32 positionId, int256 newSize);
    event HedgeClosed(bytes32 indexed poolId, bytes32 positionId, int256 pnl);
    event CollateralReceived(bytes32 indexed poolId, uint256 amount);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address _usdc, address _perpsAdapter) {
        usdc = IERC20(_usdc);
        perpsAdapter = IPerpsAdapter(_perpsAdapter);
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    function setPerpsAdapter(address _adapter) external onlyOwner {
        perpsAdapter = IPerpsAdapter(_adapter);
    }

    function setUnichainVault(address _vault) external onlyOwner {
        unichainVault = _vault;
    }

    function registerOperator(address operator, bool active) external onlyOwner {
        registeredOperators[operator] = active;
    }

    modifier onlyOperator() {
        require(registeredOperators[msg.sender], "HedgehogArbitrum: not a registered operator");
        _;
    }

    // -----------------------------------------------------------------------
    // Called by AVS operator after USDC bridge settles
    // -----------------------------------------------------------------------

    /// @notice Open a new short hedge for a pool. Requires USDC to already be in this contract.
    /// @param poolId       Hedgehog pool identifier (matches Unichain pool)
    /// @param sizeDeltaUsd Short size in GMX 1e30 USD precision
    /// @param collateral   USDC (1e6) to use as collateral
    /// @param maxSlippage  Max slippage in bps
    function openHedge(
        bytes32 poolId,
        int256 sizeDeltaUsd,
        uint256 collateral,
        uint256 maxSlippage
    ) external onlyOperator nonReentrant {
        require(poolToPosition[poolId] == bytes32(0), "HedgehogArbitrum: hedge already open");
        require(usdc.balanceOf(address(this)) >= collateral, "HedgehogArbitrum: insufficient collateral");

        usdc.approve(address(perpsAdapter), collateral);
        bytes32 positionId = perpsAdapter.openPosition(sizeDeltaUsd, collateral, maxSlippage);
        poolToPosition[poolId] = positionId;

        emit HedgeOpened(poolId, positionId, sizeDeltaUsd);
    }

    /// @notice Modify the hedge size for a pool (rebalance).
    function modifyHedge(
        bytes32 poolId,
        int256 newSizeDeltaUsd,
        uint256 maxSlippage
    ) external onlyOperator nonReentrant {
        bytes32 positionId = poolToPosition[poolId];
        require(positionId != bytes32(0), "HedgehogArbitrum: no open hedge");

        perpsAdapter.modifyPosition(positionId, newSizeDeltaUsd, maxSlippage);
        emit HedgeModified(poolId, positionId, newSizeDeltaUsd);
    }

    /// @notice Close the hedge for a pool and bridge P&L + collateral back to Unichain.
    /// @param poolId           Hedgehog pool identifier
    /// @param maxSlippage      Max slippage in bps
    /// @param acrossBridge     Across SpokePool on Arbitrum for bridging back
    /// @param destinationChain Unichain chain ID
    function closeHedge(
        bytes32 poolId,
        uint256 maxSlippage,
        address acrossBridge,
        uint256 destinationChain
    ) external onlyOperator nonReentrant {
        bytes32 positionId = poolToPosition[poolId];
        require(positionId != bytes32(0), "HedgehogArbitrum: no open hedge");

        int256 pnl = perpsAdapter.closePosition(positionId, maxSlippage);
        delete poolToPosition[poolId];

        emit HedgeClosed(poolId, positionId, pnl);

        // Bridge remaining USDC balance back to Unichain HedgeVault
        uint256 balance = usdc.balanceOf(address(this));
        if (balance > 0 && acrossBridge != address(0) && unichainVault != address(0)) {
            usdc.approve(acrossBridge, balance);
            _bridgeBack(acrossBridge, balance, destinationChain);
        }
    }

    // -----------------------------------------------------------------------
    // Internal
    // -----------------------------------------------------------------------

    function _bridgeBack(address spokePool, uint256 amount, uint256 destinationChain) internal {
        // Across SpokePool.depositV3 — bridge USDC back to Unichain HedgeVault
        (bool ok,) = spokePool.call(abi.encodeWithSignature(
            "depositV3(address,address,address,address,uint256,uint256,uint256,address,uint32,uint32,uint32,bytes)",
            address(this),           // depositor
            unichainVault,           // recipient on Unichain
            address(usdc),           // inputToken
            address(usdc),           // outputToken
            amount,
            amount * 999 / 1000,     // outputAmount (0.1% fee tolerance)
            destinationChain,
            address(0),              // exclusiveRelayer
            uint32(block.timestamp),
            uint32(block.timestamp + 3 hours),
            0,
            ""
        ));
        require(ok, "HedgehogArbitrum: bridge back failed");
    }

    // -----------------------------------------------------------------------
    // Emergency — owner can recover stuck funds
    // -----------------------------------------------------------------------

    function recoverERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    receive() external payable {}
}
