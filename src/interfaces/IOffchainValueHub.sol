// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IOffchainValueHub
 * @notice Extension for Strategy to serve as a value oracle for vaults
 * @dev Enables off-chain calculation of vault asset values for protocols 
 * where on-chain value determination is impossible or inefficient
 */
interface IOffchainValueHub {
    /**
     * @notice Sets the current total value for a specific vault
     * @param vault Address of the vault to update
     * @param value Total value in underlying asset units
     * @return The updated vault value
     */
    function setVaultValue(address vault, uint256 value) external returns (uint256);
    
    /**
     * @notice Retrieves the current value for a specific vault
     * @param vault Address of the vault to query
     * @param params Optional encoded parameters for value calculation
     * @return amount The total value in underlying asset units
     */
    function value(address vault, bytes calldata params) external view returns (uint256 amount);

    /**
     * @notice Checks if a vault is registered with this value hub
     * @param vault Address of the vault to check
     * @return True if the vault is associated with this hub
     */
    function isAssociatedVault(address vault) external view returns (bool);
    
    /**
     * @notice Emitted when a vault's value is updated
     * @param vault Address of the vault
     * @param oldValue Previous value in underlying asset units
     * @param newValue Updated value in underlying asset units
     * @param updater Address that performed the update
     */
    event VaultValueUpdated(address indexed vault, uint256 oldValue, uint256 newValue, address indexed updater);
}