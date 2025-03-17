// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IApexGateway
 * @dev Minimum interface for interacting with zkLink Gateway
 */
interface IApexGateway {
    /**
     * @notice Deposit ETH to Layer 2
     * @param _zkLinkAddress The receiver Layer 2 address (bytes32)
     * @param _subAccountId The receiver sub account (currently must be 0)
     */
    function depositETH(bytes32 _zkLinkAddress, uint8 _subAccountId) external payable;

    /**
     * @notice Deposit ERC20 token to Layer 2
     * @param _token Token address
     * @param _amount Token amount
     * @param _zkLinkAddress The receiver Layer 2 address
     * @param _subAccountId The receiver sub account (currently must be 0)
     * @param _mapping If true and token has a mapping token, user will receive mapping token at L2
     */
    function depositERC20(
        IERC20 _token, 
        uint104 _amount, 
        bytes32 _zkLinkAddress, 
        uint8 _subAccountId, 
        bool _mapping
    ) external;

    /**
     * @notice Check if a token is registered in zkLink
     * @param _tokenAddress The address of the token
     * @return tokenId The ID of the token in zkLink system
     */
    function tokenIds(address _tokenAddress) external view returns (uint16);

    function tokens(uint16 _tokenId) external view returns (
        bool registered,
        bool paused,
        address tokenAddress,
        uint8 decimals
    );

    /**
     * @notice Withdraw pending balance to the owner
     * @param _owner Address of the owner
     * @param _tokenId mapping of tokenId on this apex gateway
     * @param _amount Amount to withdraw
     */
    function withdrawPendingBalance(
        address _owner,
        uint16  _tokenId,
        uint128 _amount
    ) external;

    /**
     * @notice Returns the pending balance of a token for an address
     * @param _address Owner address
     * @param _tokenId Token ID
     * @return Amount of tokens available to withdraw
     */
    function getPendingBalance(address _address, uint16 _tokenId) external view returns (uint128);

    // Events
    event NewPriorityRequest(
        address sender,
        uint64 serialId,
        uint8 opType,
        bytes pubData,
        uint256 expirationBlock
    );

    event WithdrawalPending(
        uint16 tokenId,
        bytes32 recipient,
        uint128 amount
    );
}