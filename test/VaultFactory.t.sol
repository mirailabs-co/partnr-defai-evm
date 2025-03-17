// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/VaultFactory.sol";
import "../src/Vault.sol";
import "../src/VaultDeployer.sol";
import "./mock/ERC20.sol";
import "./mock/ActionMock.sol";
import "../src/strategies/apex/ApexStrategy.sol";
import {EIP712Signature} from "../src/libraries/SigValidationHelpers.sol";
import "./mock/MockApexGateway.sol";

contract VaultFactoryTest is Test {
    // Contracts
    VaultFactory public factory;
    VaultDeployer public deployer;
    MockERC20 public usdt;
    MockERC20 public unsupportedToken;
    ApexStrategy public apexStrategy;
    MockApexGateway public apexGateway;

    // Addresses
    address public owner;
    address public operator;
    address public agent;
    address public user1;
    
    // Constants
    uint256 public constant MINIMUM_DEPOSIT = 1000 * 1e18;
    uint256 public constant INITIAL_BALANCE = 10000 * 1e18;

    // Private keys for signature testing
    uint256 constant operatorPrivateKey = 0x4;
    uint256 constant agentPrivateKey = 0x5;
    uint256 constant userPrivateKey = 0x6;

    // Protocol parameters
    bytes32 public zkLinkAddress = bytes32(uint256(0x123456789));
    uint8 public subAccountId = 0;
    bool public useMapping = false;
    bytes public protocolParams;
    
    function setUp() public {
        // Set up test accounts
        owner = address(this);
        operator = vm.addr(operatorPrivateKey);
        agent = vm.addr(agentPrivateKey);
        user1 = vm.addr(userPrivateKey);

        // Deploy tokens
        usdt = new MockERC20("Test USDT", "USDT", 18);
        unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);
        
        // Deploy mock Apex gateway
        apexGateway = new MockApexGateway();
        apexGateway.registerToken(address(usdt), 18);
        
        // Deploy strategy
        apexStrategy = new ApexStrategy(
            address(apexGateway),
            address(0)
        );

        // Encode protocol params
        protocolParams = abi.encode(
            address(usdt),     // underlying asset
            zkLinkAddress,     // zkLink address
            subAccountId,      // sub-account ID
            useMapping,        // use mapping
            0,                 // totalDeposit (starts at 0)
            0                  // totalWithdraw (starts at 0)
        );

        // Deploy factory
        factory = new VaultFactory();
        factory.initialize(owner, operator);

        // Set strategy whitelist
        factory.setWhitelistedStrategy(address(apexStrategy), true);

        // Deploy vault deployer
        deployer = new VaultDeployer(address(factory));
        factory.setVaultDeployer(address(deployer));
        
        // Fund accounts
        usdt.mint(agent, INITIAL_BALANCE);
        usdt.mint(user1, INITIAL_BALANCE);
        usdt.mint(address(this), INITIAL_BALANCE);
        
        // Setup approvals
        vm.startPrank(agent);
        usdt.approve(address(factory), UINT256_MAX);
        vm.stopPrank();
    }

    function test_UpdateableFactory() public {
        // Deploy a proxy implementation of the factory
        address _factory = Upgrades.deployUUPSProxy(
            "VaultFactory.sol:VaultFactory",
            abi.encodeCall(
                VaultFactory.initialize,
                (
                    owner,
                    operator
                )
            )
        );

        // Deploy a new implementation
        VaultFactory newFactory = new VaultFactory();
        
        // Upgrade the proxy to the new implementation
        bytes memory data;
        VaultFactory(payable(_factory)).upgradeToAndCall(address(newFactory), data);
        
        // Verify the upgrade was successful
        // This is a basic test - in production, you would verify state persistence
        // and functionality after the upgrade
    }

    function test_UpdateSupportedAssets() public {
        address[] memory assets = new address[](2);
        assets[0] = address(usdt);
        assets[1] = address(0); // For native token
        
        uint256[] memory minimumDeposits = new uint256[](2);
        minimumDeposits[0] = MINIMUM_DEPOSIT;
        minimumDeposits[1] = MINIMUM_DEPOSIT;

        // Update supported assets
        factory.setSupportedAssets(assets, minimumDeposits);

        // Verify updates
        assertEq(factory.supportedAssets(address(usdt)), MINIMUM_DEPOSIT);
        assertEq(factory.supportedAssets(address(0)), MINIMUM_DEPOSIT);
    }

    function test_CreateVaultWithUnsupportedAsset() public {
        // Create params with unsupported token
        VaultParameters memory params = VaultParameters({
            underlying: address(unsupportedToken),
            name: "Unsupported Token Vault",
            symbol: "UTV",
            agent: agent,
            initialAgentDeposit: MINIMUM_DEPOSIT,
            minDeposit: MINIMUM_DEPOSIT,
            maxDeposit: MINIMUM_DEPOSIT * 2,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: bytes("")
        });

        // Create signature for vault creation
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                factory.domainSeparator(),
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
        params.protocolParams = protocolParams;

        // Expect revert due to unsupported asset
        vm.startPrank(agent);
        vm.expectRevert(abi.encodeWithSignature("PDefaiUnspportedAsset(address)", address(unsupportedToken)));
        factory.createVault(params, operator, address(apexStrategy));
        vm.stopPrank();
    }

    function test_CreateVaultWithInsufficientDeposit() public {
        // First set supported asset
        address[] memory assets = new address[](1);
        assets[0] = address(usdt);
        uint256[] memory minimumDeposits = new uint256[](1);
        minimumDeposits[0] = MINIMUM_DEPOSIT;
        factory.setSupportedAssets(assets, minimumDeposits);

        // Try to create vault with deposit less than minimum
        VaultParameters memory params = VaultParameters({
            underlying: address(usdt),
            name: "Test Vault",
            symbol: "TV",
            agent: agent,
            initialAgentDeposit: MINIMUM_DEPOSIT - 1,
            minDeposit: MINIMUM_DEPOSIT,
            maxDeposit: MINIMUM_DEPOSIT * 2,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: bytes("")
        });

        // Create signature for vault creation
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                factory.domainSeparator(),
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
        params.protocolParams = protocolParams;

        // Expect revert due to insufficient deposit
        vm.startPrank(agent);
        vm.expectRevert(abi.encodeWithSignature("PDefaiValueMismatch()"));
        factory.createVault(params, operator, address(apexStrategy));
        vm.stopPrank();
    }

    function test_CreateVaultWithDuplicateName() public {
        // First set supported asset
        address[] memory assets = new address[](1);
        assets[0] = address(usdt);
        uint256[] memory minimumDeposits = new uint256[](1);
        minimumDeposits[0] = MINIMUM_DEPOSIT;
        factory.setSupportedAssets(assets, minimumDeposits);

        // Setup parameters for the vault
        VaultParameters memory params = VaultParameters({
            underlying: address(usdt),
            name: "Duplicate Vault",
            symbol: "DV",
            agent: agent,
            initialAgentDeposit: MINIMUM_DEPOSIT,
            minDeposit: MINIMUM_DEPOSIT,
            maxDeposit: MINIMUM_DEPOSIT * 2,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: bytes("")
        });

        // Create signature for vault creation
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                factory.domainSeparator(),
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
        params.protocolParams = protocolParams;

        // Grant operator role for vault creation
        factory.grantRole(factory.OPERATOR_ROLE(), operator);

        // Create first vault
        vm.startPrank(agent);
        factory.createVault(params, operator, address(apexStrategy));

        // Try to create second vault with same name
        vm.expectRevert(abi.encodeWithSignature("PDefaiDeployedVault()"));
        factory.createVault(params, operator, address(apexStrategy));
        vm.stopPrank();
    }

    function test_CreateVaultSuccessfully() public {
        // Set supported asset
        address[] memory assets = new address[](1);
        assets[0] = address(usdt);
        uint256[] memory minimumDeposits = new uint256[](1);
        minimumDeposits[0] = MINIMUM_DEPOSIT;
        factory.setSupportedAssets(assets, minimumDeposits);

        // Setup vault parameters
        string memory vaultName = "Test Vault";
        string memory vaultSymbol = "TV";

        VaultParameters memory params = VaultParameters({
            underlying: address(usdt),
            name: vaultName,
            symbol: vaultSymbol,
            agent: agent,
            initialAgentDeposit: MINIMUM_DEPOSIT,
            minDeposit: MINIMUM_DEPOSIT,
            maxDeposit: MINIMUM_DEPOSIT * 2,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: bytes("")
        });

        // Create signature for vault creation
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                factory.domainSeparator(),
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
        params.protocolParams = protocolParams;

        // Grant operator role for vault creation
        factory.grantRole(factory.OPERATOR_ROLE(), operator);

        // Create the vault
        vm.startPrank(agent);
        usdt.approve(address(factory), UINT256_MAX);
        uint256 balanceBefore = usdt.balanceOf(agent);
        
        address vaultAddress = factory.createVault(params, operator, address(apexStrategy));
        vm.stopPrank();
        
        // Verify vault creation
        Vault vault = Vault(vaultAddress);
        
        uint256 balanceAfter = usdt.balanceOf(agent);

        // Check vault properties
        assertEq(vault.name(), vaultName);
        assertEq(vault.symbol(), vaultSymbol);
        assertEq(address(vault.UNDERLYING()), address(usdt));
        assertEq(vault.agent(), agent);

        // Check token transfers
        assertEq(balanceBefore - balanceAfter, MINIMUM_DEPOSIT);
        
        // Check initial deposit and share minting
        assertEq(vault.balanceOf(agent), MINIMUM_DEPOSIT); // Initial shares should equal deposit amount
    }

    function test_CreateVaultWithInvalidStrategy() public {
        // Set supported asset
        address[] memory assets = new address[](1);
        assets[0] = address(usdt);
        uint256[] memory minimumDeposits = new uint256[](1);
        minimumDeposits[0] = MINIMUM_DEPOSIT;
        factory.setSupportedAssets(assets, minimumDeposits);

        // Setup vault parameters
        VaultParameters memory params = VaultParameters({
            underlying: address(usdt),
            name: "Invalid Strategy Vault",
            symbol: "ISV",
            agent: agent,
            initialAgentDeposit: MINIMUM_DEPOSIT,
            minDeposit: MINIMUM_DEPOSIT,
            maxDeposit: MINIMUM_DEPOSIT * 2,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: bytes("")
        });

        // Create a non-whitelisted strategy address
        address invalidStrategy = address(0x123456789);

        // Create signature for vault creation
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                factory.domainSeparator(),
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
        params.protocolParams = protocolParams;

        // Grant operator role
        factory.grantRole(factory.OPERATOR_ROLE(), operator);

        // Expect revert due to invalid strategy
        vm.startPrank(agent);
        vm.expectRevert(abi.encodeWithSignature("PDefaiInvalidStrategy()"));
        factory.createVault(params, operator, invalidStrategy);
        vm.stopPrank();
    }

    function test_CreateVaultWithOperatorPermissions() public {
        // Set supported asset
        address[] memory assets = new address[](1);
        assets[0] = address(usdt);
        uint256[] memory minimumDeposits = new uint256[](1);
        minimumDeposits[0] = MINIMUM_DEPOSIT;
        factory.setSupportedAssets(assets, minimumDeposits);

        // Setup vault parameters
        VaultParameters memory params = VaultParameters({
            underlying: address(usdt),
            name: "Operator Permission Vault",
            symbol: "OPV",
            agent: agent,
            initialAgentDeposit: MINIMUM_DEPOSIT,
            minDeposit: MINIMUM_DEPOSIT,
            maxDeposit: MINIMUM_DEPOSIT * 2,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: bytes("")
        });

        // Create signature for vault creation
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                factory.domainSeparator(),
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
        params.protocolParams = protocolParams;

        // Use a non-operator address
        address nonOperator = makeAddr("nonOperator");

        // Expect revert due to missing operator role
        vm.startPrank(agent);
        vm.expectRevert(abi.encodeWithSignature("PDefaiNoValidRole()"));
        factory.createVault(params, nonOperator, address(apexStrategy));
        vm.stopPrank();
    }

    function test_CreateVaultWithInvalidSignature() public {
        // Set supported asset
        address[] memory assets = new address[](1);
        assets[0] = address(usdt);
        uint256[] memory minimumDeposits = new uint256[](1);
        minimumDeposits[0] = MINIMUM_DEPOSIT;
        factory.setSupportedAssets(assets, minimumDeposits);

        // Setup vault parameters
        VaultParameters memory params = VaultParameters({
            underlying: address(usdt),
            name: "Invalid Signature Vault",
            symbol: "ISV",
            agent: agent,
            initialAgentDeposit: MINIMUM_DEPOSIT,
            minDeposit: MINIMUM_DEPOSIT,
            maxDeposit: MINIMUM_DEPOSIT * 2,
            veriSig: EIP712Signature(0, bytes32(0), bytes32(0), 0),
            protocolParams: bytes("")
        });

        // Create an invalid signature (wrong signer)
        uint256 wrongPrivateKey = 0xDEADBEEF;
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                factory.domainSeparator(),
                keccak256(
                    abi.encode(
                        protocolParams,
                        deadline
                    )
                )
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);
        
        EIP712Signature memory sig = EIP712Signature({
            v: v,
            r: r,
            s: s,
            deadline: deadline
        });
        
        params.veriSig = sig;
        params.protocolParams = protocolParams;

        // Grant operator role
        factory.grantRole(factory.OPERATOR_ROLE(), operator);

        // Expect revert due to invalid signature
        vm.startPrank(agent);
        vm.expectRevert("SIG_INVALID");
        factory.createVault(params, operator, address(apexStrategy));
        vm.stopPrank();
    }

    function test_UpdateVaultDeployer() public {
        // Deploy new vault deployer
        VaultDeployer newDeployer = new VaultDeployer(address(factory));
        
        // Update the vault deployer
        factory.setVaultDeployer(address(newDeployer));
        
        // Verify the update
        assertEq(address(factory.vaultDeployer()), address(newDeployer));
    }

    function test_SetDefaultOperator() public {
        // Set new default operator
        address newDefaultOperator = makeAddr("newDefaultOperator");
        factory.setDefaultOperator(newDefaultOperator);
        
        // Verify the update
        assertEq(factory.defaultOperator(), newDefaultOperator);
    }

    // Helper function to calculate vault registry hash key
    function getVaultHashKey(string memory name, string memory symbol) internal pure returns (bytes32) {
        return keccak256(abi.encode(name, symbol));
    }
}