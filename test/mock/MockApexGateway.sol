// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/strategies/apex/IApexGateway.sol";
import "forge-std/console.sol";

/**
 * @title MockApexGateway
 * @notice Mock implementation of the Apex Gateway for testing purposes
 */
contract MockApexGateway  {
    using SafeERC20 for IERC20;
    
    mapping(address => mapping(uint16 => uint128)) public pendingBalances;
    mapping(address => uint16) public  tokenIds;
    mapping(uint16 => TokenInfo) public tokenInfos;
    
    struct TokenInfo {
        bool registered;
        bool paused;
        address tokenAddress;
        uint8 decimals;
    }
    
    uint16 private nextTokenId = 1;
    
    event DepositERC20(address token, uint104 amount, bytes32 zkLinkAddress, uint8 subAccountId, bool mapping_);
    event WithdrawToken(address owner, uint16 tokenId, uint128 amount);
    
    constructor() {}

    function registerToken(address token, uint8 decimals) external {
        uint16 tokenId = nextTokenId++;
        tokenIds[token] = tokenId;
        tokenInfos[tokenId] = TokenInfo({
            registered: true,
            paused: false,
            tokenAddress: token,
            decimals: decimals
        });
    }
    
    function depositETH(bytes32 _zkLinkAddress, uint8 _subAccountId) external payable  {
        // Not implemented for testing
        emit DepositERC20(address(0), uint104(msg.value), _zkLinkAddress, _subAccountId, false);
    }
    
    function depositERC20(
        address _token, 
        uint104 _amount, 
        bytes32 _zkLinkAddress, 
        uint8 _subAccountId, 
        bool _mapping
    ) external  {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint16 tokenId = tokenIds[_token];
        require(tokenId != 0, "Token not registered");
        
        emit DepositERC20(_token, _amount, _zkLinkAddress, _subAccountId, _mapping);
    }
    
    function tokens(uint16 _tokenId) external view  returns (
        bool registered,
        bool paused,
        address tokenAddress,
        uint8 decimals
    ) {
        TokenInfo memory info = tokenInfos[_tokenId];
        return (info.registered, info.paused, info.tokenAddress, info.decimals);
    }
    
    function withdrawPendingBalance(
        address _owner,
        uint16 _tokenId,
        uint128 _amount
    ) external  {
        console.log("withdraw pending balance ");

        require(pendingBalances[_owner][_tokenId] >= _amount, "Insufficient pending balance");
        
        pendingBalances[_owner][_tokenId] -= _amount;
        
        TokenInfo memory tokenInfo = tokenInfos[_tokenId];
        IERC20(tokenInfo.tokenAddress).safeTransfer(_owner, _amount);
        
        emit WithdrawToken(_owner, _tokenId, _amount);
    }
    
    function getPendingBalance(address _address, uint16 _tokenId) external view  returns (uint128) {
        return pendingBalances[_address][_tokenId];
    }

    // Function to simulate pending balances for testing
    function mockPendingBalance(address _owner, uint16 _tokenId, uint128 _amount) external {
        pendingBalances[_owner][_tokenId] = _amount;
        
        // Transfer tokens to this contract to simulate the balance
        TokenInfo memory tokenInfo = tokenInfos[_tokenId];
        if (tokenInfo.tokenAddress != address(0)) {
            IERC20(tokenInfo.tokenAddress).transferFrom(msg.sender, address(this), _amount);
        }
    }
}