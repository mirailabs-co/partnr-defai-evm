// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/VaultFactory.sol";
import "../src/Vault.sol";
import "../src/VaultDeployer.sol";
import "./mock/USDT.sol";
import "./mock/ActionMock.sol";
import {EIP712Signature} from "../src/libraries/SigValidationHelpers.sol";

contract VaultFactorySigTest is Test {
    VaultFactory public factory;
    VaultDeployer public deployer;
    address constant vUSDT = 0xb7526572FFE56AB9D7489838Bf2E18e3323b441A;
    address constant USDT = 0xA11c8D9DC9b66E209Ef60F0C8D969D3CD988782c;
    address public owner;
    address public operator;
    address public agent;
    address public user1;
    
    uint256 public constant MINIMUM_DEPOSIT = 1000 * 1e18;
    uint256 public constant INITIAL_BALANCE = 10000 * 1e18;
    
    // Private keys for signature testing
    uint256 constant operatorPrivateKey = 0x4;
    uint256 constant agentPrivateKey = 0x5;
    uint256 constant userPrivateKey = 0x6;

    uint8[] substitutionOffsets =  new uint8[](1);
    
    function setUp() public {
        owner = address(this);
        operator = vm.addr(operatorPrivateKey);
        agent = vm.addr(agentPrivateKey);
        user1 = vm.addr(userPrivateKey);

        // Deploy factory
        factory = new VaultFactory();
        factory.initialize(owner, operator);

        // Deploy vault deployer
        deployer = new VaultDeployer(address(factory));
        factory.setVaultDeployer(address(deployer));
        

        // assertEq(factory.owner(), owner);
        // assertEq(factory.operator(), operator);

        substitutionOffsets[0] = 4;
    }

    // function _signDepositActions(DepositExecution[] memory actions, uint256 deadline) internal view returns (EIP712Signature memory) {
    //     bytes32[] memory targetHashes = new bytes32[](actions.length);
    //     bytes32[] memory paramHashes = new bytes32[](actions.length);
        
    //     for (uint i = 0; i < actions.length; i++) {
    //         targetHashes[i] = keccak256(abi.encode(actions[i].target));
    //         paramHashes[i] = keccak256(abi.encode(actions[i].params));
    //     }

    //     console.logBytes32(targetHashes[0]);
    //     console.logBytes32(paramHashes[0]);
    //     bytes32 digest = _getActionDigest(targetHashes, paramHashes, deadline);
    //     console.log("digest ");
    //     console.logBytes32(digest);
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPrivateKey, digest);
        
    //     return EIP712Signature({
    //         v: v,
    //         r: r,
    //         s: s,
    //         deadline: deadline
    //     });
    // }
    
    // Helper to calculate the digest for action signing
    function _getActionDigest(bytes32[] memory targetHashes, bytes32[] memory paramHashes, uint256 deadline) internal view returns (bytes32) {
        bytes32 hashedData = keccak256(
            abi.encode(
                targetHashes,
                paramHashes,
                1740972315
            )
        );

        console.log("hashedData ");
        console.logBytes32(hashedData);
        
        bytes32 domainSeparator = factory.domainSeparator();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, hashedData));
    }

    // Tests for Signature Validation with VaultFactory
    
    function test_WithdrawWithValidActionSignature() public {
        Fee[] memory fees = new Fee[](1);
        fees[0] = Fee(FeeType.WITHDRAW_FEE, 0x0f4240, 0x29b0801f910F7436533Cc8b2f5D29F98B3c908dE);

        uint256 numberOfFee = fees.length;

        bytes32[] memory feeHashes = new bytes32[](numberOfFee);
        for (uint i = 0; i < numberOfFee; i++) {
            require(fees[i].fee > 0);

            feeHashes[i] = keccak256(
                abi.encode(fees[i].feeType, fees[i].receiver, fees[i].fee)
            );
        }

        console.logBytes32(feeHashes[0]);
        console.logBytes32(keccak256(abi.encode(feeHashes)));

        console.logBytes32(
            keccak256(
                abi.encode(
                    0x4c4b40,
                    0xDe2bB28e02d71337658Be35122251f2AbF0578aC,
                    keccak256(abi.encode(feeHashes)),
                    1741860881
                )
            )
        );

        // bytes32 digest = keccak256(
        //     abi.encodePacked(
        //         "\x19\x01",
        //         vault.domainSeparator(),
        //         keccak256(
        //             abi.encode(
        //                 withdrawAmount,
        //                 receiver,
        //                 keccak256(abi.encode(fees)),
        //                 deadline
        //             )
        //         )
        //     )
        // );
        
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPrivateKey, digest);

    }

}