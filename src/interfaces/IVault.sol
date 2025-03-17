// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../libraries/SigValidationHelpers.sol";
import "./IStrategy.sol";

enum FeeType { WITHDRAW_FEE, PLATFORM_FEE, PERFORMANCE_FEE }

struct Fee {
    FeeType feeType;
    uint256 fee;
    address receiver;
}

interface IVault {
    /**
     * @notice Initializes the vault with initial deposit and strategy
     * @param initialDepositAmount The initial amount deposited by the agent
     * @param strategy The address of the strategy contract
     * @param protocolParams Protocol-specific parameters for the strategy
     */
    function initialize(
        uint256 initialDepositAmount,
        address strategy,
        bytes calldata protocolParams
    ) external;

    /**
     * @notice Returns the underlying token of the vault
     * @return The IERC20 interface of the underlying token
     */
    function UNDERLYING() external view returns (IERC20);

    /**
     * @notice Returns the address of the vault operator
     * @return The operator address
     */
    function operator() external view returns (address);

    /**
     * @notice Returns the address of the vault agent (manager)
     * @return The agent address
     */
    function agent() external view returns (address);

    /**
     * @notice Returns the share token (vault token) of the vault
     * @return The IERC20 interface of the share token
     */
    function xToken() external view returns (IERC20);

    /**
     * @notice Returns the minimum deposit amount allowed
     * @return The minimum deposit amount
     */
    function minDeposit() external view returns (uint256);

    /**
     * @notice Returns the current share rate (price of shares in terms of underlying)
     * @return The share rate normalized to 1e18
     */
    function shareRate() external view returns (uint256);

    /**
     * @notice Returns the maximum deposit amount allowed
     * @return The maximum deposit amount
     */
    function maxDeposit() external view returns (uint256);

    /**
     * @notice Returns the strategy address used by the vault
     * @return The strategy contract address
     */
    function strategy() external view returns (address);

    /**
     * @notice Deposits underlying assets and mints share tokens
     * @param amount The amount of underlying assets to deposit
     * @param receiver The address that will receive the share tokens
     * @return The amount of share tokens minted
     */
    function deposit(uint256 amount, address receiver)
        external
        returns (uint256);
    
    /**
     * @notice Withdraws underlying assets by burning share tokens
     * @dev Requires a valid signature from the backend to authorize the withdrawal
     * @param assets The amount of underlying assets to withdraw
     * @param receiver The address that will receive the assets
     * @param fees Array of fee structures to be applied to the withdrawal
     * @param sig Backend's signature authorizing the withdrawal
     * @return The actual amount of assets withdrawn (after fees)
     */
    function withdraw(uint256 assets, address receiver, Fee[] calldata fees, EIP712Signature calldata sig)
        external
        returns (uint256);

    /**
     * @notice Executes a list of actions with authorization from the backend
     * @param actions List of actions to execute
     * @param sig Backend's signature authorizing the execution
     * @return results Array of bytes containing the results of each action
     */
    function execute(Execution[] calldata actions, EIP712Signature calldata sig) 
        external 
        payable 
        returns (bytes[] memory results);
    
    /**
     * @notice Returns the domain separator for the current chain
     * @return The domain separator used for EIP-712 signatures
     */
    function domainSeparator() external view returns (bytes32);

    /**
     * @notice Returns the total amount of assets deposited into the vault
     * @return The total deposit amount
     */
    function totalDeposit() external view returns (uint256);

    /**
     * @notice Returns the total amount of assets withdrawn from the vault
     * @return The total withdrawal amount
     */
    function totalWithdraw() external view returns (uint256);

    /**
     * @notice Takes a fee from the vault
     * @param fee The amount of fee to take
     * @param receiver The fee receiver
     */
    function takeFee(uint256 fee, address receiver) external;

    /**
     * @notice Initiates an asynchronous withdrawal request
     * @dev Burns shares from the user and creates a pending withdrawal request
     * @param assets The amount of underlying assets to withdraw
     * @param shareOwner The owner of the shares to burn
     * @param withdrawalId The BE withdrawId
     * @param sig User's signature authorizing the withdrawal request
     */
     function requestWithdraw(
        uint256 assets,
        address shareOwner,
        bytes16 withdrawalId,
        EIP712Signature calldata sig) external;
    
    /**
     * @notice Claims assets from a pending withdrawal request
     * @param withdrawalId The identifier of the withdrawal request
     * @param receiver The address that will receive the assets
     * @param fees Array of fee structures to be applied to the claim
     * @param sig Backend's signature authorizing the claim
     * @return The actual amount of assets claimed (after fees)
     */
    function claim(bytes16 withdrawalId, address intermediateWallet,address receiver, Fee[] calldata fees, EIP712Signature calldata sig)
        external
        returns (uint256);

    // Events
    /**
     * @notice Emitted when an execution is performed
     * @param executeId The unique identifier of the execution
     */
    event Execute(bytes16 indexed executeId);
    
    /**
     * @notice Emitted when a withdrawal is performed
     * @param withdrawId The unique identifier of the withdrawal
     */
    event Withdraw(bytes16 indexed withdrawId);

    // Event for withdrawal requests
    event WithdrawalRequested(
        bytes16 indexed requestId,
        address indexed owner,
        uint256 assets
    );
    event FeeTaken(address indexed receiver, uint256 amount);
    event WithdrawalClaimed(
        bytes16 indexed requestId,
        address indexed receiver,
        uint256 amount
    );

    // Custom Errors
    error PDefaiInvalidAgentAddress();
    error PDefaiOnlyAgentCanCall();
    error PDefaiDepositExceedsMax();
    error PDefaiZeroShares();
    error PDefaiWithdrawExceedsMax();
    error PDefaiRedeemExceedsMax();
    error PDefaiZeroAssets();
    error PDefaiExecutionFailed();
    error PDefaiInvalidSignature();
    error PDefaiSignatureExpired();
    error PDefaiUsedSig();
    error PDefaiInvalidStrategy();
    error PDefaiNolongerUsed();
}