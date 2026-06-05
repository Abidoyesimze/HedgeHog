import "dotenv/config";
import { createPublicClient, createWalletClient, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { solveHedge } from "./hedge-solver";
import { signInstruction } from "./signer";
import { HedgeInstruction, PoolState } from "./types";

// -------------------------------------------------------------------------
// Config from environment
// -------------------------------------------------------------------------
const PRIVATE_KEY     = process.env.OPERATOR_PRIVATE_KEY as `0x${string}`;
const VAULT_ADDRESS   = process.env.VAULT_ADDRESS as `0x${string}`;
const UNICHAIN_RPC    = process.env.UNICHAIN_SEPOLIA_RPC!;
const POLL_INTERVAL   = parseInt(process.env.POLL_INTERVAL_MS ?? "12000"); // 1 block

// -------------------------------------------------------------------------
// ABI fragments
// -------------------------------------------------------------------------
const VAULT_ABI = parseAbi([
  "function netDelta(bytes32 poolId) view returns (int256)",
  "function deltaDriftBps(bytes32 poolId) view returns (uint256)",
  "function operatorNonce(address) view returns (uint256)",
  "function executeHedgeInstruction((bytes32,int256,uint256,uint256,uint256), bytes) external",
  "event RebalanceRequested(bytes32 indexed poolId, int256 currentDrift)",
  "event HedgeRequested(bytes32 indexed poolId, int256 targetNotional)",
]);

// -------------------------------------------------------------------------
// Main operator loop
// -------------------------------------------------------------------------
async function main() {
  console.log("Hedgehog AVS operator starting...");

  const account = privateKeyToAccount(PRIVATE_KEY);
  const transport = http(UNICHAIN_RPC);

  const publicClient = createPublicClient({ transport });
  const walletClient = createWalletClient({ account, transport });

  // Watch for RebalanceRequested events from the vault
  const unwatch = publicClient.watchContractEvent({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    eventName: "RebalanceRequested",
    onLogs: async (logs) => {
      for (const log of logs) {
        const poolId = (log as any).args.poolId as `0x${string}`;
        console.log(`[AVS] RebalanceRequested for pool ${poolId}`);
        await handleRebalance(poolId, publicClient, walletClient, account.address);
      }
    },
  });

  // Also watch HedgeRequested (new LP position)
  publicClient.watchContractEvent({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    eventName: "HedgeRequested",
    onLogs: async (logs) => {
      for (const log of logs) {
        const poolId = (log as any).args.poolId as `0x${string}`;
        console.log(`[AVS] HedgeRequested for pool ${poolId}`);
        await handleRebalance(poolId, publicClient, walletClient, account.address);
      }
    },
  });

  console.log(`[AVS] Watching vault at ${VAULT_ADDRESS} on Unichain Sepolia`);
  console.log(`[AVS] Operator address: ${account.address}`);

  // Keep process alive
  await new Promise(() => {});
}

async function handleRebalance(
  poolId: `0x${string}`,
  publicClient: any,
  walletClient: any,
  operatorAddress: `0x${string}`
) {
  try {
    // 1. Read current pool state from vault
    const [netDelta, driftBps, nonce] = await Promise.all([
      publicClient.readContract({ address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "netDelta", args: [poolId] }),
      publicClient.readContract({ address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "deltaDriftBps", args: [poolId] }),
      publicClient.readContract({ address: VAULT_ADDRESS, abi: VAULT_ABI, functionName: "operatorNonce", args: [operatorAddress] }),
    ]);

    const poolState: PoolState = {
      poolId,
      netDelta: netDelta as bigint,
      lastHedgedNotional: 0n, // TODO: read from vault storage
      driftBps: driftBps as bigint,
    };

    // 2. Fetch ETH price (mock for now — replace with Chainlink or Pyth in Week 2)
    const ethPriceUsd = await fetchEthPrice();

    // 3. Run hedge solver
    const solution = solveHedge({
      poolState,
      ethPriceUsd,
      fundingRate: { symbol: "ETH", hourlyRate: 0.01, nextFundingTime: 0 },
      gasCostUsdc: 2.0, // ~$2 gas estimate for testnet
    });

    console.log(`[AVS] Solver result: ${solution.reason}`);

    if (!solution.shouldRebalance) return;

    // 4. Build and sign instruction
    const instruction: HedgeInstruction = {
      poolId,
      targetNotional: solution.targetNotional,
      maxSlippageBps: 50n,
      deadline: BigInt(Math.floor(Date.now() / 1000) + 300), // 5 min deadline
      nonce: nonce as bigint,
    };

    const signature = await signInstruction(instruction, PRIVATE_KEY);

    // 5. Submit on-chain
    const hash = await walletClient.writeContract({
      address: VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: "executeHedgeInstruction",
      args: [
        [instruction.poolId, instruction.targetNotional, instruction.maxSlippageBps, instruction.deadline, instruction.nonce],
        signature,
      ],
    });

    console.log(`[AVS] Hedge instruction submitted: ${hash}`);
  } catch (err) {
    console.error(`[AVS] Error handling rebalance for pool ${poolId}:`, err);
  }
}

async function fetchEthPrice(): Promise<number> {
  // TODO Week 2: query Chainlink or Pyth on-chain for live ETH/USD price
  // Using a hardcoded mock for now
  return 3000;
}

main().catch(console.error);
