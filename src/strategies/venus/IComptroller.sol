// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IComptroller
 * @notice Interface for Venus Protocol's Comptroller contract
 * @dev The Comptroller implements the risk control mechanisms for the Venus protocol
 */
interface IComptroller {
    /**
     * @notice Enter a list of markets (vTokens)
     * @param vTokens The addresses of the vToken markets to enter
     * @return A list of error codes (0 means success, otherwise an error code)
     */
    function enterMarkets(address[] calldata vTokens) external returns (uint256[] memory);
    
    /**
     * @notice Exit a market (vToken)
     * @param vToken The address of the vToken market to exit
     * @return 0 on success, otherwise an error code
     */
    function exitMarket(address vToken) external returns (uint256);
    
    /**
     * @notice Get the markets (vTokens) an account has entered
     * @param account The address of the account
     * @return A dynamic array of vToken addresses
     */
    function getAssetsIn(address account) external view returns (address[] memory);
    
    /**
     * @notice Check if an account can borrow a specific amount from a vToken market
     * @param vToken The vToken to borrow from
     * @param borrower The account that would borrow
     * @param borrowAmount The amount of underlying to borrow
     * @return 0 if the account can borrow, otherwise an error code
     */
    function borrowAllowed(address vToken, address borrower, uint256 borrowAmount) external returns (uint256);
    
    /**
     * @notice Check if an account can repay a specific amount to a vToken market
     * @param vToken The vToken to repay to
     * @param payer The account that would repay
     * @param borrower The account that borrowed
     * @param repayAmount The amount of underlying to repay
     * @return 0 if the account can repay, otherwise an error code
     */
    function repayBorrowAllowed(address vToken, address payer, address borrower, uint256 repayAmount) external returns (uint256);
    
    /**
     * @notice Check if an account can supply a specific amount to a vToken market
     * @param vToken The vToken to supply to
     * @param supplier The account that would supply
     * @param mintAmount The amount of underlying to supply
     * @return 0 if the account can supply, otherwise an error code
     */
    function mintAllowed(address vToken, address supplier, uint256 mintAmount) external returns (uint256);
    
    /**
     * @notice Check if an account can redeem a specific amount from a vToken market
     * @param vToken The vToken to redeem from
     * @param redeemer The account that would redeem
     * @param redeemTokens The amount of vTokens to redeem
     * @return 0 if the account can redeem, otherwise an error code
     */
    function redeemAllowed(address vToken, address redeemer, uint256 redeemTokens) external returns (uint256);
    
    /**
     * @notice Get the Venus (XVS) rewards accrued but not yet claimed by an account
     * @param account The account to check
     * @return The amount of XVS accrued by the account
     */
    function venusAccrued(address account) external view returns (uint256);
    
    /**
     * @notice Claim all Venus (XVS) rewards accrued by an account
     * @param holder The account to claim for
     */
    function claimVenus(address holder) external;
    
    /**
     * @notice Claim all Venus (XVS) rewards accrued by multiple accounts
     * @param holders The accounts to claim for
     * @param vTokens The vToken markets to claim for
     * @param borrowers Whether to claim for borrowing rewards
     * @param suppliers Whether to claim for supply rewards
     */
    function claimVenus(address[] calldata holders, address[] calldata vTokens, bool borrowers, bool suppliers) external;
    
    /**
     * @notice Calculate the amount of Venus (XVS) rewards accrued by an account for a specific vToken
     * @param vToken The vToken market to get rewards for
     * @param account The account to check
     * @return The amount of XVS accrued for the account in the vToken market
     */
    function venusAccrued(address vToken, address account) external view returns (uint256);
    
    /**
     * @notice Get the address of the Venus (XVS) token
     * @return The address of the XVS token
     */
    function getVenusAddress() external view returns (address);
    
    /**
     * @notice Get the liquidity of an account (adjusted collateral value minus borrowed value)
     * @param account The account to check
     * @return error The error code (0 means success)
     * @return liquidity The liquidity of the account (if positive, can borrow more)
     * @return shortfall The shortfall of the account (if positive, is subject to liquidation)
     */
    function getAccountLiquidity(address account) external view returns (uint256 error, uint256 liquidity, uint256 shortfall);
    
    /**
     * @notice Get all markets (vTokens) that are listed in the Comptroller
     * @return A dynamic array of vToken addresses
     */
    function getAllMarkets() external view returns (address[] memory);
    
    /**
     * @notice Check if a vToken is listed in the Comptroller
     * @param vToken The vToken to check
     * @return True if the vToken is listed, otherwise false
     */
    function isMarketListed(address vToken) external view returns (bool);
    
    function markets(address vToken) external view returns (bool isListed, uint256 collateralFactorMantissa);
}