// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Vault.sol";
import "../src/strategies/apex/ApexStrategy.sol";
import "../src/oracle/OffchainValueHub.sol";
import "../src/interfaces/IVault.sol";
import "../src/interfaces/IStrategy.sol";
import "../src/interfaces/IOffchainValueHub.sol";
import {EIP712Signature} from "../src/libraries/SigValidationHelpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// Mock contracts
import "./mock/ERC20.sol";
import "./mock/MockApexGateway.sol";
import "../src/VaultFactory.sol";
import "../src/VaultDeployer.sol";

contract ApexStrategyWithOffchainValueTests is Test {
    // Main contracts
    Vault public vault;
    ApexStrategy public apexStrategy;
    OffchainValueHub public valueHub;
    VaultFactory public vaultFactory;
    
    // Mock contracts
    MockERC20 public underlying;
    MockApexGateway public apexGateway;
    
    // Test accounts
    address public admin = vm.addr(0x1);
    address public operator = vm.addr(0x2);
    address public valueProvider = vm.addr(0x3);
    address public agent = vm.addr(0x5);
    address public user1 = vm.addr(0x6);
    address public user2 = vm.addr(0x7);
    
    // Private keys for signing
    uint256 constant operatorPrivateKey = 0x2;
    uint256 constant valueProviderPrivateKey = 0x3;
    
    // Test constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant INITIAL_DEPOSIT = 100_000 * 1e18;
    uint256 public constant USER_DEPOSIT = 10_000 * 1e18;
    uint256 public constant MIN_DEPOSIT = 100 * 1e18;
    uint256 public constant MAX_DEPOSIT = 1_000_000 * 1e18;
    uint256 public constant MIN_VALUE_CHANGE_PCT = 100; // 1%
    uint256 public constant STALENESS_THRESHOLD = 86400; // 1 day in seconds
    
    // Apex protocol parameters
    bytes32 public zkLinkAddress = bytes32(uint256(0x123456789));
    uint8 public subAccountId = 0;
    bool public useMapping = false;
    bytes public protocolParams;
    
    function setUp() public {
        // Set up test accounts
        vm.startPrank(admin);
        
        // Deploy mock VaultFactory
        vaultFactory = new VaultFactory();
        vaultFactory.initialize(admin, operator);

        // Deploy mock tokens
        underlying = new MockERC20("Test USDT", "USDT", 18);
        
        address[] memory assets = new address[](1);
        assets[0] = address(underlying);
        uint256[] memory minimumDeposits = new uint256[](1);
        minimumDeposits[0] = 1;

        vaultFactory.setSupportedAssets(assets, minimumDeposits);

        VaultDeployer newDeployer = new VaultDeployer(address(vaultFactory));
        
        // Update the vault deployer
        vaultFactory.setVaultDeployer(address(newDeployer));

        // Deploy mock Apex gateway
        apexGateway = new MockApexGateway();
        
        // Register the token with the gateway
        apexGateway.registerToken(address(underlying), 18);
        
        // Deploy OffchainValueHub (proxy)
        valueHub = new OffchainValueHub();
        valueHub.initialize(
            admin,
            valueProvider,
            MIN_VALUE_CHANGE_PCT,
            0, // Use 0 for values that never expire
            address(vaultFactory)
        );
        
        // Deploy strategy with reference to OffchainValueHub
        apexStrategy = new ApexStrategy(
            address(apexGateway),
            address(valueHub)
        );

        vaultFactory.setWhitelistedStrategy(address(apexStrategy), true);
        
        // Mint initial tokens to test accounts
        underlying.mint(operator, INITIAL_SUPPLY);
        underlying.mint(agent, INITIAL_SUPPLY);
        underlying.mint(user1, INITIAL_SUPPLY);
        underlying.mint(user2, INITIAL_SUPPLY);
        underlying.mint(address(this), INITIAL_SUPPLY);
        
        // Encode protocol params
        protocolParams = abi.encode(
            address(underlying),   // underlying asset
            zkLinkAddress,         // zkLink address
            subAccountId,          // sub-account ID
            useMapping
        );
        
        vm.stopPrank();
        
        // Deploy vault
        vm.startPrank(agent);
        underlying.approve(address(vaultFactory), INITIAL_SUPPLY);
        VaultParameters memory params = VaultParameters({
            underlying: address(underlying),
            name: "AAAAA",
            symbol: "BBBBBB",
            agent: agent,
            initialAgentDeposit: INITIAL_SUPPLY,
            minDeposit: MIN_DEPOSIT,
            maxDeposit: MAX_DEPOSIT,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: protocolParams
        });

        // Create signature for vault creation
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                vaultFactory.domainSeparator(),
                keccak256(
                    abi.encode(
                        protocolParams,
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
        
        params.veriSig = sig;
        
        vault = Vault(vaultFactory.createVault(params, operator, address(apexStrategy)));
        
        vm.stopPrank();
    }
    
    function testCorrectDeployment() public {
        assertEq(address(vault.UNDERLYING()), address(underlying));
        assertEq(vault.agent(), agent);
        assertEq(vault.operator(), operator);
        assertEq(vault.minDeposit(), MIN_DEPOSIT);
        assertEq(vault.maxDeposit(), MAX_DEPOSIT);
        assertEq(vault.strategy(), address(apexStrategy));
    }
    
    function testValueHubDeployment() public view {
        assertEq(valueHub.stalenessThreshold(), 0); // Values never expire
        assertEq(valueHub.minValueChangePercentage(), MIN_VALUE_CHANGE_PCT);
        assert(valueHub.hasRole(valueHub.VALUE_PROVIDER_ROLE(), valueProvider));
        assert(valueHub.hasRole(valueHub.DEFAULT_ADMIN_ROLE(), admin));
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
    
    function testOffchainValueSetting() public {
        // Prepare value data
        uint256 vaultValue = 200_000 * 1e18; // 200,000 tokens, more than deposits to simulate profit
        
        // Set the value using the valueProvider
        vm.startPrank(valueProvider);
        valueHub.setVaultValue(address(vault), vaultValue);
        vm.stopPrank();
        
        // Check that the strategy returns the value from the hub
        uint256 reportedValue = apexStrategy.value(address(vault), "");
        assertEq(reportedValue, vaultValue);
    }
    
    function testOffchainValueUpdating() public {
        // Set an initial value
        vm.startPrank(valueProvider);
        valueHub.setVaultValue(address(vault), 150_000 * 1e18);
        
        // Try to update with a value change exceeding the maximum
        uint256 excessiveValue = 151_000 * 1e18;
        vm.expectRevert("Value change lesser permitted minimum votatility");
        valueHub.setVaultValue(address(vault), excessiveValue);
        
        // Update with a valid value change
        uint256 acceptableValue = 200_000 * 1e18; // ~33% increase, within 50% limit
        valueHub.setVaultValue(address(vault), acceptableValue);
        vm.stopPrank();
        
        // Verify the value was updated
        uint256 reportedValue = apexStrategy.value(address(vault), "");
        assertEq(reportedValue, acceptableValue);
    }
    
    function testValueFallbackMechanism() public {
        // Create a scenario where the value hub call fails
        // 1. First set up a valid fallback calculation
        uint256 depositAmount = INITIAL_DEPOSIT / 2;
        uint16 tokenId = apexGateway.tokenIds(address(underlying));
        
        // Need to approve tokens for the mock
        underlying.approve(address(apexGateway), depositAmount);
        
        // Simulate deposit by setting a pending balance
        apexGateway.mockPendingBalance(address(vault), tokenId, uint128(depositAmount));
    }
    
   
    function testInitializationActions() public view {
        Execution[] memory actions = apexStrategy.getInitializationActions(USER_DEPOSIT, protocolParams);
        
        // Should return actions for approval and deposit
        assertEq(actions.length, 3);
        
        // First action should be approval of token
        assertEq(actions[0].target, address(underlying));
        
        // Second action should be deposit to Apex
        assertEq(actions[1].target, address(apexGateway));
    }
    
    function testGetDepositActions() public view {
        Execution[] memory actions = apexStrategy.getDepositActions(USER_DEPOSIT, protocolParams);
        
        // Should return one action for depositing to Apex
        assertEq(actions.length, 1);
        
        // Action should target the Apex gateway
        assertEq(actions[0].target, address(apexGateway));
    }
    
    function testComposeProtocolParameters() public view {
        bytes memory composedParams = apexStrategy.composeProtocolParameters(
            address(vault),
            protocolParams
        );
        
        (
            address underlyingAsset,
            bytes32 receivedZkLinkAddress,
            uint8 receivedSubAccountId,
            bool receivedUseMapping,
            uint256 totalDeposit,
            uint256 totalWithdraw
        ) = abi.decode(
            composedParams,
            (address, bytes32, uint8, bool, uint256, uint256)
        );
        
        assertEq(underlyingAsset, address(underlying));
        assertEq(receivedZkLinkAddress, zkLinkAddress);
        assertEq(receivedSubAccountId, subAccountId);
        assertEq(receivedUseMapping, useMapping);
        
    }
}
