// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

bytes32 constant DEPOSIT_WITH_SIG_TYPEHASH =
    keccak256("DepositWithSig(uint256 assets,address receiver,uint256 share,uint256 nonce,uint256 deadline)");

bytes32 constant WITHDRAW_WITH_SIG_TYPEHASH =
    keccak256("WithdrawWithSig(uint256 assets,address receiver,address owner,uint256 nonce,uint256 deadline)");

bytes32 constant REDEEM_WITH_SIG_TYPEHASH =
    keccak256("RedeemWithSig(uint256 shares,address receiver,address owner,uint256 nonce,uint256 deadline)");

bytes32 constant EXECUTE_WITH_SIG_TYPEHASH =
    keccak256("Execute(address vault,bytes32 params,uint256 nonce,uint256 deadline)");

uint256 constant SCALE = 1e18;
