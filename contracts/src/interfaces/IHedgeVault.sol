// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/// @notice Signed instruction submitted by an AVS operator to adjust the hedge book
struct HedgeInstruction {
    bytes32 poolId;
    int256 targetNotional;   // positive = long, negative = short (in USDC terms)
    uint256 maxSlippageBps;  // max acceptable slippage in basis points
    uint256 deadline;        // unix timestamp after which instruction is invalid
    uint256 nonce;           // per-operator nonce to prevent replays
}

interface IHedgeVault {
    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    event LiquidityAdded(address indexed lp, bytes32 indexed poolId, int256 deltaExposure);
    event LiquidityRemoved(address indexed lp, bytes32 indexed poolId, int256 deltaExposure);
    event HedgeRequested(bytes32 indexed poolId, int256 targetNotional);
    event RebalanceRequested(bytes32 indexed poolId, int256 currentDrift);
    event HedgeExecuted(bytes32 indexed poolId, int256 notionalDelta, address operator);
    event CollateralBridged(bytes32 indexed poolId, uint256 amount, uint256 destinationChainId);

    // -----------------------------------------------------------------------
    // Hook callbacks (called by HedgehogHook only)
    // -----------------------------------------------------------------------

    /// @notice Called after an LP adds liquidity to a Hedgehog pool
    function onLiquidityAdded(
        address lp,
        PoolKey calldata key,
        int256 exposureDelta
    ) external;

    /// @notice Called after an LP removes liquidity from a Hedgehog pool
    function onLiquidityRemoved(
        address lp,
        PoolKey calldata key,
        int256 exposureDelta
    ) external;

    /// @notice Called by the hook when drift threshold is exceeded; emits RebalanceRequested
    function requestRebalance(PoolKey calldata key) external;

    // -----------------------------------------------------------------------
    // AVS operator interface
    // -----------------------------------------------------------------------

    /// @notice Execute a hedge instruction signed by a registered AVS operator
    function executeHedgeInstruction(
        HedgeInstruction calldata instruction,
        bytes calldata operatorSignature
    ) external;

    // -----------------------------------------------------------------------
    // View functions
    // -----------------------------------------------------------------------

    /// @notice Net ETH-equivalent delta exposure for a pool (positive = net long ETH)
    function netDelta(bytes32 poolId) external view returns (int256);

    /// @notice Delta drift in basis points since last hedge execution
    function deltaDriftBps(bytes32 poolId) external view returns (uint256);

    /// @notice Whether the vault is paused (hook should no-op if true)
    function paused() external view returns (bool);

    /// @notice Total USDC collateral held by the vault
    function totalCollateral() external view returns (uint256);
}
