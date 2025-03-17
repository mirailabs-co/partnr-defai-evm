// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../../interfaces/IStrategy.sol";
import "./IVToken.sol";
import "./IComptroller.sol";

/**
 * @title VenusStrategy
 * @notice Strategy for Venus protocol that manages deposits into vTokens
 * @dev This strategy contains immutable configurations and logic, no mutable state
 */
contract VenusStrategy is IStrategy {
    using SafeERC20 for IERC20;

    // Strategy configuration constants
    uint256 private constant PRICE_PRECISION = 1e6; // 6 decimal places for price precision
    uint256 private constant RESERVE_RATIO = 0;    // 10% liquidity reserve
    
    // Immutable protocol addresses
    address public immutable VTOKEN;        // Venus token (e.g., vUSDT)
    
    /**
     * @notice Constructor sets immutable protocol addresses
     * @param vToken_ The Venus token address (e.g., vUSDT)
     */
    constructor(
        address vToken_
    ) {
        require(vToken_ != address(0), "Invalid vToken address");
        
        VTOKEN = vToken_;
    }
    
    /**
     * @notice Get initialization actions for the vault
     * @param initialDeposit The initial deposit amount
     * @return An array of actions to execute during initialization
     */
    function getInitializationActions( uint256 initialDeposit,  bytes calldata) 
        external view override returns (Execution[] memory)
    {
        Execution[] memory actions = new Execution[](3);
        
        // Action 1: Approve Venus to use the underlying tokens
        address underlying = IVToken(VTOKEN).underlying();
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            VTOKEN,
            type(uint256).max
        );
        
        actions[0] = Execution({
            target: underlying,
            params: approveCalldata
        });
        
        // Action 2: Mint vTokens with initial deposit (minus reserve)
        uint256 amountToDeposit = initialDeposit * (100 - RESERVE_RATIO) / 100;
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint(uint256)",
            amountToDeposit
        );
        
        actions[1] = Execution({
            target: VTOKEN,
            params: mintCalldata
        });
        
        return actions;
    }
    
    /**
     * @notice Get actions for processing a deposit
     * @param amount The amount being deposited
     * @return An array of actions to execute for the deposit
     */
    function getDepositActions(uint256 amount,  bytes calldata) 
        external view override returns (Execution[] memory)
    {
        // Calculate how much to deposit to Venus (keeping reserve)
        uint256 amountToDeposit = amount * (100 - RESERVE_RATIO) / 100;
        
        // If amount is too small, don't do anything
        if (amountToDeposit == 0) {
            return new Execution[](0);
        }
        
        Execution[] memory actions = new Execution[](1);
        
        // Supply to Venus
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint(uint256)",
            amountToDeposit
        );
        
        actions[0] = Execution({
            target: VTOKEN,
            params: mintCalldata
        });
        
        return actions;
    }
    
    /**
     * TODO: Add any unclaimed rewards (if applicable)
     * This would require interacting with Venus reward mechanisms
     */
    function value(address vault,  bytes calldata) public view override returns (uint256) {
        // Get balance of vTokens
        uint256 vTokenBalance = IVToken(VTOKEN).balanceOf(vault);
        
        // Convert vToken balance to underlying using exchange rate
        uint256 exchangeRate = IVToken(VTOKEN).exchangeRateStored();
        uint256 vTokenValue = (vTokenBalance * exchangeRate) / 1e18;
        
        return vTokenValue;
    }
    
    function withdraw(address receiver, uint256 amount,  bytes calldata) public override {
        IERC20 underlying = IERC20(IVToken(VTOKEN).underlying());
        uint256 err = IVToken(VTOKEN).redeemUnderlying(amount);
        if (err != 0) {
            revert PDefaiRedeemFailed();
        }
        underlying.transfer(receiver, amount);
    }

    function composeProtocolParameters(address, bytes calldata) pure external override returns (bytes memory output) {
        return bytes("");
    }
    
    error PDefaiRedeemFailed();
}