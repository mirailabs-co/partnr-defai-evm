// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IVaultDeployer.sol";
import "./interfaces/IVault.sol";

contract VaultFactory is IVaultFactory, UUPSUpgradeable, ReentrancyGuardTransientUpgradeable, EIP712Upgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("VAULT_OPERATOR_ROLE");

    mapping (bytes32 hashkey => address vault) public vaultRegistries;
    mapping (address asset => uint256 minimumDeposit) public supportedAssets;
    IVaultDeployer public vaultDeployer;

    mapping (address strategy => bool) public whitelistedStrategies;
    address public defaultOperator;
    mapping (address vault => bool) public existedVault;

    function initialize(address _owner, address _operator) public virtual initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(OPERATOR_ROLE, _operator);
        defaultOperator = _operator;
        __ReentrancyGuardTransient_init();
        __EIP712_init("VAULT_FACTORY", "1.0");
    }

    /**
     * Set supported assets and minimum deposit for each
     * minimumDeposit = 0 mean that asset is not supported
     * @param assets list of assets
     * @param minimumDeposits  minimum amount deposit for each kind of asset
     */
    function setSupportedAssets(address[] memory assets, uint256[] memory minimumDeposits) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 length = assets.length;
        for (uint256 i = 0; i < length;) {
            supportedAssets[assets[i]] = minimumDeposits[i];
            unchecked { ++i; }
        }
    }

    function setWhitelistedStrategy(address strategy, bool whitelisted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistedStrategies[strategy] = whitelisted;
    }

    function setVaultDeployer(address _deployer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultDeployer = IVaultDeployer(_deployer);
    }

    function setDefaultOperator(address _operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultOperator = _operator;
    }

    function createVault(VaultParameters calldata params, address _operator, address _strategy) payable public nonReentrant returns (address){
        bytes32 hashKey = keccak256(abi.encode(params.name, params.symbol));

        if (params.underlying == address(0)) revert PDefaiUnspportedAsset(address(0));

        if (vaultRegistries[hashKey] != address(0)) revert PDefaiDeployedVault();

        if (supportedAssets[params.underlying] == 0) revert PDefaiUnspportedAsset(params.underlying);

        if (supportedAssets[params.underlying] > params.initialAgentDeposit) revert PDefaiValueMismatch();
        
        if (!whitelistedStrategies[_strategy]) revert PDefaiInvalidStrategy();
        
        if (!hasRole(OPERATOR_ROLE, _operator)) revert PDefaiNoValidRole();

        if (params.protocolParams.length > 0) {
            unchecked {
                SigValidationHelpers._validateRecoveredAddress(
                    SigValidationHelpers._calculateDigest(
                        keccak256(
                            abi.encode(
                                params.protocolParams,
                                params.veriSig.deadline
                            )
                        ),
                        _domainSeparatorV4()
                    ),
                    _operator,
                    params.veriSig
                );
            }

        }
        
        // use vaul deployer to avoid contract size limit
        if (address(vaultDeployer) == address(0)) revert PDefaiUndefinedVaultDeployer();

        address vault = vaultDeployer.createVault(
            _operator,
            params.underlying,
            params.name,
            params.symbol,
            params.agent,
            params.minDeposit,
            params.maxDeposit
        );
        
        vaultRegistries[hashKey] = address(vault);
        existedVault[vaultRegistries[hashKey]] = true;

        // transfer initial amount to vault, no support native token just stable coins for now
        IERC20(params.underlying).safeTransferFrom(
            msg.sender,
            address(vaultRegistries[hashKey]),
            params.initialAgentDeposit
        );
        
        // init the vault and execute the default actions if needed
        IVault(vault).initialize(params.initialAgentDeposit, _strategy, params.protocolParams);
        
        emit CreateVault(vaultRegistries[hashKey], params.agent, params.underlying, params.initialAgentDeposit);
        
        return vaultRegistries[hashKey];
    }

    function domainSeparator() external view returns(bytes32) {
        return _domainSeparatorV4();
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {
        (newImplementation);
    }

    error PDefaiDeployedVault();
    error PDefaiValueMismatch();
    error PDefaiUnspportedAsset(address);
    error PDefaiUndefinedVaultDeployer();
    error PDefaiNoValidRole();
    error PDefaiInvalidStrategy();

    receive() external payable {}

    fallback() external payable {}
}
