// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "@openzeppelin-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IStrategy.sol";
import "./libraries/Constants.sol";
import "./libraries/SigValidationHelpers.sol";

/**
 * @title Vault
 * @notice Implementation of a vault that uses strategies via delegatecall
 */
contract Vault is
    IVault,
    ERC4626,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardTransientUpgradeable
{
    using SafeERC20 for IERC20;

    // Immutable state variables
    IERC20 public immutable override UNDERLYING;

    // Mutable state variables
    mapping(bytes16 => bool) internal _usedSigs;
    address public override agent;
    address public override operator;
    uint256 public totalDeposit;
    uint256 public totalWithdraw;

    // Strategy configuration
    address public strategy;
    uint256 public minDeposit;
    uint256 public maxDeposit;

    uint8 private immutable _underlyingDecimals;
    bytes protocolParams;

    // Mapping to store pending withdrawal requests
    mapping(bytes16 => WithdrawalRequest) public withdrawalRequests;

    struct WithdrawalRequest {
        address owner;
        uint256 assets;
        bool claimed;
        uint256 timestamp;
    }

    /**
     * @notice Constructor sets the immutable variables
     * @param operator_ The vault operator
     * @param underlying_ The underlying asset
     * @param name_ The name of the vault token
     * @param symbol_ The symbol of the vault token
     * @param mintDeposit_ The minimum deposit
     * @param maxDeposit_ The maximum deposit
     */
    constructor(
        address operator_,
        address underlying_,
        string memory name_,
        string memory symbol_,
        address agent_,
        uint256 mintDeposit_,
        uint256 maxDeposit_
    ) ERC4626(IERC20(underlying_)) ERC20(name_, symbol_) {
        if (agent_ == address(0)) revert PDefaiInvalidAgentAddress();

        agent = agent_;
        UNDERLYING = IERC20(underlying_);
        operator = operator_;
        minDeposit = mintDeposit_;
        maxDeposit = maxDeposit_;

        (bool success, uint8 assetDecimals) = _getAssetDecimals(
            IERC20(underlying_)
        );
        _underlyingDecimals = success ? assetDecimals : 18;
    }

    /**
     * @notice Initialize the vault with the initial deposit and strategy
     * @param initialDepositAmount The initial amount deposited
     * @param strategy_ The address of the strategy contract
     */
    function initialize(
        uint256 initialDepositAmount,
        address strategy_,
        bytes calldata _protocolParams
    ) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuardTransient_init();
        __EIP712_init(name(), "1.0");

        if (strategy_ == address(0)) revert PDefaiInvalidStrategy();
        strategy = strategy_;

        totalDeposit = initialDepositAmount;

        // Mint initial shares to the agent
        uint256 shares = initialDepositAmount * (10 ** _decimalsOffset());
        _mint(agent, shares);

        // Initialize the strategy
        Execution[] memory initActions = IStrategy(strategy)
            .getInitializationActions(initialDepositAmount, _protocolParams);

        protocolParams = _protocolParams;

        _executeActions(initActions);
    }

    /**
     * @notice Access modifier for operator-only functions
     */
    modifier onlyOperator() {
        _onlyOperator();
        _;
    }

    /**
     * @notice Access check for operator-only functions
     */
    function _onlyOperator() internal view {
        require(
            msg.sender == operator || msg.sender == address(this),
            "only operator"
        );
    }

    /**
     * @notice Access modifier for agent-only functions
     */
    modifier onlyAgent() {
        require(msg.sender == agent, "only agent");
        _;
    }

    /**
     * @notice Transfer operator role to a new address
     * @param newOperator The new operator address
     */
    function transferOperator(address newOperator) public onlyOperator {
        operator = newOperator;
    }

    /**
     * @notice Transfer agent role to a new address
     * @param newAgent The new agent address
     */
    function transferAgent(address newAgent) public onlyOperator {
        agent = newAgent;
    }

    /**
     * @notice Set the minimum deposit amount
     * @param amount The new minimum deposit amount
     */
    function setMinDeposit(uint256 amount) external onlyOperator {
        minDeposit = amount;
    }

    /**
     * @notice Set the maximum deposit amount
     * @param amount The new maximum deposit amount
     */
    function setMaxDeposit(uint256 amount) external onlyOperator {
        maxDeposit = amount;
    }

    /**
     * @notice Get the total value of assets in the vault
     * @return The total value of assets
     */
    function totalAssets() public view override returns (uint256) {
        (bool _success, bytes memory _protocolParams) = strategy.staticcall(
            abi.encodeWithSelector(
                IStrategy.composeProtocolParameters.selector,
                address(this),
                protocolParams
            )
        );

        // Extract the actual bytes value from the encoded response
        _protocolParams = _success
            ? abi.decode(_protocolParams, (bytes))
            : protocolParams;

        (bool success, bytes memory result) = strategy.staticcall(
            abi.encodeWithSelector(
                IStrategy.value.selector,
                address(this),
                _protocolParams
            )
        );

        require(success, "Total value calculation failed");
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Deposit assets into the vault
     * @param amount The amount of underlying tokens to deposit
     * @param receiver The address to receive the shares
     * @return The amount of shares minted
     */
    function deposit(
        uint256 amount,
        address receiver
    ) public override(ERC4626, IVault) nonReentrant returns (uint256) {
        if (amount < minDeposit) revert PDefaiDepositExceedsMax();
        if (amount > maxDeposit) revert PDefaiDepositExceedsMax();

        uint256 shares = previewDeposit(amount);
        if (shares == 0) revert PDefaiZeroShares();

        totalDeposit += amount;
        _deposit(_msgSender(), receiver, amount, shares);

        // Execute deposit actions from the strategy
        Execution[] memory depositActions = IStrategy(strategy)
            .getDepositActions(amount, protocolParams);

        _executeActions(depositActions);

        return shares;
    }

    /**
     * @notice Withdraw amount from the vault
     * @param amount The amount of underlying amount to withdraw
     * @param receiver The address to receive the amount
     * @param fees Array of fee structures to be applied to the withdrawal
     * @param sig The signature from the operator
     * @return The amount of amount withdrawn to the receiver
     */
    function withdraw(
        uint256 amount,
        address receiver,
        Fee[] calldata fees,
        EIP712Signature calldata sig
    ) external override nonReentrant returns (uint256) {
        bytes16 usedSig = bytes16(abi.encodePacked(sig.r, sig.s));

        if (_usedSigs[usedSig]) {
            revert PDefaiUsedSig();
        }

        // Burn shares
        uint256 shares = super.previewWithdraw(amount);

        if (shares == 0) revert PDefaiZeroShares();
        if (shares > balanceOf(msg.sender)) revert PDefaiWithdrawExceedsMax();

        _burn(msg.sender, shares);

        // Withdraw the full amount to this contract first
        (bool success, ) = strategy.delegatecall(
            abi.encodeWithSelector(
                IStrategy.withdraw.selector,
                address(this),
                amount,
                protocolParams
            )
        );

        if (!success) {
            revert PDefaiExecutionFailed();
        }

        // Process fees and calculate hashes in a single loop
        uint256 remainingAmount = amount;
        uint256 numberOfFees = fees.length;
        bytes32[] memory feeHashes = new bytes32[](numberOfFees);

        for (uint i = 0; i < numberOfFees; i++) {
            require(fees[i].fee > 0, "Fee must be positive");
            require(fees[i].receiver != address(0), "Invalid fee receiver");
            require(
                fees[i].fee < remainingAmount,
                "Fee exceeds remaining amount"
            );

            // Calculate fee hash
            feeHashes[i] = keccak256(
                abi.encode(fees[i].feeType, fees[i].receiver, fees[i].fee)
            );

            // Transfer fee
            UNDERLYING.safeTransfer(fees[i].receiver, fees[i].fee);

            // Update remaining amount
            remainingAmount -= fees[i].fee;
        }

        // Ensure there's something left for the receiver
        require(remainingAmount > 0, "No amount left after fees");

        // Transfer the remaining amount to the receiver
        UNDERLYING.safeTransfer(receiver, remainingAmount);

        // Update total withdrawal tracking
        totalWithdraw += amount;

        // Verify signature
        unchecked {
            SigValidationHelpers._validateRecoveredAddress(
                SigValidationHelpers._calculateDigest(
                    keccak256(
                        abi.encode(
                            amount,
                            receiver,
                            keccak256(abi.encode(feeHashes)),
                            sig.deadline
                        )
                    ),
                    _domainSeparatorV4()
                ),
                operator,
                sig
            );
        }

        _usedSigs[usedSig] = true;

        emit Withdraw(usedSig);

        return remainingAmount;
    }

    /***** Disable ERC4626 mutable public functions */
    /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256,
        address,
        address
    ) public virtual override returns (uint256) {
        revert PDefaiNolongerUsed();
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256,
        address,
        address
    ) public virtual override returns (uint256) {
        revert PDefaiNolongerUsed();
    }

    /** @dev See {IERC4626-mint}. */
    function mint(uint256, address) public virtual override returns (uint256) {
        revert PDefaiNolongerUsed();
    }

    /****** end overriding no longer used functions ********/

    /**
     * @notice Get the share token (this contract is also the ERC20 token)
     * @return IERC20 interface to this contract
     */
    function xToken() external view override returns (IERC20) {
        return IERC20(address(this));
    }

    /**
     * @notice Get the domain separator for EIP-712 signatures
     * @return The domain separator
     */
    function domainSeparator() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Execute a list of actions with operator approval
     * @param actions The actions to execute
     * @param sig The signature from the operator
     * @return results The results of each action
     */
    function execute(
        Execution[] calldata actions,
        EIP712Signature calldata sig
    ) external payable override nonReentrant returns (bytes[] memory) {
        bytes16 usedSig = bytes16(abi.encodePacked(sig.r, sig.s));

        if (_usedSigs[usedSig]) {
            revert PDefaiUsedSig();
        }

        uint256 length = actions.length;

        // Calculate array hashes for signature verification
        bytes32[] memory targetHashes = new bytes32[](length);
        bytes32[] memory paramHashes = new bytes32[](length);

        bytes[] memory result = new bytes[](length);

        for (uint256 i = 0; i < length; ) {
            bool success;
            (success, result[i]) = actions[i].target.call(actions[i].params);

            if (!success) {
                revert PDefaiExecutionFailed();
            }

            targetHashes[i] = keccak256(abi.encode(actions[i].target));
            paramHashes[i] = keccak256(abi.encode(actions[i].params));

            unchecked {
                ++i;
            }
        }

        // Verify signature
        unchecked {
            SigValidationHelpers._validateRecoveredAddress(
                SigValidationHelpers._calculateDigest(
                    keccak256(
                        abi.encode(
                            address(this),
                            keccak256(abi.encode(targetHashes)),
                            keccak256(abi.encode(paramHashes)),
                            sig.deadline
                        )
                    ),
                    _domainSeparatorV4()
                ),
                operator,
                sig
            );
        }

        _usedSigs[usedSig] = true;
        emit Execute(usedSig);

        return result;
    }

    // Issue: No support native token for now
    function _executeActions(
        Execution[] memory actions
    ) internal returns (bytes[] memory) {
        uint256 length = actions.length;
        bytes[] memory result = new bytes[](length);

        for (uint256 i = 0; i < length; ) {
            bool success;
            (success, result[i]) = actions[i].target.call(actions[i].params);

            if (!success) {
                revert PDefaiExecutionFailed();
            }

            unchecked {
                ++i;
            }
        }

        return result;
    }

    /**
     * @notice Takes a fee from the vault's assets
     * @dev Can only be called by the operator
     * @param fee The amount of fee to take
     * @param receiver The fee receiver
     */
    function takeFee(
        uint256 fee,
        address receiver
    ) external override onlyOperator {
        // Ensure there are enough assets in the vault
        require(fee > 0, "Fee must be greater than zero");

        // Get the current total assets in the vault
        uint256 currentAssets = totalAssets();
        require(currentAssets >= fee, "Insufficient assets for fee");

        // Transfer the fee using the strategy
        (bool success, ) = strategy.delegatecall(
            abi.encodeWithSelector(
                IStrategy.withdraw.selector,
                receiver,
                fee,
                bytes("")
            )
        );

        if (!success) {
            revert PDefaiExecutionFailed();
        }

        // Update total withdrawal tracking
        totalWithdraw += fee;

        emit FeeTaken(receiver, fee);
    }

    /**
     * @notice Initiates an asynchronous withdrawal request
     * @dev Burns shares from the user and creates a pending withdrawal request
     * @param assets The amount of underlying assets to withdraw
     * @param shareOwner The owner of the shares to burn
     * @param withdrawalId The owner of the shares to burn
     * @param sig shareOwner's sig to approve the withdraw amount
     */
    function requestWithdraw(
        uint256 assets,
        address shareOwner,
        bytes16 withdrawalId,
        EIP712Signature calldata sig
    ) external override nonReentrant onlyAgent {
        bytes16 usedSig = bytes16(abi.encodePacked(sig.r, sig.s));

        if (_usedSigs[usedSig]) {
            revert PDefaiUsedSig();
        }

        if (assets == 0) revert PDefaiZeroAssets();

        WithdrawalRequest memory request = withdrawalRequests[withdrawalId];
        if (request.claimed) revert("Already claimed");

        // Calculate shares to burn based on the assets
        uint256 sharesToBurn = super.previewWithdraw(assets);

        if (sharesToBurn == 0) revert PDefaiZeroShares();
        if (sharesToBurn > balanceOf(shareOwner))
            revert PDefaiWithdrawExceedsMax();

        // Verify signature
        unchecked {
            SigValidationHelpers._validateRecoveredAddress(
                SigValidationHelpers._calculateDigest(
                    keccak256(abi.encode(withdrawalId, sig.deadline)),
                    _domainSeparatorV4()
                ),
                shareOwner,
                sig
            );
        }

        // Burn the shares
        _burn(shareOwner, sharesToBurn);

        // Create the withdrawal request
        withdrawalRequests[withdrawalId] = WithdrawalRequest({
            owner: shareOwner,
            assets: assets,
            claimed: false,
            timestamp: block.timestamp
        });

        _usedSigs[usedSig] = true;

        emit WithdrawalRequested(withdrawalId, shareOwner, assets);

    }

    /**
     * @notice Claims assets from a pending withdrawal request
     * @param requestId The identifier of the withdrawal request
     * @param receiver The address that will receive the assets
     * @param intermediateWallet some protocol doesn't support withdraw directly to a wallet
     * @param fees Array of fee structures to be applied to the claim
     * @param sig Backend's signature authorizing the claim
     * @return The actual amount of assets claimed (after fees)
     */
    function claim(
        bytes16 requestId,
        address receiver,
        address intermediateWallet,
        Fee[] calldata fees,
        EIP712Signature calldata sig
    ) external override nonReentrant returns (uint256) {
        bytes16 usedSig = bytes16(abi.encodePacked(sig.r, sig.s));

        if (_usedSigs[usedSig]) {
            revert PDefaiUsedSig();
        }

        // Get and validate the withdrawal request
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.owner == address(0)) revert("Request does not exist");
        if (request.claimed) revert("Already claimed");

        // Mark as claimed immediately to prevent reentrancy
        request.claimed = true;

        uint256 totalAmount = request.assets;

        // Withdraw the full amount to this contract first
        (bool success, ) = strategy.delegatecall(
            abi.encodeWithSelector(
                IStrategy.withdraw.selector,
                intermediateWallet,
                totalAmount,
                protocolParams
            )
        );

        // make sure this wallet had approved to this vault
        UNDERLYING.safeTransferFrom(intermediateWallet, address(this), totalAmount);

        if (!success) {
            revert PDefaiExecutionFailed();
        }

        // Process fees and calculate hashes in a single loop
        uint256 remainingAmount = totalAmount;
        uint256 numberOfFees = fees.length;
        bytes32[] memory feeHashes = new bytes32[](numberOfFees);

        for (uint i = 0; i < numberOfFees; i++) {
            require(fees[i].fee > 0, "Fee must be positive");
            require(fees[i].receiver != address(0), "Invalid fee receiver");
            require(
                fees[i].fee < remainingAmount,
                "Fee exceeds remaining amount"
            );

            // Calculate fee hash
            feeHashes[i] = keccak256(
                abi.encode(fees[i].feeType, fees[i].receiver, fees[i].fee)
            );

            // Transfer fee
            UNDERLYING.safeTransfer(fees[i].receiver, fees[i].fee);

            // Update remaining amount
            remainingAmount -= fees[i].fee;
        }

        // Ensure there's something left for the receiver
        require(remainingAmount > 0, "No amount left after fees");

        // Transfer the remaining amount to the receiver
        UNDERLYING.safeTransfer(receiver, remainingAmount);

        // Update total withdrawal tracking
        totalWithdraw += totalAmount;

        // Verify signature
        unchecked {
            SigValidationHelpers._validateRecoveredAddress(
                SigValidationHelpers._calculateDigest(
                    keccak256(
                        abi.encode(
                            requestId,
                            receiver,
                            intermediateWallet,
                            totalAmount,
                            keccak256(abi.encode(feeHashes)),
                            sig.deadline
                        )
                    ),
                    _domainSeparatorV4()
                ),
                operator,
                sig
            );
        }

        _usedSigs[usedSig] = true;

        emit WithdrawalClaimed(requestId, receiver, remainingAmount);

        return remainingAmount;
    }

    function shareRate() external view returns (uint256) {
        return (totalAssets() * 1e18) / totalSupply();
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function _decimalsOffset() internal view virtual override returns (uint8) {
        return decimals() - _underlyingDecimals;
    }

    function _getAssetDecimals(
        IERC20 asset_
    ) private view returns (bool ok, uint8 assetDecimals) {
        (bool success, bytes memory encodedDecimals) = address(asset_)
            .staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    /**
     * @notice Authorize contract upgrades (UUPS pattern)
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOperator {}
}
