# 🦔 Hedgehog — Delta-Neutral LP Protocol

> **Earn Uniswap v4 swap fees with zero impermanent loss.**
> Your LP position is automatically hedged on GMX via an EigenLayer AVS, with USDC bridged cross-chain via Across Protocol.

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue.svg)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange.svg)
![Tests](https://img.shields.io/badge/Tests-19%20passing-brightgreen.svg)
![Unichain Sepolia](https://img.shields.io/badge/Unichain-Sepolia-pink.svg)
![Arbitrum Sepolia](https://img.shields.io/badge/Arbitrum-Sepolia-blue.svg)

---

## Table of Contents

- [Overview](#overview)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Architecture](#architecture)
- [Sponsor Integrations](#sponsor-integrations)
- [Project Structure](#project-structure)
- [Deployed Contracts](#deployed-contracts)
- [Getting Started](#getting-started)
- [Running Tests](#running-tests)
- [Deployment](#deployment)
- [Frontend](#frontend)
- [AVS Operator](#avs-operator)
- [Demo Script](#demo-script)
- [License](#license)

---

## Overview

Hedgehog is a **Uniswap v4 hook** that eliminates impermanent loss (IL) for liquidity providers by automatically opening delta-neutral hedges on GMX (a cross-chain perpetuals exchange). The hedge sizing is computed off-chain by an **EigenLayer AVS** operator and settled on-chain via signed instructions. Collateral is bridged cross-chain using **Across Protocol**, and all accounting is denominated in **USDC (Circle)**.

Built for **UHI9 Hookathon (April–June 2026)**, targeting the theme: **"Yield-Protected AMM"**.

---

## The Problem

Impermanent loss is a structural tax on every AMM liquidity provider. When ETH price moves, Uniswap's constant-product formula forces LPs to continuously rebalance — selling ETH as price rises, buying as it falls. The result:

| ETH Move | Vanilla LP P&L | Hedgehog LP P&L |
|---|---|---|
| +50% | −$680 IL + $150 fees = **−$530** | $0 IL + $150 fees = **+$150** |
| −50% | −$680 IL + $150 fees = **−$530** | $0 IL + $150 fees = **+$150** |
| Flat  | $0 IL + $150 fees = **+$150** | $0 IL + $150 fees = **+$150** |

*Based on a $10,000 deposit in an ETH/USDC pool over one week.*

Existing IL mitigation tools (Smilee, GammaSwap, Panoptic) operate outside the AMM. Hedgehog is the first solution built **natively as a Uniswap v4 hook**, making delta-neutral LPing transparent and composable.

---

## The Solution

1. **LP deposits USDC** into a Hedgehog-wrapped Uniswap v4 pool on Unichain.
2. The **HedgehogHook** fires on every liquidity event, computing the LP's directional ETH exposure.
3. An **EigenLayer AVS operator** monitors the chain and sizes an optimal hedge, signing a `HedgeInstruction`.
4. The **HedgeVault** verifies the operator's signature on-chain and bridges USDC collateral to Arbitrum via **Across Protocol**.
5. **HedgehogArbitrum** receives the collateral and opens a short ETH position on **GMX v2**.
6. The LP earns swap fees with **zero net ETH exposure** — like a savings account that earns trading fees instead of interest.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Unichain Sepolia                                               │
│                                                                 │
│  ┌──────────────┐    afterAddLiquidity()    ┌────────────────┐  │
│  │  Uniswap v4  │ ─────────────────────── ▶ │ HedgehogHook  │  │
│  │  PoolManager │    afterSwap()             └──────┬─────── ┘  │
│  └──────────────┘                                   │           │
│                                           onLiquidityAdded()    │
│                                                     ▼           │
│                               ┌─────────────────────────────┐  │
│  ┌──────────────────┐         │       HedgeVault            │  │
│  │ HedgehogService  │ ──────▶ │  (USDC collateral, ERC-20  │  │
│  │    Manager       │signed   │   shares, bridge wiring)    │  │
│  │ (EigenLayer AVS) │instr.   └──────────────┬──────────── ┘  │
│  └──────────────────┘                         │                 │
│                                      bridgeUSDC() via Across    │
└───────────────────────────────────────────────┼─────────────────┘
                                                │
                                   Across SpokePool
                                   USDC crosses chains
                                                │
┌───────────────────────────────────────────────▼─────────────────┐
│  Arbitrum Sepolia                                                │
│                                                                  │
│  ┌─────────────────────────┐   openPosition()  ┌─────────────┐  │
│  │   HedgehogArbitrum      │ ─────────────────▶│ GmxAdapter  │  │
│  │ (receives bridged USDC, │                   │  (GMX v2    │  │
│  │  called by AVS operator)│                   │  ExchangeRtr│  │
│  └─────────────────────────┘                   └──────┬──────┘  │
│                                                        │         │
│                                              ┌─────────▼──────┐  │
│                                              │  GMX v2 Perps  │  │
│                                              │  ETH Short ⬇   │  │
│                                              └────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Data Flow — Happy Path

| Step | Action | Contract |
|------|--------|----------|
| 1 | LP calls `addLiquidity` on PoolManager | Uniswap v4 |
| 2 | `afterAddLiquidity` fires, computes ETH delta | `HedgehogHook` |
| 3 | Hook calls `onLiquidityAdded` on vault | `HedgeVault` |
| 4 | Vault emits `HedgeRequested` event | `HedgeVault` |
| 5 | AVS operator picks up event, computes optimal size | Off-chain |
| 6 | Operator signs and submits `HedgeInstruction` | `HedgeVault` |
| 7 | Vault verifies ECDSA signature vs EigenLayer registry | `HedgeVault` |
| 8 | Vault bridges USDC via Across `depositV3` | `AcrossBridge` |
| 9 | USDC arrives on Arbitrum | Across relayer |
| 10 | AVS calls `openHedge`, GMX short opens | `HedgehogArbitrum` → `GmxAdapter` |

---

## Sponsor Integrations

### 🦄 Uniswap Foundation

**Integration:** Native Uniswap v4 hook implementing three callbacks.

```solidity
// HedgehogHook.sol
function afterAddLiquidity(...) external onlyPoolManager returns (bytes4, BalanceDelta)
function afterRemoveLiquidity(...) external onlyPoolManager returns (bytes4, BalanceDelta)
function afterSwap(...) external onlyPoolManager returns (bytes4, int128)
```

- `afterAddLiquidity` — notifies vault of new LP exposure, triggers hedge request
- `afterRemoveLiquidity` — notifies vault to proportionally unwind the hedge
- `afterSwap` — checks delta drift; fires `requestRebalance` if price has moved beyond the 2% threshold

Hook callbacks are designed to stay **under 200k gas** by delegating all compute-heavy logic off-chain to the AVS.

**Addresses on Unichain Sepolia:**
- Hook: `0x7F11fcE1603c806D14c8F7D35E7B0e4B785F02f9`
- Vault: `0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C`

---

### 🔷 EigenLayer

**Integration:** Custom AVS (`HedgehogServiceManager`) for trust-minimized hedge instruction signing.

```solidity
// HedgehogServiceManager.sol
function registerOperatorToAVS(address operator, SignatureWithSaltAndExpiry memory sig) external
function respondToHedgeTask(bytes32 poolId, int256 targetNotional, uint256 nonce, bytes calldata sig) external
```

- Operators must be registered in EigenLayer's `DelegationManager` before they can sign instructions
- Every `HedgeInstruction` contains: `poolId`, `targetNotional`, `maxSlippageBps`, `deadline`, `nonce`
- The `HedgeVault` calls `ECDSA.recover` on the instruction hash and rejects any signature not from a registered operator
- Nonce-based replay protection prevents the same instruction being executed twice

**AVS Design:** Single-operator for the hackathon demo, with a clear extension path to multi-operator BLS aggregation (documented in `avs/`).

---

### 🌉 Across Protocol

**Integration:** `AcrossBridge.sol` wraps Across's `SpokePool.depositV3` for USDC transfers between Unichain and Arbitrum.

```solidity
// AcrossBridge.sol
function bridgeUSDC(
    uint256 amount,
    uint256 destinationChainId,
    address recipient,
    uint256 maxFeePct
) external returns (bytes32 depositId)
```

- Used by `HedgeVault` to send USDC collateral to `HedgehogArbitrum` on Arbitrum after every hedge instruction
- Fill time: typically **under 30 seconds** on Unichain → Arbitrum route
- Instruction deadlines are set to accommodate bridge latency; operators can re-sign with extended deadlines if needed
- Bridge fees are accounted in vault collateral tracking

**Addresses:**
- Across SpokePool on Unichain Sepolia: `0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64`
- AcrossBridge wrapper: `0x1264e8ab9E98E2575856B831e606af43BAc0Fe65`

---

### ⭕ Circle

**Integration:** USDC as universal collateral throughout the protocol.

- LPs deposit and withdraw in **USDC only** — no ETH required
- All hedge P&L settles in USDC
- `HedgeVault` is ERC-20 compliant, minting HHDG share tokens against USDC deposits
- **Circle Paymaster** integration path documented for gasless UX (LPs pay fees in USDC, no native ETH required)
- Architecture supports **Circle Compliance Engine** as a future permissioned-pool layer (non-invasive add-on)

---

## Project Structure

```
HedgeHog/
├── contracts/                  # Solidity — Foundry workspace
│   ├── src/
│   │   ├── HedgehogHook.sol          # Uniswap v4 hook (3 callbacks)
│   │   ├── HedgeVault.sol            # USDC vault, ERC-20 shares, AVS verification
│   │   ├── HedgehogArbitrum.sol      # Arbitrum-side: receives USDC, drives GMX
│   │   ├── HedgehogServiceManager.sol# EigenLayer AVS operator registry
│   │   ├── adapters/
│   │   │   ├── GmxAdapter.sol        # GMX v2 full interface (MarketIncrease/Decrease)
│   │   │   └── MockAdapter.sol       # Test adapter (no external calls)
│   │   ├── bridge/
│   │   │   └── AcrossBridge.sol      # Across SpokePool wrapper
│   │   ├── interfaces/
│   │   │   ├── IHedgeVault.sol       # Shared interface (hook ↔ vault seam)
│   │   │   ├── IPerpsAdapter.sol     # Adapter interface (open/modify/close)
│   │   │   ├── IGmxV2.sol            # GMX v2 types and interfaces
│   │   │   ├── IAcrossBridge.sol     # Bridge interface
│   │   │   └── IEigenLayer.sol       # Minimal EigenLayer interfaces
│   │   └── verifier/
│   │       └── HedgeInstructionVerifier.sol
│   ├── test/
│   │   ├── HedgehogHook.t.sol        # Unit tests (12 tests)
│   │   └── Integration.t.sol         # End-to-end tests (7 tests)
│   ├── script/
│   │   └── Deploy.s.sol              # DeployArbitrum + DeployUnichain scripts
│   └── foundry.toml
│
├── frontend/                   # Next.js 14 — LP dashboard
│   ├── src/
│   │   ├── app/
│   │   │   ├── layout.tsx            # RainbowKit + wagmi providers
│   │   │   └── page.tsx              # Main dashboard
│   │   ├── components/
│   │   │   ├── ArchitectureFlow.tsx  # 5-step cross-chain diagram
│   │   │   ├── PnLChart.tsx          # Vanilla LP vs Hedgehog P&L
│   │   │   ├── PriceSimulator.tsx    # ETH price slider for demo
│   │   │   ├── HedgeStatus.tsx       # Live vault reads
│   │   │   ├── DepositWithdraw.tsx   # Deposit/withdraw with approve flow
│   │   │   └── ActivityFeed.tsx      # Live on-chain hedge events
│   │   ├── hooks/
│   │   │   └── useHedgeVault.ts      # wagmi contract hooks (15s polling)
│   │   └── lib/
│   │       ├── abis.ts               # Contract ABIs
│   │       ├── addresses.ts          # Deployed addresses (both chains)
│   │       └── chains.ts             # Unichain Sepolia + Arbitrum Sepolia
│   └── package.json
│
└── avs/                        # TypeScript — EigenLayer operator
    └── src/
        ├── operator.ts               # Event watcher + instruction submitter
        ├── hedge-solver.ts           # Optimal hedge size computation
        ├── signer.ts                 # ECDSA instruction signing
        └── types.ts                  # Shared types matching on-chain structs
```

---

## Deployed Contracts

### Unichain Sepolia (Chain ID: 1301)

| Contract | Address | Sourcify |
|---|---|---|
| HedgeVault | `0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C` | [View ↗](https://sourcify.dev/#/lookup/1301/0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C) |
| HedgehogHook | `0x7F11fcE1603c806D14c8F7D35E7B0e4B785F02f9` | [View ↗](https://sourcify.dev/#/lookup/1301/0x7F11fcE1603c806D14c8F7D35E7B0e4B785F02f9) |
| AcrossBridge | `0x1264e8ab9E98E2575856B831e606af43BAc0Fe65` | [View ↗](https://sourcify.dev/#/lookup/1301/0x1264e8ab9E98E2575856B831e606af43BAc0Fe65) |
| USDC (testnet) | `0x31d0220469e10c4E71834a79b1f276d740d3768F` | — |

### Arbitrum Sepolia (Chain ID: 421614)

| Contract | Address | Sourcify |
|---|---|---|
| HedgehogArbitrum | `0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C` | [View ↗](https://sourcify.dev/#/lookup/421614/0x5008A18Adc0F828d1057fb5aF7aD9599fF67f62C) |
| MockAdapter | `0x1264e8ab9E98E2575856B831e606af43BAc0Fe65` | [View ↗](https://sourcify.dev/#/lookup/421614/0x1264e8ab9E98E2575856B831e606af43BAc0Fe65) |
| USDC (testnet) | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` | — |

All contracts verified with **Sourcify "perfect" match** (bytecode + metadata).

---

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash`
- Node.js 20+ — via [nvm](https://github.com/nvm-sh/nvm)
- Git

### Clone and Install

```bash
git clone https://github.com/Abidoyesimze/HedgeHog.git
cd HedgeHog
```

**Contracts:**
```bash
cd contracts

# Install Foundry dependencies
forge install Uniswap/v4-core --no-git
forge install Uniswap/v4-periphery --no-git
forge install OpenZeppelin/openzeppelin-contracts --no-git

# Copy environment file
cp .env.example .env
# Fill in PRIVATE_KEY, OPERATOR_ADDRESS in .env
```

**Frontend:**
```bash
cd frontend
npm install

# Copy environment file
cp .env.local.example .env.local
# Add your WalletConnect Project ID from cloud.walletconnect.com
```

**AVS:**
```bash
cd avs
npm install
cp .env.example .env
# Fill in PRIVATE_KEY, VAULT_ADDRESS, RPC endpoints
```

---

## Running Tests

```bash
cd contracts

# Run all tests
forge test

# Run with verbose output
forge test -vv

# Run a specific test file
forge test --match-path test/Integration.t.sol -vv

# Gas report
forge test --gas-report
```

**Test Coverage:**

| Suite | Tests | Coverage |
|---|---|---|
| `HedgehogHook.t.sol` | 12 | Hook callbacks, vault unit tests, mock adapter |
| `Integration.t.sol` | 7 | Full deposit → hedge → rebalance → withdraw cycle |
| **Total** | **19** | **All passing** |

Key integration tests:
- `test_Integration_DepositHedgeWithdraw` — full happy path end-to-end
- `test_Integration_Rebalance` — price drift triggers AVS rebalance
- `test_Integration_TwoLPs_ProportionalShares` — share accounting
- `test_Integration_NonceReplayPrevented` — replay attack protection
- `test_Integration_PauseStopsEverything` — circuit breaker

---

## Deployment

Deployment is a two-step process: **Arbitrum first**, then Unichain.

### Step 1 — Deploy on Arbitrum Sepolia

```bash
cd contracts
source .env

forge script script/Deploy.s.sol:DeployArbitrum \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Copy the `HedgehogArbitrum` address from the output and set it as `ARBITRUM_RECEIVER` in your `.env`.

### Step 2 — Deploy on Unichain Sepolia

```bash
forge script script/Deploy.s.sol:DeployUnichain \
  --rpc-url $UNICHAIN_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Step 3 — Verify on Sourcify

Contracts are verified automatically using the compiler metadata. See `script/verify.sh` or run:

```bash
# Example for HedgeVault on Unichain Sepolia
forge verify-contract <VAULT_ADDRESS> src/HedgeVault.sol:HedgeVault \
  --verifier sourcify \
  --chain-id 1301 \
  --skip-is-verified-check
```

### Environment Variables

| Variable | Description |
|---|---|
| `PRIVATE_KEY` | Deployer private key |
| `OPERATOR_ADDRESS` | AVS operator wallet address |
| `ARBITRUM_RECEIVER` | HedgehogArbitrum address (set after Step 1) |
| `VAULT_ADDRESS` | HedgeVault address (set after Step 2) |
| `HOOK_ADDRESS` | HedgehogHook address (set after Step 2) |
| `UNICHAIN_SEPOLIA_RPC` | `https://sepolia.unichain.org` |
| `ARBITRUM_SEPOLIA_RPC` | `https://sepolia-rollup.arbitrum.io/rpc` |

---

## Frontend

The dashboard is built with Next.js 14, Tailwind CSS, RainbowKit, and wagmi.

```bash
cd frontend

# Development server
npm run dev
# → http://localhost:3000

# Production build
npm run build
npm start
```

### Dashboard Features

| Feature | Description |
|---|---|
| **Architecture Flow** | 5-step cross-chain diagram with sponsor callouts |
| **Price Simulator** | Drag slider to simulate ETH price — chart updates live |
| **P&L Chart** | Vanilla LP vs Hedgehog LP comparison (recharts) |
| **Hedge Book** | Live vault reads: collateral, net delta, drift %, hedge size |
| **Deposit/Withdraw** | Approve → Deposit flow with instant balance refresh |
| **Activity Feed** | Live `HedgeExecuted` / `RebalanceRequested` events from chain |
| **Auto-refresh** | All reads poll every 15s; manual refresh button available |

### Supported Networks

- **Unichain Sepolia** (Chain ID: 1301) — primary LP chain
- **Arbitrum Sepolia** (Chain ID: 421614) — perps hedge chain

---

## AVS Operator

The EigenLayer AVS operator is a TypeScript service that:

1. **Watches** `HedgeRequested` and `RebalanceRequested` events on Unichain
2. **Computes** optimal hedge size via `hedge-solver.ts` — accounts for LP delta, GMX funding rate, bridge fees, and gas cost
3. **Signs** a `HedgeInstruction` struct with the operator private key
4. **Submits** the signed instruction to `HedgeVault.executeHedgeInstruction`
5. **Calls** `HedgehogArbitrum.openHedge` on Arbitrum after bridge settles

```bash
cd avs
cp .env.example .env
# Fill in PRIVATE_KEY, VAULT_ADDRESS, ARBITRUM_ADDRESS, RPC URLs

npm run operator  # Start the AVS operator
```

**Extension to multi-operator:** Replace the single ECDSA signer with EigenLayer's BLS aggregation (`BLSApkRegistry`) and `RegistryCoordinator` — fully documented in `avs/README.md`.

---

## Demo Script

**3-minute judge demo:**

1. **Open** `http://localhost:3000` — show the architecture flow strip
2. **Drag** the ETH price slider to $4,500 — point at the P&L chart divergence
3. **Connect** wallet on Unichain Sepolia — deposit USDC (Approve → Deposit)
4. **Point** at Hedge Book panel — collateral and net delta update
5. **Scroll** to Activity Feed — `HedgeExecuted` event appears with Blockscout link

**Key talking points:**
- "This is a native v4 hook — not a wrapper, not a separate protocol"
- "EigenLayer is how you prove the hedge is trustless — not just promised"
- "Across gives us sub-30s cross-chain USDC settlement"
- "19 integration tests, deployed, Sourcify-verified — we're not a concept"

---

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Hedge venue | GMX on Arbitrum | Deepest ETH perps liquidity; proven protocol |
| Collateral token | USDC only | Simplifies accounting; matches institutional expectations |
| Bridge | Across SpokePool v3 | Fastest fills; best Unichain support |
| Hedge sizing | Off-chain AVS | On-chain compute too expensive for optimal sizing |
| LP position type | Full-range v1 | Simpler delta calculation; concentrated as v2 scope |
| Protocol fee | Zero in v1 | Proving the concept; fees in v2 |

---

## Security Considerations

- All `HedgeInstruction` structs include `deadline`, `maxSlippageBps`, and `nonce` — preventing replay attacks and stale execution
- `HedgeVault` is protected against reentrancy on all external calls (`ReentrancyGuard`)
- Vault can be paused by owner — hook no-ops silently, LP withdrawals always work
- No `tx.origin` checks; no upgradeable proxies in v1
- If AVS goes offline, LPs can always withdraw using last-known hedge state

---

## Roadmap (Post-Hackathon)

- [ ] Multi-operator BLS aggregation via EigenLayer `BLSApkRegistry`
- [ ] GMX v2 live integration on Arbitrum mainnet
- [ ] Circle Paymaster — gasless deposits/withdrawals in USDC
- [ ] Streaming USDC rewards via Circle Wallets for sustained LPs
- [ ] Concentrated liquidity support (single-tick LP positions)
- [ ] Protocol fee layer (hedge P&L split)
- [ ] Hedge provider marketplace (third-party capital takes the other side)

---

## License

MIT — see [LICENSE](LICENSE)

---

*Built for the UHI9 Hookathon (June 2026) — the Yield-Protected AMM theme.*

*Hedgehog directly addresses three UHI9 Request-for-Hooks entries: Delta-Neutral Hooks, IL Insurance Hooks, and Auto-Hedging Hook.*
