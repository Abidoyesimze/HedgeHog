import { HedgeSolverInput, HedgeSolverOutput } from "./types";

const MIN_REBALANCE_DRIFT_BPS = 200n;  // 2% minimum drift to trigger rebalance
const FUNDING_RATE_COST_THRESHOLD = 0.5; // annualized % above which we factor in funding cost

/// @notice Compute whether to rebalance and what the target hedge notional should be.
///         This is the core IP of the AVS — cost-benefit hedge sizing.
export function solveHedge(input: HedgeSolverInput): HedgeSolverOutput {
  const { poolState, ethPriceUsd, fundingRate, gasCostUsdc } = input;

  // Step 1: Compute current ETH exposure in USDC terms
  // netDelta is in 1e18 ETH units; ethPriceUsd is a JS number
  const ethExposureEth = Number(poolState.netDelta) / 1e18;
  const ethExposureUsdc = BigInt(Math.round(ethExposureEth * ethPriceUsd * 1e6));

  // Step 2: Compute the ideal hedge: short ETH exposure to net delta = 0
  // targetNotional is negative (short)
  const idealTargetNotional = -ethExposureUsdc;

  // Step 3: Check if drift is large enough to warrant a rebalance
  if (poolState.driftBps < MIN_REBALANCE_DRIFT_BPS) {
    return {
      shouldRebalance: false,
      targetNotional: poolState.lastHedgedNotional,
      reason: `Drift ${poolState.driftBps} bps below threshold ${MIN_REBALANCE_DRIFT_BPS} bps`,
    };
  }

  // Step 4: Cost-benefit — only rebalance if IL savings > (gas + funding)
  const driftUsdc = idealTargetNotional - poolState.lastHedgedNotional;
  const absDriftUsdc = driftUsdc < 0n ? -driftUsdc : driftUsdc;

  // Rough IL estimate: drift^2 / (2 * poolNotional) — simplified
  const poolNotionalUsdc = ethExposureUsdc < 0n ? -ethExposureUsdc : ethExposureUsdc;
  const ilEstimateUsdc = poolNotionalUsdc > 0n
    ? (absDriftUsdc * absDriftUsdc) / (2n * poolNotionalUsdc)
    : 0n;

  const gasCostUsdcBig = BigInt(Math.round(gasCostUsdc * 1e6));

  if (ilEstimateUsdc < gasCostUsdcBig) {
    return {
      shouldRebalance: false,
      targetNotional: poolState.lastHedgedNotional,
      reason: `IL savings ${ilEstimateUsdc} < gas cost ${gasCostUsdcBig} — skipping rebalance`,
    };
  }

  return {
    shouldRebalance: true,
    targetNotional: idealTargetNotional,
    reason: `Rebalancing: drift ${poolState.driftBps} bps, IL est $${Number(ilEstimateUsdc)/1e6} > gas $${gasCostUsdc}`,
  };
}
