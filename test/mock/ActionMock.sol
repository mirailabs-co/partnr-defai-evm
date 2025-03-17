// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ActionMock {
    event ActionExecuted(address caller, uint256 value);
    event TokenTransferred(address token, address recipient, uint256 amount);
    event DepositRegistered(uint256 depositAmount, address depositor);
    
    uint256 public callCount;
    uint256 public lastDepositAmount;
    address public lastDepositor;
    
    // Static function - used to test regular actions
    function executeAction(uint256 value) external {
        callCount++;
        emit ActionExecuted(msg.sender, value);
    }
    
    // Dynamic function - used to test deposit amount substitution
    function handleDeposit(uint256 depositAmount, address depositor) external {
        callCount++;
        lastDepositAmount = depositAmount;
        lastDepositor = depositor;
        emit DepositRegistered(depositAmount, depositor);
    }
    
    // Function to transfer tokens - used for both static and dynamic testing
    function transferToken(address token, address recipient, uint256 amount) external {
        IERC20(token).transfer(recipient, amount);
        emit TokenTransferred(token, recipient, amount);
    }

    // Function that always fails - for testing error handling
    function failingAction() external pure {
        revert("Action failed intentionally");
    }
}