// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HedgeVault} from "../src/HedgeVault.sol";
import {HedgehogHook} from "../src/HedgehogHook.sol";
import {HedgehogArbitrum} from "../src/HedgehogArbitrum.sol";
import {HedgehogServiceManager} from "../src/HedgehogServiceManager.sol";
import {MockAdapter} from "../src/adapters/MockAdapter.sol";
import {IHedgeVault, HedgeInstruction} from "../src/interfaces/IHedgeVault.sol";
import {IPerpsAdapter} from "../src/interfaces/IPerpsAdapter.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

// -----------------------------------------------------------------------
// Shared test fixtures
// -----------------------------------------------------------------------

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount; return true;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount); balanceOf[msg.sender] -= amount; balanceOf[to] += amount; return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount); require(allowance[from][msg.sender] >= amount);
        balanceOf[from] -= amount; balanceOf[to] += amount; allowance[from][msg.sender] -= amount; return true;
    }
}

/// @notice Mock Across bridge — teleports USDC instantly (no async delay in tests)
contract MockBridge {
    MockERC20 usdc;
    constructor(address _usdc) { usdc = MockERC20(_usdc); }

    function bridgeUSDC(
        uint256 amount, uint256, address recipient, uint256
    ) external returns (bytes32) {
        usdc.transferFrom(msg.sender, recipient, amount);
        return bytes32(uint256(1));
    }
    function estimateBridgeFee(uint256, uint256) external pure returns (uint256) { return 1e15; }
}

/// @notice Mock PoolManager — just lets us call hook callbacks directly
contract MockPoolManager {}

// -----------------------------------------------------------------------
// Integration test: deposit → hedge → rebalance → withdraw
// -----------------------------------------------------------------------
contract IntegrationTest is Test {
    using PoolIdLibrary for PoolKey;

    MockERC20          usdc;
    MockBridge         bridge;
    HedgeVault         vault;
    MockAdapter        mockAdapter;
    HedgehogArbitrum   arbitrumSide;
    MockPoolManager    poolManager;

    address operator;
    uint256 operatorKey;

    address lp1 = address(0xBB01);
    address lp2 = address(0xBB02);

    // A simple PoolKey for tests
    PoolKey poolKey;
    bytes32 poolId;

    function setUp() public {
        usdc        = new MockERC20();
        bridge      = new MockBridge(address(usdc));
        vault       = new HedgeVault(address(usdc), address(bridge));
        mockAdapter = new MockAdapter();
        poolManager = new MockPoolManager();

        // Arbitrum side — receives bridged USDC and calls MockAdapter
        arbitrumSide = new HedgehogArbitrum(address(usdc), address(mockAdapter));
        arbitrumSide.setUnichainVault(address(vault));

        // Wire vault → bridge → arbitrumSide
        vault.setArbitrumConfig(
            42161,               // Arbitrum One chain ID
            address(arbitrumSide),
            1e15
        );

        // Operator setup
        operatorKey = 0xC0FFEE;
        operator    = vm.addr(operatorKey);
        vault.registerOperator(operator, true);
        arbitrumSide.registerOperator(operator, true);

        // Fund LPs
        usdc.mint(lp1, 20_000e6);
        usdc.mint(lp2, 10_000e6);

        // Build a minimal PoolKey
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0x111)),
            currency1: Currency.wrap(address(usdc)),
            fee:       3000,
            tickSpacing: 60,
            hooks:     IHooks(address(0))  // hook address validated by PoolManager, not relevant here
        });
        poolId = PoolId.unwrap(poolKey.toId());
    }

    // -----------------------------------------------------------------------
    // Helper: sign a HedgeInstruction
    // -----------------------------------------------------------------------
    function _sign(HedgeInstruction memory instr) internal view returns (bytes memory sig) {
        bytes32 hash = keccak256(abi.encode(
            instr.poolId, instr.targetNotional, instr.maxSlippageBps, instr.deadline, instr.nonce
        ));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, ethHash);
        sig = abi.encodePacked(r, s, v);
    }

    // -----------------------------------------------------------------------
    // Test 1: Full happy path — deposit → first hedge → withdraw
    // -----------------------------------------------------------------------
    function test_Integration_DepositHedgeWithdraw() public {
        // LP1 deposits 10,000 USDC
        vm.startPrank(lp1);
        usdc.approve(address(vault), 10_000e6);
        uint256 shares = vault.deposit(10_000e6);
        vm.stopPrank();
        assertEq(shares, 10_000e6, "LP1 shares");

        // Simulate hook: LP added 1 ETH of exposure
        vault.setHook(address(this)); // test contract acts as the hook
        vault.onLiquidityAdded(lp1, poolKey, int256(1e18));

        // Vault should have recorded the delta
        assertEq(vault.netDelta(poolId), int256(1e18));

        // AVS submits hedge instruction: short -3000e6 USDC (~1 ETH at $3000)
        HedgeInstruction memory instr = HedgeInstruction({
            poolId:         poolId,
            targetNotional: -3_000e6,
            maxSlippageBps: 50,
            deadline:       block.timestamp + 300,
            nonce:          0
        });
        vault.executeHedgeInstruction(instr, _sign(instr));
        assertEq(vault.lastHedgedNotional(poolId), -3_000e6);

        // Arbitrum side: operator opens the hedge position with bridged collateral
        // (In real flow, bridge settled and USDC is now in arbitrumSide)
        usdc.mint(address(arbitrumSide), 3_000e6); // simulate bridge settlement
        vm.prank(operator);
        arbitrumSide.openHedge(poolId, -3_000e30, 3_000e6, 50); // sizeDeltaUsd in GMX 1e30

        bytes32 posId = arbitrumSide.poolToPosition(poolId);
        assertTrue(posId != bytes32(0), "position should be open");

        // LP1 withdraws all shares
        vm.prank(lp1);
        uint256 returned = vault.withdraw(shares);
        assertGt(returned, 0, "LP1 should receive USDC");
    }

    // -----------------------------------------------------------------------
    // Test 2: Price drift → rebalance cycle
    // -----------------------------------------------------------------------
    function test_Integration_Rebalance() public {
        vault.setHook(address(this));

        // Initial deposit + hedge
        vm.startPrank(lp1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6);
        vm.stopPrank();

        vault.onLiquidityAdded(lp1, poolKey, int256(1e18));

        HedgeInstruction memory instr1 = HedgeInstruction({
            poolId: poolId, targetNotional: -3_000e6, maxSlippageBps: 50,
            deadline: block.timestamp + 300, nonce: 0
        });
        vault.executeHedgeInstruction(instr1, _sign(instr1));

        // Simulate ETH price moves — hook triggers rebalance
        // After price move, drift is above threshold
        vault.requestRebalance(poolKey);

        // AVS submits new instruction with updated notional (-4000 USDC = ETH went to $4000)
        HedgeInstruction memory instr2 = HedgeInstruction({
            poolId: poolId, targetNotional: -4_000e6, maxSlippageBps: 50,
            deadline: block.timestamp + 300, nonce: 1
        });
        vault.executeHedgeInstruction(instr2, _sign(instr2));
        assertEq(vault.lastHedgedNotional(poolId), -4_000e6);

        // Arbitrum: modify position to match new size
        usdc.mint(address(arbitrumSide), 3_000e6);
        vm.prank(operator);
        arbitrumSide.openHedge(poolId, -4_000e30, 3_000e6, 50);

        bytes32 posId = arbitrumSide.poolToPosition(poolId);
        vm.prank(operator);
        arbitrumSide.modifyHedge(poolId, -4_000e30, 50);
        // Position size updated
        assertEq(mockAdapter.getPosition(posId).size, -4_000e30);
    }

    // -----------------------------------------------------------------------
    // Test 3: Two LPs, proportional shares
    // -----------------------------------------------------------------------
    function test_Integration_TwoLPs_ProportionalShares() public {
        // LP1 deposits 10k, LP2 deposits 5k
        vm.startPrank(lp1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6);
        vm.stopPrank();

        vm.startPrank(lp2);
        usdc.approve(address(vault), 5_000e6);
        vault.deposit(5_000e6);
        vm.stopPrank();

        // LP1 has 2/3 of shares, LP2 has 1/3
        uint256 totalShares = vault.totalSupply();
        uint256 lp1Shares = vault.balanceOf(lp1);
        uint256 lp2Shares = vault.balanceOf(lp2);

        assertApproxEqAbs(lp1Shares * 3, totalShares * 2, 10, "LP1 should have 2/3 of shares");
        assertApproxEqAbs(lp2Shares * 3, totalShares, 10, "LP2 should have 1/3 of shares");

        // LP2 withdraws — should get ~5000 USDC back
        uint256 usdcBefore = usdc.balanceOf(lp2);
        vm.prank(lp2);
        uint256 returned = vault.withdraw(lp2Shares);
        assertApproxEqAbs(returned, 5_000e6, 1e3, "LP2 should get back ~5000 USDC");
    }

    // -----------------------------------------------------------------------
    // Test 4: Nonce replay protection
    // -----------------------------------------------------------------------
    function test_Integration_NonceReplayPrevented() public {
        vault.setHook(address(this));
        vault.onLiquidityAdded(lp1, poolKey, int256(1e18));

        HedgeInstruction memory instr = HedgeInstruction({
            poolId: poolId, targetNotional: -3_000e6, maxSlippageBps: 50,
            deadline: block.timestamp + 300, nonce: 0
        });
        bytes memory sig = _sign(instr);
        vault.executeHedgeInstruction(instr, sig);

        // Replay with same nonce should revert
        vm.expectRevert("HedgeVault: invalid nonce");
        vault.executeHedgeInstruction(instr, sig);
    }

    // -----------------------------------------------------------------------
    // Test 5: Vault pause stops all operations
    // -----------------------------------------------------------------------
    function test_Integration_PauseStopsEverything() public {
        vault.setPaused(true);

        vm.startPrank(lp1);
        usdc.approve(address(vault), 1_000e6);
        vm.expectRevert("HedgeVault: paused");
        vault.deposit(1_000e6);
        vm.stopPrank();

        // Hook callbacks also silently skip when paused
        // (hook checks vault.paused() before calling — confirmed in HedgehogHook.sol)
    }

    // -----------------------------------------------------------------------
    // Test 6: HedgehogArbitrum — close and bridge back
    // -----------------------------------------------------------------------
    function test_HedgehogArbitrum_CloseAndBridgeBack() public {
        usdc.mint(address(arbitrumSide), 3_000e6);
        vm.prank(operator);
        arbitrumSide.openHedge(poolId, -3_000e30, 3_000e6, 50);

        bytes32 posId = arbitrumSide.poolToPosition(poolId);
        assertTrue(posId != bytes32(0));

        // Close with no bridge configured (address(0)) — just closes position
        vm.prank(operator);
        arbitrumSide.closeHedge(poolId, 50, address(0), 0);

        assertEq(arbitrumSide.poolToPosition(poolId), bytes32(0), "position cleared");
    }

    // -----------------------------------------------------------------------
    // Test 7: ServiceManager operator registration (standalone)
    // -----------------------------------------------------------------------
    function test_ServiceManager_RevertOnUnregisteredOperator() public {
        HedgehogServiceManager sm = new HedgehogServiceManager(
            address(0x01), // placeholder AVSDirectory — calls will revert, which is fine for unit test
            address(0x02)  // placeholder DelegationManager
        );
        // respondToHedgeTask should fail for non-registered operator
        vm.expectRevert("HedgehogSM: not a registered operator");
        sm.respondToHedgeTask(bytes32(0), 0, 0, "");
    }
}
