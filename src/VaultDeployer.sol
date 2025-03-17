// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Vault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVaultDeployer.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

/**
 * Seperate Deployer vs Factory to avoid contract size limit
 * TODO use simple proxy to point to vault contract code to reduce gas cost
 * when creating new vault
 */
contract VaultDeployer is IVaultDeployer, Ownable {
    constructor(address owner) Ownable(owner) {}

    function createVault(
        address owner,
        address underlying,
        string memory name,
        string memory symbol,
        address agent,
        uint256 mintDeposit_,
        uint256 maxDeposit_
    ) public onlyOwner override returns (address)  {
        return address(new Vault(
            owner,
            underlying,
            name,
            symbol,
            agent,
            mintDeposit_,
            maxDeposit_
        ));
    }
}
