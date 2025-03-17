// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Vault.sol";
import "../src/strategies/apex/ApexStrategy.sol";
import "../src/interfaces/IVault.sol";
import "../src/interfaces/IStrategy.sol";
import "../src/interfaces/IStrategy.sol";
import {EIP712Signature} from "../src/libraries/SigValidationHelpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock contracts
import "./mock/ERC20.sol";
import "./mock/MockApexGateway.sol";

contract ApexStrategyTests is Test {
    // Main contracts
    Vault public vault;
    ApexStrategy public apexStrategy;
    
    // Mock contracts
    MockERC20 public underlying;
    MockApexGateway public apexGateway;
    
    // Test accounts
    address public operator = address(1);
    address public agent = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    
    // Test constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant INITIAL_DEPOSIT = 100_000 * 1e18;
    uint256 public constant USER_DEPOSIT = 10_000 * 1e18;
    uint256 public constant MIN_DEPOSIT = 100 * 1e18;
    uint256 public constant MAX_DEPOSIT = 1_000_000 * 1e18;
    
    // Apex protocol parameters
    bytes32 public zkLinkAddress = bytes32(uint256(0x123456789));
    uint8 public subAccountId = 0;
    bool public useMapping = false;
    bytes public protocolParams;
    
    function setUp() public {
        // Deploy mock tokens
        underlying = new MockERC20("Test USDT", "USDT", 18);
        
        // Deploy mock Apex gateway
        apexGateway = new MockApexGateway();
        
        // Register the token with the gateway
        apexGateway.registerToken(address(underlying), 18);
        
        // Mint initial tokens to test accounts
        underlying.mint(operator, INITIAL_SUPPLY);
        underlying.mint(agent, INITIAL_SUPPLY);
        underlying.mint(user1, INITIAL_SUPPLY);
        underlying.mint(user2, INITIAL_SUPPLY);
        underlying.mint(address(this), INITIAL_SUPPLY);
        
        // Deploy strategy
        apexStrategy = new ApexStrategy(
            address(apexGateway),
            address(0)
        );
        
        // Encode protocol params
        protocolParams = abi.encode(
            address(underlying),   // underlying asset
            zkLinkAddress,         // zkLink address
            subAccountId,          // sub-account ID
            useMapping
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
        
        // Mint tokens to vault for initialization
        underlying.mint(address(vault), INITIAL_SUPPLY);

        // Approve tokens for initial deposit
        underlying.approve(address(vault), INITIAL_DEPOSIT);

        // Initialize vault with strategy
        vault.initialize(INITIAL_DEPOSIT, address(apexStrategy), protocolParams);
        vm.stopPrank();
    }
    
    function testCorrectDeployment() public view {
        assertEq(address(vault.UNDERLYING()), address(underlying));
        assertEq(vault.agent(), agent);
        assertEq(vault.operator(), operator);
        assertEq(vault.minDeposit(), MIN_DEPOSIT);
        assertEq(vault.maxDeposit(), MAX_DEPOSIT);
        assertEq(vault.strategy(), address(apexStrategy));
    }
    
    function testInitialDeposit() public {
        // Check initial shares were minted to the agent
        assertEq(vault.balanceOf(agent), INITIAL_DEPOSIT);
        
        // Since we're using a mock, we just check that the underlying approval is set
        assertEq(underlying.allowance(address(vault), address(apexGateway)), type(uint256).max);
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
        // First, we need to simulate a deposit to the protocol
        // This would typically involve tokens moving to the Apex gateway
        
        // Create a scenario where tokens are in the pendingBalances of the gateway
        uint256 depositAmount = INITIAL_DEPOSIT / 2;
        uint16 tokenId = apexGateway.tokenIds(address(underlying));
        
        // Need to approve tokens for the mock
        underlying.approve(address(apexGateway), depositAmount);
        
        // Simulate deposit by setting a pending balance
        apexGateway.mockPendingBalance(address(vault), tokenId, uint128(depositAmount));
        
        // Update the protocol params to reflect the deposit
        bytes memory updatedParams = abi.encode(
            address(underlying),   // underlying asset
            zkLinkAddress,         // zkLink address
            subAccountId,          // sub-account ID
            useMapping,            // use mapping
            depositAmount,         // totalDeposit
            0                      // totalWithdraw
        );
        
        // The value should include the deposited amount, reflected in the protocol params
        assertEq(apexStrategy.value(address(vault), updatedParams), underlying.balanceOf(address(vault)) +  depositAmount);
    }
    
    function testInitializationActions() public {
        Execution[] memory actions = apexStrategy.getInitializationActions(USER_DEPOSIT, protocolParams);
        
        // Should return actions for approval and deposit
        assertEq(actions.length, 3);
        
        // First action should be approval of token
        assertEq(actions[0].target, address(underlying));
        
        // Second action should be deposit to Apex
        assertEq(actions[1].target, address(apexGateway));
        
        // Verify function selector for deposit ERC20
        // bytes4 selector = bytes4(actions[1].params[0:4]);
        // assertEq(selector, bytes4(keccak256("depositERC20(address,uint104,bytes32,uint8,bool)")));
    }
    
}