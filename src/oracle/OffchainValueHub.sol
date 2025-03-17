// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IOffchainValueHub.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultFactory.sol";

/**
 * @title OffchainValueHub
 * @notice Manages off-chain valuation for vaults where on-chain value calculation is not feasible
 * @dev Implements UUPSUpgradeable and AccessControlUpgradeable for secure upgradeability and access management
 */
contract OffchainValueHub is 
    IOffchainValueHub, 
    AccessControlUpgradeable, 
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;

    bytes32 public constant VALUE_PROVIDER_ROLE = keccak256("VALUE_PROVIDER_ROLE");

    // Storage variables
    struct VaultValueData {
        uint256 value;          // Current value of the vault
        uint256 lastUpdateTime; // Timestamp of the last update
    }

    // VaultFactory reference for vault verification
    IVaultFactory public vaultFactory;

    // Mapping of vault address to its value data
    mapping(address => VaultValueData) private _vaultValues;
    
    // Maximum allowable percentage change in value updates
    uint256 public minValueChangePercentage; // Based on 10000 = 100%

    // Staleness threshold in seconds (0 means values never expire)
    uint256 public stalenessThreshold;

    /**
     * @notice Initialize the contract with the default admin and roles
     * @param admin Address to be granted the admin role
     * @param valueProvider Address to be granted the value provider role
     * @param initialMaxValueChange Maximum allowed percentage change in value (base 10000)
     * @param initialStalenessThreshold Time in seconds after which a value is considered stale (0 = never expires)
     * @param factory Address of the VaultFactory contract
     */
    function initialize(
        address admin,
        address valueProvider,
        uint256 initialMaxValueChange,
        uint256 initialStalenessThreshold,
        address factory
    ) public initializer {
        require(admin != address(0), "Admin cannot be zero address");
        require(factory != address(0), "Factory cannot be zero address");
        
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VALUE_PROVIDER_ROLE, valueProvider);
        
        minValueChangePercentage = initialMaxValueChange;
        stalenessThreshold = initialStalenessThreshold;
        vaultFactory = IVaultFactory(factory);
    }

    /**
     * @notice Sets the current total value for a specific vault
     * @param vault Address of the vault to update
     * @param _value Total value in underlying asset units
     * @return The updated vault value
     */
    function setVaultValue(address vault, uint256 _value) 
        external 
        override 
        onlyRole(VALUE_PROVIDER_ROLE) 
        returns (uint256) 
    {
        require(isAssociatedVault(vault), "Vault not registered");
        
        VaultValueData storage vaultData = _vaultValues[vault];
        uint256 oldValue = vaultData.value;
        
        /**
         * If the price is stale, update the new value right away without checking
         */
        if (stalenessThreshold > 0 && block.timestamp - vaultData.lastUpdateTime >= stalenessThreshold) {
            vaultData.value = _value;
            vaultData.lastUpdateTime = block.timestamp;
            
            emit VaultValueUpdated(vault, oldValue, _value, msg.sender);
            
            return _value;
        }

        // Validate value change is within acceptable limits if not the first update
        if (oldValue > 0) {
            uint256 changePercentage;
            if (_value > oldValue) {
                changePercentage = ((_value - oldValue) * 10000) / oldValue;
            } else {
                changePercentage = ((oldValue - _value) * 10000) / oldValue;
            }
            
            require(
                changePercentage >= minValueChangePercentage, 
                "Value change lesser permitted minimum votatility"
            );
        }
        
        // Update the value and timestamp
        vaultData.value = _value;
        vaultData.lastUpdateTime = block.timestamp;
        
        emit VaultValueUpdated(vault, oldValue, _value, msg.sender);
        
        return _value;
    }
    
    /**
     * @notice Retrieves the current value for a specific vault
     * if the vault's value has not been updated before, return 0 instead of revert
     * @param vault Address of the vault to query
     * @param params Optional encoded parameters for value calculation
     * @return amount The total value in underlying asset units
     */
    function value(address vault, bytes calldata params) 
        external 
        view 
        override 
        returns (uint256 amount) 
    {
        require(isAssociatedVault(vault), "Vault not registered");
        
        VaultValueData storage vaultData = _vaultValues[vault];
        
        // Check if value is stale (if stalenessThreshold is 0, values never expire)
        if (stalenessThreshold > 0) {
            if (vaultData.lastUpdateTime == 0) {
                return 0;
            }

            require(
                block.timestamp - vaultData.lastUpdateTime <= stalenessThreshold,
                "VAULT_VALUE_STALE"
            );
        }

        return vaultData.value;
    }

    /**
     * @notice Checks if a vault is registered with the VaultFactory
     * @param vault Address of the vault to check
     * @return True if the vault is registered with the factory
     */
    function isAssociatedVault(address vault) 
        public 
        view 
        override 
        returns (bool) 
    {
        return vaultFactory.existedVault(vault);
    }
    
    /**
     * @notice Retrieves the value and its last update timestamp for a vault
     * @param vault Address of the vault to query
     * @return value The total value in underlying asset units
     * @return timestamp When the value was last updated
     */
    function getValueWithTimestamp(address vault) 
        external 
        view 
        returns (uint256 value, uint256 timestamp) 
    {
        require(isAssociatedVault(vault), "Vault not registered");
        
        VaultValueData storage vaultData = _vaultValues[vault];
        return (vaultData.value, vaultData.lastUpdateTime);
    }
    
    /**
     * @notice Update the min allowable percentage change for value updates
     * @param newMinChangePercentage New max percentage (base 10000)
     */
    function setMinValueChangePercentage(uint256 newMinChangePercentage) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        minValueChangePercentage = newMinChangePercentage;
    }
    
    /**
     * @notice Update the staleness threshold
     * @param newStalenessThreshold New threshold in seconds (0 = never expires)
     */
    function setStalenessThreshold(uint256 newStalenessThreshold) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        stalenessThreshold = newStalenessThreshold;
    }
    
    /**
     * @notice Update the VaultFactory reference
     * @param newFactory Address of the new VaultFactory contract
     */
    function setVaultFactory(address newFactory) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newFactory != address(0), "Factory cannot be zero address");
        vaultFactory = IVaultFactory(newFactory);
    }
    
    /**
     * @notice Function that allows a vault to pull its own value
     * @dev This is useful for integration with existing vault contracts
     * @param params Optional parameters that might be required
     * @return The current value of the calling vault
     */
    function getCallerValue(bytes calldata params) 
        external 
        view 
        returns (uint256) 
    {
        return this.value(msg.sender, params);
    }
    
    /**
     * @notice Configure authorization for contract upgrades (UUPS pattern)
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {}
}