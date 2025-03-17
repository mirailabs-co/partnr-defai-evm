// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Vault.sol";
import "../src/strategies/venus/VenusStrategy.sol";
import "../src/interfaces/IVault.sol";
import "../src/interfaces/IStrategy.sol";
import "../src/strategies/venus/IVToken.sol";
import "../src/strategies/venus/IComptroller.sol";
import {EIP712Signature} from "../src/libraries/SigValidationHelpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock contracts
import "./mock/ERC20.sol";
import "./mock/MockVToken.sol";

contract VaultStrategyTests is Test {
    // Main contracts
    Vault public vault;
    VenusStrategy public venusStrategy;
    
    // Mock contracts
    MockERC20 public underlying;
    MockVToken public vToken;
    
    // Test accounts
    address public operator = address(1);
    address public agent = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    
    // Test constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant INITIAL_DEPOSIT = 100_000 * 1e18;
    uint256 public constant USER_DEPOSIT = 10_000 * 1e18;
    uint256 public constant MIN_DEPOSIT = 1 * 1e18;
    uint256 public constant MAX_DEPOSIT = 1_000_000 * 1e18;
    uint256 public constant EXCHANGE_RATE = 2 * 1e18; // 1 vToken = 2 underlying
    
    function setUp() public {
        // Deploy mock tokens
        underlying = new MockERC20("Test USDT", "USDT", 18);
        vToken = new MockVToken("Venus USDT", "vUSDT", address(underlying), EXCHANGE_RATE);
        
        // Mint initial tokens to test accounts
        underlying.mint(operator, INITIAL_SUPPLY);
        underlying.mint(agent, INITIAL_SUPPLY);
        underlying.mint(user1, INITIAL_SUPPLY);
        underlying.mint(user2, INITIAL_SUPPLY);
        
        // Deploy strategy
        venusStrategy = new VenusStrategy(
            address(vToken)
        );
        
        // Deploy vault
        vm.startPrank(operator);
        vault = new Vault(
            operator,
            address(underlying),
            "Test Vault",
            "vTST",
            agent,
            MIN_DEPOSIT,
            MAX_DEPOSIT
        );
        
        // in production we use a  VaultFactory to move fund
        underlying.mint(address(vault), INITIAL_SUPPLY);

        // Approve tokens for initial deposit
        underlying.approve(address(vault), INITIAL_DEPOSIT);

        vault.initialize(INITIAL_DEPOSIT, address(venusStrategy), bytes(""));
        vm.stopPrank();
    }
    
    function testCorrectDeployment() public {
        assertEq(address(vault.UNDERLYING()), address(underlying));
        assertEq(vault.agent(), agent);
        assertEq(vault.operator(), operator);
        assertEq(vault.minDeposit(), MIN_DEPOSIT);
        assertEq(vault.maxDeposit(), MAX_DEPOSIT);
        assertEq(vault.strategy(), address(venusStrategy));
    }
    
    function testInitialDeposit() public view {
        // Check initial shares were minted to the agent
        assertEq(vault.balanceOf(agent), INITIAL_DEPOSIT);
        
        // Check underlying tokens were transferred to the vault
        assertEq(underlying.balanceOf(address(vToken)), INITIAL_DEPOSIT);
    }
    
    function testInitializationActions() public view {
        // Check that Venus approval was set
        assertEq(underlying.allowance(address(vault), address(vToken)), type(uint256).max);
    }
    
    function testUserDeposit() public {
        vm.startPrank(user1);
        
        // Approve and deposit
        underlying.approve(address(vault), USER_DEPOSIT);
        
        uint256 sharesBefore = vault.totalSupply();
        uint256 userSharesBefore = vault.balanceOf(user1);

        uint256 receivedShares = vault.deposit(USER_DEPOSIT, user1);
        
        // Check shares were minted correctly
        assertEq(vault.balanceOf(user1), userSharesBefore + receivedShares);
        assertEq(vault.totalSupply(), sharesBefore + receivedShares);
        
        // Check underlying tokens were transferred
        assertEq(underlying.balanceOf(address(vToken)), INITIAL_DEPOSIT + USER_DEPOSIT);
        
        vm.stopPrank();
    }
    
    function testDepositBelowMinimum() public {
        vm.startPrank(user1);
        
        // Approve and try to deposit below minimum
        underlying.approve(address(vault), MIN_DEPOSIT - 1);
        
        // Should revert with PDefaiDepositExceedsMax
        vm.expectRevert(abi.encodeWithSignature("PDefaiDepositExceedsMax()"));
        vault.deposit(MIN_DEPOSIT - 1, user1);
        
        vm.stopPrank();
    }
    
    function testDepositAboveMaximum() public {
        vm.startPrank(user1);
        
        // Approve and try to deposit above maximum
        underlying.approve(address(vault), MAX_DEPOSIT + 1);
        
        // Should revert with PDefaiDepositExceedsMax
        vm.expectRevert(abi.encodeWithSignature("PDefaiDepositExceedsMax()"));
        vault.deposit(MAX_DEPOSIT + 1, user1);
        
        vm.stopPrank();
    }
    
    function testVaultValue() public {
        // First, simulate some Venus actions
        vm.startPrank(address(vault));
        
        // Mint some vTokens with 50% of initial deposit
        underlying.approve(address(vToken), INITIAL_DEPOSIT / 2);
        vToken.mint(INITIAL_DEPOSIT / 2);
        
        vm.stopPrank();
        
        // Now check the vault's value
        uint256 vTokenBalance = vToken.balanceOf(address(vault));
        uint256 expectedVTokenValue = (vTokenBalance * EXCHANGE_RATE) / 1e18;
        
        // The value should be the vToken value
        assertEq(venusStrategy.value(address(vault), bytes("")), expectedVTokenValue);
        
        // total assets should be the value
        assertEq(vault.totalAssets(), expectedVTokenValue);
    }
    
    //================ TESTS FOR WITHDRAWAL FLOWS ================//
    
    function testWithdrawalWithSignature() public {
        // Setup: deposit from user1
        vm.startPrank(user1);
        underlying.approve(address(vault), USER_DEPOSIT);
        uint256 shares = vault.deposit(USER_DEPOSIT, user1);
        vm.stopPrank();
        
        // Setup: create a signature from operator
        uint256 withdrawAmount = USER_DEPOSIT / 2;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Calculate shares to burn based on value
        uint256 sharesToBurn = (shares * withdrawAmount) / USER_DEPOSIT;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                vault.domainSeparator(),
                keccak256(
                    abi.encode(
                        withdrawAmount,
                        user1, // receiver
                        sharesToBurn,
                        user1, // owner
                        deadline
                    )
                )
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(1), digest);
        
        EIP712Signature memory sig = EIP712Signature({
            v: v,
            r: r,
            s: s,
            deadline: deadline
        });
        
        // TODO: Mock the withdrawal with signature
        // This would require more complex test setup for signature verification
    }
    
    function testExecuteActions() public {
        // Create some test actions
        Execution[] memory actions = new Execution[](1);
        
        // Action to approve the vToken to spend underlying
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(vToken),
            USER_DEPOSIT
        );
        
        actions[0] = Execution({
            target: address(underlying),
            params: approveCalldata
        });
        
        // TODO: Mock the execution with signature
        // This would require more complex test setup for signature verification
    }
    
    function testStrategyGetInitializationActions() public view {
        Execution[] memory actions = venusStrategy.getInitializationActions(USER_DEPOSIT, bytes(""));
        
        // Should return 2 actions (approve, mint)
        assertEq(actions.length, 3);
        
        // Check targets and selectors using assembly
        assertEq(actions[0].target, address(underlying), "First action should target the underlying token");
        assertEq(actions[1].target, address(vToken), "Second action should target the vToken");
        
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            vToken,
            type(uint256).max
        );
        
        uint256 amountToDeposit = USER_DEPOSIT;
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint(uint256)",
            amountToDeposit
        );

        assertEq(actions[0].params, approveCalldata, "First action should target the underlying token");
        assertEq(actions[1].params, mintCalldata, "Second action should mint the vToken");

    }
    
    function testStrategyGetDepositActions() public {
        // Execution[] memory actions = venusStrategy.getDepositActions(USER_DEPOSIT);
        
        // // Should return 1 action (mint vTokens)
        // assertEq(actions.length, 1);
        
        // // Check action is mint
        // bytes4 selector = bytes4(actions[0].params[0:4]);
        // assertEq(selector, bytes4(keccak256("mint(uint256)")));
    }
}