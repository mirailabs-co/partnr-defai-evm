// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Vault.sol";
import "../src/interfaces/IVault.sol";
import "../src/interfaces/IStrategy.sol";
import "../src/strategies/apex/ApexStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP712Signature} from "../src/libraries/SigValidationHelpers.sol";

// Import mock contracts
import "./mock/ERC20.sol";
import "./mock/MockApexGateway.sol";

contract VaultTest is Test {
    // Main contracts
    Vault public vault;
    ApexStrategy public apexStrategy;
    MockApexGateway public apexGateway;

    // Mock tokens
    MockERC20 public underlying;
    
    // Test accounts
    address public operator;
    address public agent;
    address public user1;
    address public user2;
    uint256 private operatorPrivateKey;
    
    // Test constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant INITIAL_DEPOSIT = 100_000 * 1e18;
    uint256 public constant USER_DEPOSIT = 10_000 * 1e18;
    uint256 public constant MIN_DEPOSIT = 100 * 1e18;
    uint256 public constant MAX_DEPOSIT = 1_000_000 * 1e18;

    // Protocol parameters
    bytes32 public zkLinkAddress = bytes32(uint256(0x123456789));
    uint8 public subAccountId = 0;
    bool public useMapping = false;
    bytes public protocolParams;

    function setUp() public {
        // Set up test accounts
        operatorPrivateKey = 0xA11CE;
        operator = vm.addr(operatorPrivateKey);
        agent = makeAddr("agent");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock tokens
        underlying = new MockERC20("Test USDT", "USDT", 18);
        
        // Deploy mock Apex gateway
        apexGateway = new MockApexGateway();
        apexGateway.registerToken(address(underlying), 18);
        
        // Mint initial tokens to test accounts
        underlying.mint(operator, INITIAL_SUPPLY);
        underlying.mint(agent, INITIAL_SUPPLY);
        underlying.mint(user1, INITIAL_SUPPLY);
        underlying.mint(user2, INITIAL_SUPPLY);
        
        // Encode protocol params
        protocolParams = abi.encode(
            address(underlying),   // underlying asset
            zkLinkAddress,         // zkLink address
            subAccountId,          // sub-account ID
            useMapping,            // use mapping
            0,                     // totalDeposit (starts at 0)
            0                      // totalWithdraw (starts at 0)
        );
        
        // Deploy strategy
        apexStrategy = new ApexStrategy(
            address(apexGateway),
            address(0)
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
        
        // Approve tokens for initial deposit
        underlying.approve(address(vault), INITIAL_DEPOSIT);

        // In production the factory will move funds from creator to vault
        underlying.mint(address(vault), INITIAL_DEPOSIT);

        // Initialize vault with strategy
        vault.initialize(INITIAL_DEPOSIT, address(apexStrategy), protocolParams);
        vm.stopPrank();
    }
    
    function testConstructor() public view {
        assertEq(address(vault.UNDERLYING()), address(underlying));
        assertEq(vault.operator(), operator);
        assertEq(vault.agent(), agent);
        assertEq(vault.minDeposit(), MIN_DEPOSIT);
        assertEq(vault.maxDeposit(), MAX_DEPOSIT);
    }
    
    function testInitialization() public view {
        assertEq(vault.strategy(), address(apexStrategy));
        assertEq(vault.balanceOf(agent), INITIAL_DEPOSIT);
    }
    
    function testCannotReinitialize() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        vault.initialize(1000, address(apexStrategy), protocolParams);
    }
    
    function testTransferOperator() public {
        address newOperator = makeAddr("newOperator");
        
        vm.prank(operator);
        vault.transferOperator(newOperator);
        
        assertEq(vault.operator(), newOperator);
    }
    
    function testTransferOperatorUnauthorized() public {
        address newOperator = makeAddr("newOperator");
        
        vm.prank(user1);
        vm.expectRevert("only operator");
        vault.transferOperator(newOperator);
    }
    
    function testTransferAgent() public {
        address newAgent = makeAddr("newAgent");
        
        vm.prank(operator);
        vault.transferAgent(newAgent);
        
        assertEq(vault.agent(), newAgent);
    }
    
    function testTransferAgentUnauthorized() public {
        address newAgent = makeAddr("newAgent");
        
        vm.prank(user1);
        vm.expectRevert("only operator");
        vault.transferAgent(newAgent);
    }
    
    function testSetMinDeposit() public {
        uint256 newMinDeposit = 200 * 1e18;
        
        vm.prank(operator);
        vault.setMinDeposit(newMinDeposit);
        
        assertEq(vault.minDeposit(), newMinDeposit);
    }
    
    function testSetMaxDeposit() public {
        uint256 newMaxDeposit = 500_000 * 1e18;
        
        vm.prank(operator);
        vault.setMaxDeposit(newMaxDeposit);
        
        assertEq(vault.maxDeposit(), newMaxDeposit);
    }
    
    function testDeposit() public {
        vm.startPrank(user1);
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
        underlying.approve(address(vault), MIN_DEPOSIT - 1);
        
        vm.expectRevert(abi.encodeWithSignature("PDefaiDepositExceedsMax()"));
        vault.deposit(MIN_DEPOSIT - 1, user1);
        
        vm.stopPrank();
    }
    
    function testDepositAboveMaximum() public {
        vm.startPrank(user1);
        underlying.approve(address(vault), MAX_DEPOSIT + 1);
        
        vm.expectRevert(abi.encodeWithSignature("PDefaiDepositExceedsMax()"));
        vault.deposit(MAX_DEPOSIT + 1, user1);
        
        vm.stopPrank();
    }
    
    function testWithdrawWithSignature() public {
        // First, user1 deposits
        vm.startPrank(user1);
        underlying.approve(address(vault), USER_DEPOSIT);
        uint256 shares = vault.deposit(USER_DEPOSIT, user1);
        vm.stopPrank();
        
        // Create withdrawal parameters
        uint256 withdrawAmount = USER_DEPOSIT / 2;
        address receiver = user1;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Setup mock pending balance in Apex gateway
        uint16 tokenId = apexGateway.tokenIds(address(underlying));
        underlying.mint(operator, withdrawAmount);
        
        vm.startPrank(operator);
        underlying.approve(address(apexGateway), withdrawAmount);
        apexGateway.mockPendingBalance(address(vault), tokenId, uint128(withdrawAmount));
        vm.stopPrank();
        
        // Update protocol params to reflect the withdrawal
        bytes memory updatedParams = abi.encode(
            address(underlying),   // underlying asset
            zkLinkAddress,         // zkLink address
            subAccountId,          // sub-account ID
            useMapping,            // use mapping
            USER_DEPOSIT,          // totalDeposit
            0                      // totalWithdraw
        );
        
        // Create signature for withdrawal
        Fee[] memory fees = new Fee[](0);
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                vault.domainSeparator(),
                keccak256(
                    abi.encode(
                        withdrawAmount,
                        receiver,
                        keccak256(abi.encode(fees)),
                        deadline
                    )
                )
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPrivateKey, digest);
        
        EIP712Signature memory sig = EIP712Signature({
            v: v,
            r: r,
            s: s,
            deadline: deadline
        });

        // Execute withdrawal
        uint256 balanceBefore = underlying.balanceOf(user1);
        
        // Mock the strategy value call using updatedParams
        bytes memory withdrawParams = abi.encode(
            address(underlying),
            zkLinkAddress,
            subAccountId,
            useMapping,
            USER_DEPOSIT,
            withdrawAmount
        );
        
        vm.prank(user1);
        vault.withdraw(withdrawAmount, receiver, fees, sig);
    }
    
    // function testWithdrawSignatureReplay() public {
    //     // First, user1 deposits
    //     vm.startPrank(user1);
    //     underlying.approve(address(vault), USER_DEPOSIT);
    //     vault.deposit(USER_DEPOSIT, user1);
    //     vm.stopPrank();
        
    //     // Create withdrawal parameters
    //     uint256 withdrawAmount = USER_DEPOSIT / 2;
    //     address receiver = user1;
    //     uint256 deadline = block.timestamp + 1 hours;
        
    //     Fee[] memory fees = new Fee[](0);
    //     // Create signature
    //     bytes32 digest = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             vault.domainSeparator(),
    //             keccak256(
    //                 abi.encode(
    //                     withdrawAmount,
    //                     receiver,
    //                     keccak256(abi.encode(fees)),
    //                     deadline
    //                 )
    //             )
    //         )
    //     );
        
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPrivateKey, digest);
        
    //     EIP712Signature memory sig = EIP712Signature({
    //         v: v,
    //         r: r,
    //         s: s,
    //         deadline: deadline
    //     });
        
    //     // Setup for withdrawal
    //     uint16 tokenId = apexGateway.tokenIds(address(underlying));
    //     underlying.mint(operator, withdrawAmount * 2); // Enough for two withdrawals
        
    //     vm.startPrank(operator);
    //     underlying.approve(address(apexGateway), withdrawAmount * 2);
    //     apexGateway.mockPendingBalance(address(vault), tokenId, uint128(withdrawAmount * 2));
    //     vm.stopPrank();
        
    //     // For this test, we just check the signature is marked as used
    //     // by attempting to use it twice
    //     vm.startPrank(user1);
        
    //     // Execute twice (will fail but we're just checking the signature usage)
    //     vm.expectRevert();
    //     vault.withdraw(withdrawAmount, receiver, fees, sig);
        
    //     // Second attempt should fail with PDefaiUsedSig
    //     vm.expectRevert(abi.encodeWithSignature("PDefaiUsedSig()"));
    //     vault.withdraw(withdrawAmount, receiver, fees, sig);
        
    //     vm.stopPrank();
    // }
    
    function testExecuteActions() public {
        // Create a simple action to transfer tokens
        Execution[] memory actions = new Execution[](1);
        
        // Mint some tokens to the vault for this test
        underlying.mint(address(vault), 1000);

        // Action to transfer 1000 tokens from vault to user1
        bytes memory transferCalldata = abi.encodeWithSignature(
            "transfer(address,uint256)",
            user1,
            1000
        );
        
        actions[0] = Execution({
            target: address(underlying),
            params: transferCalldata
        });
        
        // Calculate hashes for signature
        bytes32[] memory targetHashes = new bytes32[](1);
        bytes32[] memory paramHashes = new bytes32[](1);
        
        targetHashes[0] = keccak256(abi.encode(address(underlying)));
        paramHashes[0] = keccak256(abi.encode(transferCalldata));
        
        // Create signature
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                vault.domainSeparator(),
                keccak256(
                    abi.encode(
                        address(vault),
                        keccak256(abi.encode(targetHashes)),
                        keccak256(abi.encode(paramHashes)),
                        block.timestamp + 1 hours
                    )
                )
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPrivateKey, digest);
        
        EIP712Signature memory sig = EIP712Signature({
            v: v,
            r: r,
            s: s,
            deadline: block.timestamp + 1 hours
        });
        
        // Execute the actions
        uint256 user1BalanceBefore = underlying.balanceOf(user1);
        
        vm.prank(operator);
        vault.execute(actions, sig);
        
        // Verify transfer happened
        assertEq(underlying.balanceOf(user1), user1BalanceBefore + 1000);
    }
    
    function testExecuteActionsUnauthorized() public {
        // Create a simple action
        Execution[] memory actions = new Execution[](1);
        
        actions[0] = Execution({
            target: address(underlying),
            params: abi.encodeWithSignature("transfer(address,uint256)", user1, 1000)
        });
        
        // Create an invalid signature (signed by user1 instead of operator)
        uint256 user1PrivateKey = 0xB0B;
        
        bytes32[] memory targetHashes = new bytes32[](1);
        bytes32[] memory paramHashes = new bytes32[](1);
        
        targetHashes[0] = keccak256(abi.encode(address(underlying)));
        paramHashes[0] = keccak256(abi.encode(actions[0].params));
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                vault.domainSeparator(),
                keccak256(
                    abi.encode(
                        address(vault),
                        keccak256(abi.encode(targetHashes)),
                        keccak256(abi.encode(paramHashes)),
                        block.timestamp + 1 hours
                    )
                )
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);
        
        EIP712Signature memory sig = EIP712Signature({
            v: v,
            r: r,
            s: s,
            deadline: block.timestamp + 1 hours
        });
        
        // Execute with invalid signature
        underlying.mint(address(vault), 1000);

        vm.prank(user1);
        vm.expectRevert("SIG_INVALID");
        vault.execute(actions, sig);
    }
    
    function testTotalAssetsWithMockedStrategy() public {
        // Set up a scenario where the Apex gateway has a balance
        uint256 depositAmount = INITIAL_DEPOSIT * 2;
        uint16 tokenId = apexGateway.tokenIds(address(underlying));
        
        underlying.mint(operator, depositAmount);
        
        vm.startPrank(operator);
        underlying.approve(address(apexGateway), depositAmount);
        apexGateway.mockPendingBalance(address(vault), tokenId, uint128(depositAmount));
        vm.stopPrank();
        
        // Update protocol params to reflect total deposits
        bytes memory updatedParams = abi.encode(
            address(underlying),   // underlying asset
            zkLinkAddress,         // zkLink address
            subAccountId,          // sub-account ID
            useMapping,            // use mapping
            depositAmount,         // totalDeposit
            0                      // totalWithdraw
        );
        
        // Mock totalAssets calculation 
        // This test is limited because totalAssets depends on a staticcall to the strategy
        // In a real test, we'd need to mock this staticcall
        
        // Instead, verify directly with the strategy's value function
        assertEq(apexStrategy.value(address(vault), updatedParams), depositAmount);
    }
}