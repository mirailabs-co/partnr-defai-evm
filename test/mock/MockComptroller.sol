// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockComptroller
 * @notice A simple mock for Venus Comptroller contract
 */
contract MockComptroller is Ownable {
    // Track market memberships
    mapping(address => mapping(address => bool)) public markets; // account -> market -> isMember

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Enter markets (mint/borrow)
     * @param vTokens The addresses of the markets to enter
     * @return A list of error codes (0 means success)
     */
    function enterMarkets(address[] memory vTokens) external returns (uint256[] memory) {
        uint256[] memory results = new uint256[](vTokens.length);
        
        for (uint256 i = 0; i < vTokens.length; i++) {
            markets[msg.sender][vTokens[i]] = true;
            results[i] = 0; // Success
        }
        
        return results;
    }

    /**
     * @notice Exit a market
     * @param vToken The address of the market to exit
     * @return 0 on success, otherwise an error code
     */
    function exitMarket(address vToken) external returns (uint256) {
        markets[msg.sender][vToken] = false;
        return 0; // Success
    }

    /**
     * @notice Check if an account is in a market
     * @param account The account to check
     * @param vToken The market to check
     * @return Whether the account is in the market
     */
    function checkMembership(address account, address vToken) external view returns (bool) {
        return markets[account][vToken];
    }

    /**
     * @notice Get all markets an account is in
     * @param account The account to check
     * @return The vToken addresses the account is in
     */
    function getAssetsIn(address account) external view returns (address[] memory) {
        // This is simplified for the mock
        // In a real implementation, we would track all vTokens and filter those the account is in
        return new address[](0);
    }

    /**
     * @notice Mock function for mint allowed
     * @return 0 indicating success (always allowed in mock)
     */
    function mintAllowed(address vToken, address minter, uint256 mintAmount) external pure returns (uint256) {
        return 0; // Always allowed
    }

    /**
     * @notice Mock function for redeem allowed
     * @return 0 indicating success (always allowed in mock)
     */
    function redeemAllowed(address vToken, address redeemer, uint256 redeemTokens) external pure returns (uint256) {
        return 0; // Always allowed
    }
}