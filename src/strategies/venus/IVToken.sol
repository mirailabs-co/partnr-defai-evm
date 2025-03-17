// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title IVToken
 * @notice Interface for Venus Protocol vTokens (e.g., vUSDT, vBUSDT, etc.)
 */
interface IVToken is IERC20 {
    /**
     * @notice Get the underlying asset address
     * @return The address of the underlying asset
     */
    function underlying() external view returns (address);
    
    /**
     * @notice Get the current exchange rate between vTokens and underlying
     * @return The current exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint256);
    
    /**
     * @notice Get the current exchange rate calculated this block
     * @return The current exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external returns (uint256);
    
    /**
     * @notice Supply underlying to the Venus protocol and receive vTokens
     * @param mintAmount The amount of underlying to supply
     * @return 0 on success, otherwise an error code
     */
    function mint(uint256 mintAmount) external returns (uint256);
    
    /**
     * @notice Redeem vTokens for underlying
     * @param redeemTokens The amount of vTokens to redeem
     * @return 0 on success, otherwise an error code
     */
    function redeem(uint256 redeemTokens) external returns (uint256);
    
    /**
     * @notice Redeem vTokens for a specific amount of underlying
     * @param redeemAmount The amount of underlying to receive
     * @return 0 on success, otherwise an error code
     */
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    
    /**
     * @notice Borrow underlying from the Venus protocol
     * @param borrowAmount The amount of underlying to borrow
     * @return 0 on success, otherwise an error code
     */
    function borrow(uint256 borrowAmount) external returns (uint256);
    
    /**
     * @notice Repay borrowed underlying to the Venus protocol
     * @param repayAmount The amount of underlying to repay
     * @return 0 on success, otherwise an error code
     */
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    
    /**
     * @notice Repay borrowed underlying on behalf of another account
     * @param borrower The account to repay for
     * @param repayAmount The amount of underlying to repay
     * @return 0 on success, otherwise an error code
     */
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
    
    /**
     * @notice Get the current borrowing balance of an account
     * @param account The account to check
     * @return The borrowing balance of the account
     */
    function borrowBalanceStored(address account) external view returns (uint256);
    
    /**
     * @notice Get the current borrow rate per block
     * @return The borrow rate per block scaled by 1e18
     */
    function borrowRatePerBlock() external view returns (uint256);
    
    /**
     * @notice Get the current supply rate per block
     * @return The supply rate per block scaled by 1e18
     */
    function supplyRatePerBlock() external view returns (uint256);
    
    /**
     * @notice Get the total amount of outstanding borrows
     * @return The total borrows
     */
    function totalBorrows() external view returns (uint256);
    
    /**
     * @notice Get the total amount of reserves
     * @return The total reserves
     */
    function totalReserves() external view returns (uint256);
    
    /**
     * @notice Get the cash balance of this vToken in the underlying asset
     * @return The underlying balance of this contract
     */
    function getCash() external view returns (uint256);
}