// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVaultDeployer{
    function createVault(
        address owner,
        address underlying,
        string memory name,
        string memory symbol,
        address agent,
        uint256 minDeposit,
        uint256 maxDeposit
    ) external returns(address);
}