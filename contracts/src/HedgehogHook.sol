// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IHedgeVault} from "./interfaces/IHedgeVault.sol";

/// @title HedgehogHook
/// @notice Uniswap v4 hook that notifies the HedgeVault on every liquidity event and swap.
///         Triggers delta-hedge rebalances when drift exceeds the configured threshold.
contract HedgehogHook is IHooks {
    using PoolIdLibrary for PoolKey;

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    IPoolManager public immutable poolManager;
    IHedgeVault public immutable vault;

    /// @notice Drift threshold in basis points above which a rebalance is requested
    uint256 public immutable driftThresholdBps;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        IPoolManager _poolManager,
        IHedgeVault _vault,
        uint256 _driftThresholdBps
    ) {
        poolManager = _poolManager;
        vault = _vault;
        driftThresholdBps = _driftThresholdBps;
    }

    // -----------------------------------------------------------------------
    // Modifier
    // -----------------------------------------------------------------------

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "HedgehogHook: caller is not PoolManager");
        _;
    }

    // -----------------------------------------------------------------------
    // IHooks — implemented callbacks
    // -----------------------------------------------------------------------

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (!vault.paused()) {
            // amount0 is negative when tokens flow into the pool (LP deposits)
            // We flip sign: positive exposureDelta = LP added ETH exposure
            int256 exposureDelta = -delta.amount0();
            vault.onLiquidityAdded(sender, key, exposureDelta);
        }
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (!vault.paused()) {
            // amount0 is positive when tokens flow back to LP (withdrawal)
            // Flip sign: negative exposureDelta = LP reduced ETH exposure
            int256 exposureDelta = -delta.amount0();
            vault.onLiquidityRemoved(sender, key, exposureDelta);
        }
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        if (!vault.paused()) {
            bytes32 poolId = PoolId.unwrap(key.toId());
            uint256 drift = vault.deltaDriftBps(poolId);
            if (drift > driftThresholdBps) {
                vault.requestRebalance(key);
            }
        }
        return (IHooks.afterSwap.selector, 0);
    }

    // -----------------------------------------------------------------------
    // IHooks — unimplemented callbacks (revert to save gas)
    // -----------------------------------------------------------------------

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert("HedgehogHook: not implemented");
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        revert("HedgehogHook: not implemented");
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure override returns (bytes4)
    {
        revert("HedgehogHook: not implemented");
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external pure override returns (bytes4)
    {
        revert("HedgehogHook: not implemented");
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external pure override returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert("HedgehogHook: not implemented");
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4)
    {
        revert("HedgehogHook: not implemented");
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external pure override returns (bytes4)
    {
        revert("HedgehogHook: not implemented");
    }
}
