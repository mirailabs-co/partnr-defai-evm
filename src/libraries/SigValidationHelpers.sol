// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IVault} from "../interfaces/IVault.sol";
import "./Constants.sol";
import {Execution} from "../interfaces/IStrategy.sol";

/**
 * @notice A struct containing the necessary information to reconstruct an EIP-712 typed data signature.
 *
 * @param v The signature's recovery parameter.
 * @param r The signature's r parameter.
 * @param s The signature's s parameter
 * @param deadline The signature's deadline
 */
struct EIP712Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
    uint256 deadline;
}


library SigValidationHelpers {
    /**
     * Support both ERC1271 and traditional signature
     * @param digest hash data
     * @param expectedAddress expected address
     * @param sig signature struct includes v,r,s,deadline
     */
    function _validateRecoveredAddress(bytes32 digest, address expectedAddress, EIP712Signature calldata sig)
        internal
        view
    {
        require(sig.deadline >= block.timestamp, "SIG_EXPIRED");
        address recoveredAddress = expectedAddress;
        // If the expected address is a contract, check the signature there.

        if (recoveredAddress.code.length != 0) {
            bytes memory concatenatedSig = abi.encodePacked(sig.r, sig.s, sig.v);
            require(
                IERC1271(expectedAddress).isValidSignature(digest, concatenatedSig) == EIP1271_MAGIC_VALUE,
                "SIG_INVALID"
            );
        } else {
            recoveredAddress = ecrecover(digest, sig.v, sig.r, sig.s);

            require(recoveredAddress != address(0) && recoveredAddress == expectedAddress, "SIG_INVALID");
        }
    }

    /**
     * @dev Calculates EIP712 digest based on the current DOMAIN_SEPARATOR.
     *
     * @param hashedMessage The message hash from which the digest should be calculated.
     * @param domainSeparator The domain separator to use in creating the digest.
     *
     * @return bytes32 A 32-byte output representing the EIP712 digest.
     */
    function _calculateDigest(bytes32 hashedMessage, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 digest;
        unchecked {
            digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, hashedMessage));
        }
        return digest;
    }
    
    /**
     * Validate the signature over the chain of action(target,params)
     * @param signer signer
     * @param actions chain of action
     * @param signature signature struct includes v,r,s,deadline
     * @param DOMAIN_SEPARATOR DOMAIN_SEPARATOR
     */
    function _validateActions(
        address signer,
        Execution[] calldata actions,
        EIP712Signature calldata signature,
        bytes32 DOMAIN_SEPARATOR
    ) internal view {
        uint256 len = actions.length;
        bytes32[] memory targetHashes = new bytes32[](len);
        bytes32[] memory paramHashes = new bytes32[](len);

        for (uint256 i = 0; i < len;) {
            targetHashes[i] = keccak256(abi.encode(actions[i].target));
            paramHashes[i] = keccak256(abi.encode(actions[i].params));

            unchecked { ++i; }
        }

        unchecked {
            SigValidationHelpers._validateRecoveredAddress(
                SigValidationHelpers._calculateDigest(
                    keccak256(
                        abi.encode(
                            targetHashes,
                            paramHashes,
                            signature.deadline
                        )
                    ),
                    DOMAIN_SEPARATOR
                ),
                signer,
                signature
            );
        }
    }
}
