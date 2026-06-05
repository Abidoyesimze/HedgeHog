# Hedgehog — Smart Contracts

Foundry workspace containing all on-chain components of the Hedgehog delta-neutral LP protocol.

## Contracts

| Contract | Chain | Description |
|---|---|---|
| `HedgehogHook.sol` | Unichain | Uniswap v4 hook — fires on add/remove liquidity and swap |
| `HedgeVault.sol` | Unichain | USDC vault, ERC-20 shares, AVS instruction verification, bridge wiring |
| `HedgehogArbitrum.sol` | Arbitrum | Receives bridged USDC, drives GMX perps positions |
| `HedgehogServiceManager.sol` | Unichain | EigenLayer AVS operator registry + task logging |
| `GmxAdapter.sol` | Arbitrum | Full GMX v2 MarketIncrease/Decrease order interface |
| `MockAdapter.sol` | Any | Test adapter — no external calls |
| `AcrossBridge.sol` | Unichain | Across SpokePool `depositV3` wrapper |

## Setup

```bash
# Install dependencies
forge install Uniswap/v4-core --no-git
forge install Uniswap/v4-periphery --no-git
forge install OpenZeppelin/openzeppelin-contracts --no-git

cp .env.example .env
```

## Build & Test

```bash
forge build
forge test -vv          # 19 tests, all passing
forge test --gas-report
```

## Deploy

```bash
# 1. Deploy Arbitrum side first
forge script script/Deploy.s.sol:DeployArbitrum --rpc-url $ARBITRUM_SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast

# 2. Set ARBITRUM_RECEIVER in .env, then deploy Unichain side
forge script script/Deploy.s.sol:DeployUnichain --rpc-url $UNICHAIN_SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast
```

See the [root README](../README.md) for full documentation.
