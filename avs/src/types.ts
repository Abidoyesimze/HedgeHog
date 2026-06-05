export interface HedgeInstruction {
  poolId: `0x${string}`;
  targetNotional: bigint;   // positive = long, negative = short
  maxSlippageBps: bigint;
  deadline: bigint;
  nonce: bigint;
}

export interface PoolState {
  poolId: `0x${string}`;
  netDelta: bigint;          // current ETH exposure (1e18 units)
  lastHedgedNotional: bigint; // last hedged notional (USDC 1e6)
  driftBps: bigint;
}

export interface FundingRateData {
  symbol: string;
  hourlyRate: number;        // annualized hourly funding rate
  nextFundingTime: number;   // unix timestamp
}

export interface HedgeSolverInput {
  poolState: PoolState;
  ethPriceUsd: number;
  fundingRate: FundingRateData;
  gasCostUsdc: number;
}

export interface HedgeSolverOutput {
  shouldRebalance: boolean;
  targetNotional: bigint;   // target short notional in USDC (negative)
  reason: string;
}
