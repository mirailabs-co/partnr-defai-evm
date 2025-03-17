// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct Execution {
    address target;
    bytes params;
}

/**
 * @title IStrategy - Contains immutable configurations and logic only, no storage. The execution context is Vault.
 * @notice each functions has extra params for vault to
 * @author Mirai Labs
 * @notice Never store any data on the strategy. Each strategy can be used with multiple vaults.
 */
interface IStrategy {
    /**
     * @notice Get initialization actions to execute when the vault is created
     * @param initialDeposit The initial deposit amount
     * @return An array of actions to execute during initialization
     */
    function getInitializationActions(uint256 initialDeposit, bytes calldata params) 
        external view returns (Execution[] memory);
    
    /**
     * @notice Get actions to execute when a user deposits
     * @param amount The amount being deposited
     * @return An array of actions to execute for the deposit
     */
    function getDepositActions( uint256 amount, bytes calldata params) 
        external view returns (Execution[] memory);

    
    /**
     * @notice Returns the current value of a vault using this strategy logic.
     * This function is intended to be used with staticcall, so the vault must be passed in.
     * @param amount The amount being deposited.
     * @return amount The amount representing the current value.
     */
    function value(address vault, bytes calldata params) external view returns(uint256 amount);

    /**
     * @notice withdraw directly from the protocol, most protocols support redeemOnBehalf or withdrawOnBehalf
     * @param receiver The receiver
     * @param amount The amount in underlying asset of vault be withdrawn
     */
    function withdraw(address receiver, uint256 amount, bytes calldata params) external;

    /**
     * Some strategies need extra data to be able to execute logic, this interface will abstract away
     * that logic from Vault.
     * @param vault address of vault
     * @param params needed parameters
     */
    function composeProtocolParameters(address vault, bytes calldata params) view external returns (bytes calldata output);
}
