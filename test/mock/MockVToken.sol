// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockVToken
 * @notice A simple mock for Venus VToken contracts
 */
contract MockVToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    address public underlying;
    uint256 public exchangeRate;
    mapping(address => bool) public accountMembership;

    constructor(
        string memory name_,
        string memory symbol_,
        address underlying_,
        uint256 exchangeRate_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        underlying = underlying_;
        exchangeRate = exchangeRate_; // Initial exchange rate (e.g., 1e18 means 1:1)
    }

    /**
     * @notice Get the stored exchange rate
     * @return The current exchange rate (scaled by 1e18)
     */
    function exchangeRateStored() external view returns (uint256) {
        return exchangeRate;
    }

    /**
     * @notice Get the current exchange rate
     * @return The current exchange rate (scaled by 1e18)
     */
    function exchangeRateCurrent() external returns (uint256) {
        return exchangeRate;
    }

    /**
     * @notice Supply underlying to mint vTokens
     * @param mintAmount The amount of underlying to supply
     * @return 0 on success
     */
    function mint(uint256 mintAmount) external returns (uint256) {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), mintAmount);
        
        // Calculate vTokens to mint based on exchange rate
        uint256 vTokenAmount = (mintAmount * 1e18) / exchangeRate;
        _mint(msg.sender, vTokenAmount);
        
        return 0;
    }

    /**
     * @notice Redeem vTokens for underlying
     * @param redeemTokens The amount of vTokens to redeem
     * @return 0 on success
     */
    function redeem(uint256 redeemTokens) external returns (uint256) {
        require(balanceOf(msg.sender) >= redeemTokens, "Insufficient vToken balance");
        
        // Calculate underlying to return
        uint256 underlyingAmount = (redeemTokens * exchangeRate) / 1e18;
        require(IERC20(underlying).balanceOf(address(this)) >= underlyingAmount, "Insufficient underlying");
        
        // Burn vTokens
        _burn(msg.sender, redeemTokens);
        
        // Return underlying
        IERC20(underlying).safeTransfer(msg.sender, underlyingAmount);
        
        return 0;
    }

    /**
     * @notice Redeem vTokens for a specific amount of underlying
     * @param redeemAmount The amount of underlying to receive
     * @return 0 on success
     */
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {
        uint256 vTokenAmount = (redeemAmount * 1e18) / exchangeRate;
        require(balanceOf(msg.sender) >= vTokenAmount, "Insufficient vToken balance");
        require(IERC20(underlying).balanceOf(address(this)) >= redeemAmount, "Insufficient underlying");
        
        // Burn vTokens
        _burn(msg.sender, vTokenAmount);
        
        // Return underlying
        IERC20(underlying).safeTransfer(msg.sender, redeemAmount);
        
        return 0;
    }

    /**
     * @notice Update the exchange rate (for testing)
     * @param newExchangeRate The new exchange rate
     */
    function setExchangeRate(uint256 newExchangeRate) external onlyOwner {
        exchangeRate = newExchangeRate;
    }
}