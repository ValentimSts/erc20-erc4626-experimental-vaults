// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title OrangeFeeVault
 * @dev An ERC4626-compliant vault with custom fee mechanics
 * 
 * Fee Structure:
 * - Deposit Fee: A percentage fee charged when depositing assets
 * - Withdrawal Fee: A percentage fee charged when withdrawing assets
 * - Management Fee: An annual fee charged on total assets under management
 * - Performance Fee: A fee charged on profits above a high-water mark
 * 
 * All fees are sent to a designated fee recipient address.
 */
contract OrangeFeeVault is ERC4626, Ownable {
    using Math for uint256;

    /**
     * Fee rates for the Orange Fee Vault are all
     * expressed in basis points (BPS) to allow 
     * fine granularity.
     * 
     * BP - Basis Point
     * -------------------
     *   1      BP = 0.01%
     *   100    BP = 1%
     *   10,000 BP = 100%
     */

    uint16 public constant MAX_FEE_BPS = 2000; // Max 20% fee
    uint16 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant MIN_COLLECTION_INTERVAL = 1 hours; // Gas optimization

    /**
     * To optimize the storage layout as much as
     * possible, we must choose the most efficient
     * order and types for our state variables.
     * 
     * The following layout is designed to minimize
     * the number of storage slots used.
     * --------------------------------------------
     * Slot 1 (4 bytes unused):
     *   - feeRecipient      20 bytes
     *   - depositFeeBps      2 bytes
     *   - withdrawalFeeBps   2 bytes
     *   - managementFeeBps   2 bytes
     *   - performanceFeeBps  2 bytes
     *        
     * 
     * Slot 2:
     *   - lastFeeCollection 32 bytes
     *
     * Slot 3:
     *   - highWaterMark     32 bytes
     */

    address public feeRecipient;
    
    /**
     * Fee rates are in basis points. The current 
     * defined maximum fee for any category is 2000
     * BPS (20%), which fits within a uint16.
     * 
     * NOTE: if we wanted to support fees above 20%,
     * (up until 100% - 10000 BPS) we would need to
     * use uint32 instead.
     */ 
    uint16 public depositFeeBps;
    uint16 public withdrawalFeeBps;
    uint16 public managementFeeBps;  // Annual fee
    uint16 public performanceFeeBps;
    
    /**
     * Block timestamps fit within uint48 (up to year
     * 8 million). However, to ensure compatibility with
     * future EVM changes, or to avoid potential issues
     * past year 8 million (haha), we use a full uint256.
     * 
     * Better safe than sorry!
     */
    uint256 public lastFeeCollection; // Management fee tracking

    // Performance fee tracking (high-water mark) - needs full precision
    uint256 public highWaterMark;


    error FeeTooHigh(uint256 provided, uint256 maxAllowed);
    error ZeroAddress();


    modifier validFee(uint16 feeBps) {
        if (feeBps > MAX_FEE_BPS) revert FeeTooHigh(feeBps, MAX_FEE_BPS);
        _;
    }

    modifier notZeroAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }


    event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event ManagementFeeUpdated(uint256 oldFee, uint256 newFee);
    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event FeesCollected(address indexed recipient, uint256 managementFee, uint256 performanceFee);
    event DepositFeeCharged(address indexed depositor, uint256 feeAmount);
    event WithdrawalFeeCharged(address indexed withdrawer, uint256 feeAmount);


    /**
     * @dev Constructor
     * @param asset_ The underlying asset token
     * @param name_ The name of the vault token
     * @param symbol_ The symbol of the vault token
     * @param feeRecipient_ The address that receives collected fees
     * @param depositFeeBps_ Deposit fee in basis points
     * @param withdrawalFeeBps_ Withdrawal fee in basis points
     * @param managementFeeBps_ Annual management fee in basis points
     * @param performanceFeeBps_ Performance fee in basis points
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address feeRecipient_,
        uint16 depositFeeBps_,
        uint16 withdrawalFeeBps_,
        uint16 managementFeeBps_,
        uint16 performanceFeeBps_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (depositFeeBps_ > MAX_FEE_BPS) revert FeeTooHigh(depositFeeBps_, MAX_FEE_BPS);
        if (withdrawalFeeBps_ > MAX_FEE_BPS) revert FeeTooHigh(withdrawalFeeBps_, MAX_FEE_BPS);
        if (managementFeeBps_ > MAX_FEE_BPS) revert FeeTooHigh(managementFeeBps_, MAX_FEE_BPS);
        if (performanceFeeBps_ > MAX_FEE_BPS) revert FeeTooHigh(performanceFeeBps_, MAX_FEE_BPS);

        feeRecipient = feeRecipient_;
        depositFeeBps = depositFeeBps_;
        withdrawalFeeBps = withdrawalFeeBps_;
        managementFeeBps = managementFeeBps_;
        performanceFeeBps = performanceFeeBps_;
        lastFeeCollection = block.timestamp;
    }


    /**
     * @notice Sets the deposit fee to a new value
     * @dev Expects the new fee to be valid and in basis points.
     *      Emits a DepositFeeUpdated event
     * @param newFeeBps New deposit fee in basis points
     */
    function setDepositFee(uint16 newFeeBps) external onlyOwner validFee(newFeeBps) {
        emit DepositFeeUpdated(depositFeeBps, newFeeBps);
        depositFeeBps = newFeeBps;
    }

    /**
     * @notice Sets the withdrawal fee to a new value
     * @dev Expects the new fee to be valid and in basis points.
     *      Emits a WithdrawalFeeUpdated event
     * @param newFeeBps New withdrawal fee in basis points
     */
    function setWithdrawalFee(uint16 newFeeBps) external onlyOwner validFee(newFeeBps) {
        emit WithdrawalFeeUpdated(withdrawalFeeBps, newFeeBps);
        withdrawalFeeBps = newFeeBps;
    }

    /**
     * @notice Sets the management fee to a new value
     * @dev Expects the new fee to be valid and in basis points.
     *      Emits a ManagementFeeUpdated event
     * @param newFeeBps New management fee in basis points
     */
    function setManagementFee(uint16 newFeeBps) external onlyOwner validFee(newFeeBps) {
        // Collect pending fees before changing rate
        collectFees();
        emit ManagementFeeUpdated(managementFeeBps, newFeeBps);
        managementFeeBps = newFeeBps;
    }

    /**
     * @notice Sets the performance fee to a new value
     * @dev Expects the new fee to be valid and in basis points.
     *      Emits a PerformanceFeeUpdated event
     * @param newFeeBps New performance fee in basis points
     */
    function setPerformanceFee(uint16 newFeeBps) external onlyOwner validFee(newFeeBps) {
        // Collect pending fees before changing rate
        collectFees();
        emit PerformanceFeeUpdated(performanceFeeBps, newFeeBps);
        performanceFeeBps = newFeeBps;
    }

    /**
     * @notice Sets the fee recipient address to a new value
     * @dev Expects the new address to be non-zero.
     *      Emits a FeeRecipientUpdated event
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner notZeroAddress(newRecipient) {
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }


    /**
     * @notice Collects accrued management and performance fees
     * @dev This function is made public by design to guarantee
     * that fee collection is transparent and doesn't harm users
     * in any way.
     * Fees are collected by minting shares to the fee recipient
     * This maintains the vault's asset balance while diluting
     * other holders.
     * 
     * Gas optimization: skips collection if called within
     * MIN_COLLECTION_INTERVAL of the last collection.
     */
    function collectFees() public {
        uint256 _lastFeeCollection = lastFeeCollection;
        
        // Skip if collected recently (gas optimization for external callers)
        // Guard against underflow and check minimum interval
        if (block.timestamp <= _lastFeeCollection ||
            block.timestamp - _lastFeeCollection < MIN_COLLECTION_INTERVAL) {
            return;
        }

        uint256 currentAssets = totalAssets();
        uint256 totalShares = totalSupply();

        if (totalShares == 0 || currentAssets == 0) {
            lastFeeCollection = block.timestamp;
            return;
        }

        uint256 managementFeeAmount;
        uint256 performanceFeeAmount;

        // Cache storage reads
        uint256 _managementFeeBps = managementFeeBps;
        uint256 _performanceFeeBps = performanceFeeBps;
        uint256 _highWaterMark = highWaterMark;

        // Calculate management fee (pro-rated for time elapsed)
        uint256 timeElapsed = block.timestamp - _lastFeeCollection;
        if (timeElapsed != 0 && _managementFeeBps != 0) {
            // Annual fee pro-rated:
            //   assets * feeBps * timeElapsed / (365 days * BPS_DENOMINATOR)
            uint256 numerator = _managementFeeBps * timeElapsed;
            uint256 denominator = uint256(365 days) * BPS_DENOMINATOR;
            managementFeeAmount = currentAssets.mulDiv(numerator, denominator);
        }

        // Calculate performance fee (on profit above high-water mark)
        uint256 currentShareValue = currentAssets.mulDiv(1e18, totalShares);
        if (currentShareValue > _highWaterMark && _performanceFeeBps != 0) {
            uint256 profit;
            unchecked {
                // This is safe because inside this if block, 
                // currentShareValue is always > _highWaterMark
                profit = (currentShareValue - _highWaterMark).mulDiv(totalShares, 1e18);
            }
            performanceFeeAmount = profit.mulDiv(_performanceFeeBps, BPS_DENOMINATOR);
            highWaterMark = currentShareValue;
        }

        uint256 totalFeeAssets = managementFeeAmount + performanceFeeAmount;

        if (totalFeeAssets != 0) {
            // Convert fee assets to shares and mint to fee recipient
            // This dilutes other holders instead of transferring assets
            uint256 feeShares = _convertToShares(totalFeeAssets, Math.Rounding.Floor);
            if (feeShares != 0) {
                _mint(feeRecipient, feeShares);
                emit FeesCollected(feeRecipient, managementFeeAmount, performanceFeeAmount);
            }
        }

        lastFeeCollection = block.timestamp;
    }


    /**
     * @dev Override to apply deposit fee
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 /* shares */
    ) internal virtual override {
        // Collect pending fees first
        collectFees();

        // Cache storage read
        uint256 _depositFeeBps = depositFeeBps;
        
        // Calculate and deduct deposit fee
        uint256 feeAmount = assets.mulDiv(_depositFeeBps, BPS_DENOMINATOR);
        uint256 assetsAfterFee;
        unchecked {
            assetsAfterFee = assets - feeAmount;
        }

        // Calculate shares directly (without fee recalculation)
        uint256 sharesAfterFee = _convertToShares(assetsAfterFee, Math.Rounding.Floor);

        IERC20 _asset = IERC20(asset());

        // Transfer total assets from caller
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);

        // Transfer fee to recipient
        if (feeAmount != 0) {
            SafeERC20.safeTransfer(_asset, feeRecipient, feeAmount);
            emit DepositFeeCharged(caller, feeAmount);
        }

        // Mint shares based on assets after fee
        _mint(receiver, sharesAfterFee);

        emit Deposit(caller, receiver, assetsAfterFee, sharesAfterFee);
    }

    /**
     * @dev Override to apply withdrawal fee
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        // Collect pending fees first
        collectFees();

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);

        // Cache storage read
        uint256 _withdrawalFeeBps = withdrawalFeeBps;

        // Calculate withdrawal fee
        uint256 feeAmount = assets.mulDiv(_withdrawalFeeBps, BPS_DENOMINATOR);
        uint256 assetsAfterFee;
        unchecked {
            assetsAfterFee = assets - feeAmount;
        }

        IERC20 _asset = IERC20(asset());

        // Transfer fee to recipient
        if (feeAmount != 0) {
            SafeERC20.safeTransfer(_asset, feeRecipient, feeAmount);
            emit WithdrawalFeeCharged(owner, feeAmount);
        }

        // Transfer remaining assets to receiver
        SafeERC20.safeTransfer(_asset, receiver, assetsAfterFee);

        emit Withdraw(caller, receiver, owner, assetsAfterFee, shares);
    }

    /**
     * @notice Preview deposit accounting for fees
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        uint256 feeAmount = assets.mulDiv(depositFeeBps, BPS_DENOMINATOR);
        uint256 assetsAfterFee;
        unchecked {
            assetsAfterFee = assets - feeAmount;
        }
        return _convertToShares(assetsAfterFee, Math.Rounding.Floor);
    }

    /**
     * @notice Preview mint accounting for fees
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Ceil);
        // Need to account for fee: assets / (1 - fee) = assets * BPS / (BPS - feeBps)
        return assets.mulDiv(BPS_DENOMINATOR, BPS_DENOMINATOR - depositFeeBps);
    }

    /**
     * @notice Preview withdraw accounting for fees
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        // Need to account for fee: we need more assets to end up with desired amount
        uint256 assetsBeforeFee = assets.mulDiv(BPS_DENOMINATOR, BPS_DENOMINATOR - withdrawalFeeBps);
        return _convertToShares(assetsBeforeFee, Math.Rounding.Ceil);
    }

    /**
     * @notice Preview redeem accounting for fees
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        uint256 feeAmount = assets.mulDiv(withdrawalFeeBps, BPS_DENOMINATOR);
        unchecked {
            return assets - feeAmount;
        }
    }


    /**
     * @notice Get all fee rates
     */
    function getFeeRates() external view returns (
        uint256 deposit,
        uint256 withdrawal,
        uint256 management,
        uint256 performance
    ) {
        return (depositFeeBps, withdrawalFeeBps, managementFeeBps, performanceFeeBps);
    }

    /**
     * @notice Get pending management fee amount
     */
    function getPendingManagementFee() external view returns (uint256) {
        uint256 currentAssets = totalAssets();
        uint256 _managementFeeBps = managementFeeBps;
        uint256 _lastFeeCollection = lastFeeCollection;
        
        if (block.timestamp <= _lastFeeCollection || _managementFeeBps == 0 || currentAssets == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - _lastFeeCollection;
        uint256 numerator = _managementFeeBps * timeElapsed;
        uint256 denominator = uint256(365 days) * BPS_DENOMINATOR;
        return currentAssets.mulDiv(numerator, denominator);
    }

    /**
     * @notice Get current share value (price per share)
     */
    function shareValue() external view returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) {
            return 1e18;
        }
        return totalAssets().mulDiv(1e18, totalShares);
    }
}