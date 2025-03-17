// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../../interfaces/IStrategy.sol";
import {IVault} from "../../interfaces/IVault.sol";
import "./IApexGateway.sol";
import "../../interfaces/IOffchainValueHub.sol";

/**
 * @title ApexStrategy
 * @notice Strategy for Apex protocol with off-chain value calculation support
 * @dev This strategy integrates with OffchainValueHub for accurate valuation
 */
contract ApexStrategy is IStrategy {
    using SafeERC20 for IERC20;

    // Strategy configuration constants
    uint256 private constant PRICE_PRECISION = 1e6; // 6 decimal places for price precision
    uint256 private constant RESERVE_RATIO = 0;    // 0% liquidity reserve
    
    // Immutable protocol addresses
    address public immutable APEX_GATEWAY;
    address public immutable VALUE_HUB;
    
    /**
     * @notice Constructor sets immutable protocol addresses
     * @param apexGateway_ Deposit gateway for Apex protocol
     * @param valueHub_ Address of the OffchainValueHub contract
     */
    constructor(
        address apexGateway_,
        address valueHub_
    ) {
        require(apexGateway_ != address(0), "Invalid Apex gateway address");
        // allow non-use valueHub
        // require(valueHub_ != address(0), "Invalid value hub address");
        
        APEX_GATEWAY = apexGateway_;
        VALUE_HUB = valueHub_;
    }
    
    /**
     * @notice Get initialization actions for the vault
     * @param initialDeposit The initial deposit amount
     * @param params Set of strategy-related parameters
     * @return An array of actions to execute during initialization
     */
    function getInitializationActions(uint256 initialDeposit, bytes calldata params) 
        external view override returns (Execution[] memory)
    {
        Execution[] memory actions = new Execution[](3);
        
        (
            address underlyingAsset,
            bytes32 zkLinkAddress, 
            uint8 subAccountId, 
            bool _mapping
        ) = abi.decode(params, (address, bytes32, uint8, bool));

        // Action 1: Approve Apex to use the underlying tokens
        bytes memory approveCalldata = abi.encodeWithSignature(
            "approve(address,uint256)",
            APEX_GATEWAY,
            type(uint256).max
        );
        
        actions[0] = Execution({
            target: underlyingAsset,
            params: approveCalldata
        });
        
        // Action 2: Deposit tokens into Apex
        uint256 amountToDeposit = initialDeposit * (100 - RESERVE_RATIO) / 100;
        bytes memory depositCalldata = abi.encodeWithSignature(
            "depositERC20(address,uint104,bytes32,uint8,bool)",
            underlyingAsset,
            amountToDeposit,
            zkLinkAddress,
            subAccountId,
            _mapping
        );
        
        actions[1] = Execution({
            target: APEX_GATEWAY,
            params: depositCalldata
        });
        
        return actions;
    }
    
    /**
     * @notice Get actions for processing a deposit
     * @param amount The amount being deposited
     * @param params Set of strategy-related parameters
     * @return An array of actions to execute for the deposit
     */
    function getDepositActions(uint256 amount, bytes calldata params) 
        external view override returns (Execution[] memory)
    {
        // Calculate how much to deposit to Apex (keeping reserve)
        uint256 amountToDeposit = amount * (100 - RESERVE_RATIO) / 100;
        
        (
            address underlyingAsset,
            bytes32 zkLinkAddress, 
            uint8 subAccountId, 
            bool _mapping
        ) = abi.decode(params, (address, bytes32, uint8, bool));

        // If amount is too small, don't do anything
        if (amountToDeposit == 0) {
            return new Execution[](0);
        }
        
        Execution[] memory actions = new Execution[](1);
        
        // Supply to Apex
        bytes memory depositCalldata = abi.encodeWithSignature(
            "depositERC20(address,uint104,bytes32,uint8,bool)",
            underlyingAsset,
            amountToDeposit,
            zkLinkAddress,
            subAccountId,
            _mapping
        );
        
        actions[0] = Execution({
            target: APEX_GATEWAY,
            params: depositCalldata
        });
        
        return actions;
    }
    
    /**
     * @notice Calculate the vault's value using the OffchainValueHub
     * @param vault Address of the vault to get value for
     * @param params Optional encoded parameters
     * @return The total value of the vault's assets
     */
    function value(address vault, bytes calldata params) public view override returns (uint256) {
        uint256 calculatedValue;
        
        // First check if the vault is registered with the value hub
        if (VALUE_HUB != address(0) && IOffchainValueHub(VALUE_HUB).isAssociatedVault(vault)) {
            calculatedValue = IOffchainValueHub(VALUE_HUB).value(vault, params);
        }

        if (calculatedValue > 0 ) return calculatedValue;
        
        // Fallback to local calculation if value hub doesn't have this vault
        if (params.length > 0) {
            (
                address underlyingAsset,
                ,
                ,
                ,
                uint256 totalDeposit,
                uint256 totalWithdraw
            ) = abi.decode(params, (address, bytes32, uint8, bool, uint256, uint256));
            return IERC20(underlyingAsset).balanceOf(vault) + totalDeposit - totalWithdraw;
        }
        
        return 0;
    }
    
    /**
     * @notice Withdraw assets from the Apex gateway
     * @param receiver Address to receive the withdrawn assets
     * @param amount Amount to withdraw
     * @param params Additional parameters needed for withdrawal
     */
    function withdraw(address receiver, uint256 amount, bytes calldata params) public override {
        (
            address underlyingAsset,,,
        ) = abi.decode(params, (address, bytes32, uint8, bool));

        uint16 tokenId = IApexGateway(APEX_GATEWAY).tokenIds(underlyingAsset);
        
        IApexGateway(APEX_GATEWAY).withdrawPendingBalance(
            receiver,
            tokenId,
            uint128(amount)
        );
    }

    /**
     * @notice Compose protocol parameters for use with this strategy
     * @param vault Address of the vault
     * @param protocolParams Original protocol parameters
     * @return Extended parameters including tracking data
     */
    function composeProtocolParameters(address vault, bytes calldata protocolParams) 
        external view override returns (bytes memory) 
    {
        if (protocolParams.length > 0) {
            // Decode existing params to get the components
            (
                address underlyingAsset,
                bytes32 zkLinkAddress,
                uint8 subAccountId,
                bool useMapping
            ) = abi.decode(protocolParams, (address, bytes32, uint8, bool));
            
            return abi.encode(
                underlyingAsset,
                zkLinkAddress,
                subAccountId,
                useMapping,
                IVault(address(vault)).totalDeposit(),
                IVault(address(vault)).totalWithdraw()
            );
        }

        return bytes("");
    }
    
    error PDefaiRedeemFailed();
}