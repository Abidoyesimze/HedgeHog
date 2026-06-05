// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {HedgehogHook} from "../src/HedgehogHook.sol";
import {HedgeVault} from "../src/HedgeVault.sol";
import {HedgehogArbitrum} from "../src/HedgehogArbitrum.sol";
import {HedgehogServiceManager} from "../src/HedgehogServiceManager.sol";
import {AcrossBridge} from "../src/bridge/AcrossBridge.sol";
import {GmxAdapter} from "../src/adapters/GmxAdapter.sol";
import {MockAdapter} from "../src/adapters/MockAdapter.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHedgeVault} from "../src/interfaces/IHedgeVault.sol";

// ============================================================
// UNICHAIN SEPOLIA — deployed by DeployUnichain
// ============================================================
contract DeployUnichain is Script {
    // Unichain Sepolia — Uniswap v4 PoolManager
    address constant POOL_MANAGER = 0x000b036B58A818B1bc34D502d3FE730Db40BaE8c;

    // USDC on Unichain Sepolia (Circle bridged)
    address constant USDC = 0x31d0220469e10c4E71834a79b1f276d740d3768F;

    // Across Protocol SpokePool on Unichain Sepolia
    address constant ACROSS_SPOKE_POOL = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;

    // EigenLayer AVSDirectory on Unichain Sepolia (or Holesky if bridging)
    address constant AVS_DIRECTORY    = 0x0000000000000000000000000000000000000000; // TODO: fill post-launch
    address constant DELEGATION_MANAGER = 0x0000000000000000000000000000000000000000; // TODO: fill

    // Arbitrum Sepolia chain ID
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    // Drift threshold: 2% price move triggers rebalance
    uint256 constant DRIFT_THRESHOLD_BPS = 200;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        // Read Arbitrum receiver address from env (deployed in DeployArbitrum first)
        address arbitrumReceiver = vm.envAddress("ARBITRUM_RECEIVER");

        console.log("=== Deploying Hedgehog on Unichain Sepolia ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // 1. Across Bridge wrapper
        AcrossBridge bridge = new AcrossBridge(ACROSS_SPOKE_POOL, USDC);
        console.log("AcrossBridge:           ", address(bridge));

        // 2. HedgeVault
        HedgeVault vault = new HedgeVault(USDC, address(bridge));
        console.log("HedgeVault:             ", address(vault));

        // 3. Wire Arbitrum config
        vault.setArbitrumConfig(ARBITRUM_SEPOLIA_CHAIN_ID, arbitrumReceiver, 1e15);

        // 4. HedgehogHook
        //    NOTE: Hook address must have correct permission bits set.
        //    Use HookMiner (v4-periphery) to find the right salt before deploying.
        //    Address bits required: afterAddLiquidity | afterRemoveLiquidity | afterSwap
        //    Binary mask: 0b...001010001000... = check Hooks.sol for exact values
        //    For testnet we deploy without mining — hook callbacks won't be invoked until
        //    pool is initialized pointing to the correctly-mined address.
        //
        // bytes32 salt = _mineHookSalt(deployer, address(vault));
        // HedgehogHook hook = new HedgehogHook{salt: salt}(
        //     IPoolManager(POOL_MANAGER), IHedgeVault(address(vault)), DRIFT_THRESHOLD_BPS
        // );
        // vault.setHook(address(hook));
        // console.log("HedgehogHook:          ", address(hook));
        //
        // For now deploy without salt (use MockHook for testing):
        HedgehogHook hook = new HedgehogHook(
            IPoolManager(POOL_MANAGER),
            IHedgeVault(address(vault)),
            DRIFT_THRESHOLD_BPS
        );
        vault.setHook(address(hook));
        console.log("HedgehogHook:           ", address(hook));

        // 5. EigenLayer Service Manager (only if AVS addresses are filled in)
        if (AVS_DIRECTORY != address(0)) {
            HedgehogServiceManager sm = new HedgehogServiceManager(AVS_DIRECTORY, DELEGATION_MANAGER);
            console.log("HedgehogServiceManager: ", address(sm));
        }

        // 6. Register the operator from env
        address operatorAddr = vm.envOr("OPERATOR_ADDRESS", address(0));
        if (operatorAddr != address(0)) {
            vault.registerOperator(operatorAddr, true);
            console.log("Registered operator:    ", operatorAddr);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Unichain Sepolia deployment complete ===");
        console.log("Set these in your .env:");
        console.log("  VAULT_ADDRESS=", address(vault));
        console.log("  HOOK_ADDRESS= ", address(hook));
        console.log("  BRIDGE_ADDRESS=", address(bridge));
    }
}

// ============================================================
// ARBITRUM SEPOLIA — deployed by DeployArbitrum (run FIRST)
// ============================================================
contract DeployArbitrum is Script {
    // USDC on Arbitrum Sepolia
    address constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

    // GMX v2 on Arbitrum Sepolia
    // NOTE: GMX v2 does not have a canonical Arbitrum Sepolia deployment as of June 2026.
    // For testnet demo, we use MockAdapter. GmxAdapter is wired for Arbitrum mainnet fork tests.
    address constant GMX_EXCHANGE_ROUTER  = 0x0000000000000000000000000000000000000000;
    address constant GMX_READER           = 0x0000000000000000000000000000000000000000;
    address constant GMX_DATA_STORE       = 0x0000000000000000000000000000000000000000;
    address constant GMX_ORDER_VAULT      = 0x0000000000000000000000000000000000000000;
    address constant GMX_ETH_USD_MARKET   = 0x0000000000000000000000000000000000000000;
    address constant WETH                 = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;

    // Across SpokePool on Arbitrum Sepolia
    address constant ACROSS_SPOKE_POOL = 0x7E63A5f1a8F0B4d0934B2f2327DAED3F6bb2ee75;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        console.log("=== Deploying Hedgehog on Arbitrum Sepolia ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // For testnet: use MockAdapter (GMX v2 not on Arb Sepolia)
        // For mainnet fork tests: deploy GmxAdapter with real addresses above
        MockAdapter adapter = new MockAdapter();
        console.log("MockAdapter (perps):    ", address(adapter));

        // HedgehogArbitrum — receives bridged USDC and manages positions
        HedgehogArbitrum arb = new HedgehogArbitrum(USDC, address(adapter));
        console.log("HedgehogArbitrum:       ", address(arb));

        // Register operator
        address operatorAddr = vm.envOr("OPERATOR_ADDRESS", address(0));
        if (operatorAddr != address(0)) {
            arb.registerOperator(operatorAddr, true);
            console.log("Registered operator:    ", operatorAddr);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Arbitrum Sepolia deployment complete ===");
        console.log("Set in .env before running DeployUnichain:");
        console.log("  ARBITRUM_RECEIVER=", address(arb));
    }
}
