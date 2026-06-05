// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockAdapter} from "../src/adapters/MockAdapter.sol";
import {HedgeVault} from "../src/HedgeVault.sol";
import {HedgeInstructionVerifier} from "../src/verifier/HedgeInstructionVerifier.sol";
import {IHedgeVault, HedgeInstruction} from "../src/interfaces/IHedgeVault.sol";
import {IPerpsAdapter, PositionState} from "../src/interfaces/IPerpsAdapter.sol";

// -----------------------------------------------------------------------
// Minimal mock ERC20 for USDC
// -----------------------------------------------------------------------
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8  public decimals = 6;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

// -----------------------------------------------------------------------
// Mock bridge — does nothing (Week 2: replace with real Across bridge test)
// -----------------------------------------------------------------------
contract MockBridge {
    function bridgeUSDC(uint256, uint256, address, uint256) external pure returns (bytes32) {
        return bytes32(uint256(1));
    }
    function estimateBridgeFee(uint256, uint256) external pure returns (uint256) {
        return 1e15;
    }
}

// -----------------------------------------------------------------------
// Test suite
// -----------------------------------------------------------------------
contract HedgehogHookTest is Test {
    MockAdapter  adapter;
    MockERC20    usdc;
    MockBridge   bridge;
    HedgeVault   vault;

    address operator;
    uint256 operatorKey;

    address lp1 = address(0xAA01);
    address lp2 = address(0xAA02);

    function setUp() public {
        adapter = new MockAdapter();
        usdc    = new MockERC20();
        bridge  = new MockBridge();
        vault   = new HedgeVault(address(usdc), address(bridge));

        // Generate operator key pair
        operatorKey = 0xBEEF;
        operator    = vm.addr(operatorKey);

        // Register operator in vault
        vault.registerOperator(operator, true);

        // Give LP1 and LP2 some USDC
        usdc.mint(lp1, 10_000e6);
        usdc.mint(lp2, 5_000e6);
    }

    // -----------------------------------------------------------------------
    // MockAdapter tests
    // -----------------------------------------------------------------------

    function test_MockAdapter_OpenShort() public {
        bytes32 posId = adapter.openPosition(-1e18, 2000e6, 50);
        PositionState memory pos = adapter.getPosition(posId);
        assertEq(pos.size, -1e18, "wrong size");
        assertEq(pos.collateral, 2000e6, "wrong collateral");
        assertEq(pos.entryPrice, 2000e18, "wrong entry price");
    }

    function test_MockAdapter_ModifyPosition() public {
        bytes32 posId = adapter.openPosition(-1e18, 2000e6, 50);
        adapter.modifyPosition(posId, -2e18, 50);
        assertEq(adapter.getPosition(posId).size, -2e18);
    }

    function test_MockAdapter_ClosePosition() public {
        bytes32 posId = adapter.openPosition(-1e18, 2000e6, 50);
        int256 pnl = adapter.closePosition(posId, 50);
        assertEq(pnl, 0);
        // Position should be zeroed out
        assertEq(adapter.getPosition(posId).size, 0);
    }

    // -----------------------------------------------------------------------
    // HedgeVault deposit / withdraw
    // -----------------------------------------------------------------------

    function test_Vault_Deposit() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 5_000e6);
        uint256 shares = vault.deposit(5_000e6);
        vm.stopPrank();

        assertEq(shares, 5_000e6, "first depositor gets 1:1 shares");
        assertEq(vault.balanceOf(lp1), 5_000e6);
        assertEq(vault.totalCollateral(), 5_000e6);
    }

    function test_Vault_TwoDepositors() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 5_000e6);
        vault.deposit(5_000e6);
        vm.stopPrank();

        vm.startPrank(lp2);
        usdc.approve(address(vault), 5_000e6);
        uint256 shares2 = vault.deposit(5_000e6);
        vm.stopPrank();

        // Both depositors put in equal amounts → equal shares
        assertEq(shares2, vault.balanceOf(lp1));
        assertEq(vault.totalCollateral(), 10_000e6);
    }

    function test_Vault_Withdraw() public {
        vm.startPrank(lp1);
        usdc.approve(address(vault), 5_000e6);
        uint256 shares = vault.deposit(5_000e6);
        uint256 returned = vault.withdraw(shares);
        vm.stopPrank();

        assertEq(returned, 5_000e6, "should get back what was deposited");
        assertEq(usdc.balanceOf(lp1), 10_000e6, "LP1 balance fully restored");
    }

    function test_Vault_ZeroDepositReverts() public {
        vm.prank(lp1);
        vm.expectRevert("HedgeVault: zero amount");
        vault.deposit(0);
    }

    // -----------------------------------------------------------------------
    // HedgeVault operator / hedge instruction
    // -----------------------------------------------------------------------

    function test_Vault_ExecuteHedgeInstruction() public {
        bytes32 poolId = bytes32(uint256(42));

        HedgeInstruction memory instruction = HedgeInstruction({
            poolId:          poolId,
            targetNotional:  -5_000e6,   // short $5000
            maxSlippageBps:  50,
            deadline:        block.timestamp + 300,
            nonce:           0
        });

        bytes32 hash = keccak256(abi.encode(
            instruction.poolId,
            instruction.targetNotional,
            instruction.maxSlippageBps,
            instruction.deadline,
            instruction.nonce
        ));
        // Sign with operator key (EIP-191)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, _toEthSignedMessageHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vault.executeHedgeInstruction(instruction, sig);

        // lastHedgedNotional updated
        assertEq(vault.lastHedgedNotional(poolId), -5_000e6);
    }

    function test_Vault_ExpiredInstructionReverts() public {
        bytes32 poolId = bytes32(uint256(1));
        HedgeInstruction memory instruction = HedgeInstruction({
            poolId:         poolId,
            targetNotional: -1_000e6,
            maxSlippageBps: 50,
            deadline:       block.timestamp - 1,   // already expired
            nonce:          0
        });
        bytes memory sig = new bytes(65);
        vm.expectRevert("HedgeVault: instruction expired");
        vault.executeHedgeInstruction(instruction, sig);
    }

    function test_Vault_UnregisteredOperatorReverts() public {
        address rogue = address(0xDEAD);
        uint256 rogueKey = 0xDEAD1234;
        // rogueKey not in vault

        bytes32 poolId = bytes32(uint256(1));
        HedgeInstruction memory instruction = HedgeInstruction({
            poolId:         poolId,
            targetNotional: -1_000e6,
            maxSlippageBps: 50,
            deadline:       block.timestamp + 300,
            nonce:          0
        });

        bytes32 hash = keccak256(abi.encode(
            instruction.poolId,
            instruction.targetNotional,
            instruction.maxSlippageBps,
            instruction.deadline,
            instruction.nonce
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(rogueKey, _toEthSignedMessageHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert("HedgeVault: operator not registered");
        vault.executeHedgeInstruction(instruction, sig);
    }

    function test_Vault_DeltaDrift() public {
        bytes32 poolId = bytes32(uint256(99));

        // Simulate vault knowing about some exposure via internal storage
        // (In production this comes from the hook. Here we call the view to verify math)
        // netDeltaByPool is 0 and lastHedgedNotional is 0 → drift should be 0
        assertEq(vault.deltaDriftBps(poolId), 0);
    }

    function test_Vault_PauseBlocking() public {
        vault.setPaused(true);
        vm.startPrank(lp1);
        usdc.approve(address(vault), 1_000e6);
        vm.expectRevert("HedgeVault: paused");
        vault.deposit(1_000e6);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // Internal helper — replicate OZ v4 toEthSignedMessageHash
    // -----------------------------------------------------------------------
    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}
