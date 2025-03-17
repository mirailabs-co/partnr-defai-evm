// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {EIP712Signature} from "../libraries/SigValidationHelpers.sol";

struct VaultParameters {
    // The AI agent's address - only the agent can execute strategy actions
    address agent;
    // The principal token (e.g., USDT, USDC)
    address underlying;
    // share token name
    string name;
    // share token symbol
    string symbol;
    // initial deposit amount
    uint256 initialAgentDeposit;
    // minimum deposit
    uint256 minDeposit;
    // maximum deposit
    uint256 maxDeposit;
    // extra protocol-related data
    bytes protocolParams;

    // signature over protocolParams
    EIP712Signature veriSig;
}

interface IVaultFactory {
    event CreateVault(address indexed vault, address agent, address underlying, uint256 amount);

    /**
     * Create vault entitled by vault agent, only
     * @dev Only callable by the owner
     * @param params vault parameters
     * @param _operator vault parameters
     * @param strategy which is defined the default actions, how to calculate vault value and withdraw logic
     */
    function createVault(VaultParameters calldata params, address _operator, address strategy) external payable returns (address vault);

    function existedVault(address vault) external view returns(bool);
}
