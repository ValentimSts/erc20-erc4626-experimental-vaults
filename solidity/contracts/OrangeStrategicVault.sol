// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OrangeFeeVault} from "./OrangeFeeVault.sol";

/**
 * @title OrangeStrategicVault
 * @dev An advanced ERC4626 vault with yield strategy simulation
 * 
 * This vault extends OrangeFeeVault with:
 * - Simulated yield generation (for learning/testing purposes)
 * - Deposit caps and whitelisting
 * - Emergency withdrawal functionality
 * - Strategy allocation tracking
 * 
 * Note: In production, yield would come from actual DeFi strategies,
 * not manual simulation.
 */
contract OrangeStrategicVault is OrangeFeeVault {
    using Math for uint256;

    /**
     * Storage layout optimized to minimize slots.
     * --------------------------------------------
     * Slot 1:
     *   - maxTotalDeposits  32 bytes
     * 
     * Slot 2:
     *   - maxUserDeposits   32 bytes
     * 
     * Slot 3 (28 bytes unused):
     *   - simulatedYieldBps  2 bytes
     *   - whitelistEnabled   1 byte
     *   - emergencyMode      1 byte
     */

    uint256 public maxTotalDeposits;
    uint256 public maxUserDeposits;

    uint16 public simulatedYieldBps; // Annual yield in basis points
    bool public whitelistEnabled;
    bool public emergencyMode;

    mapping(address => bool) public whitelist;


    error EmergencyModeActive();
    error NotInEmergencyMode();
    error NotWhitelisted();
    error ExceedsTotalCap();
    error ExceedsUserCap();
    error LengthMismatch();
    error YieldSimulationFailed();


    event MaxTotalDepositsUpdated(uint256 oldMax, uint256 newMax);
    event MaxUserDepositsUpdated(uint256 oldMax, uint256 newMax);
    event WhitelistUpdated(address indexed account, bool status);
    event WhitelistToggled(bool enabled);
    event EmergencyModeActivated();
    event EmergencyModeDeactivated();
    event YieldSimulated(uint256 amount);
    event SimulatedYieldRateUpdated(uint256 oldRate, uint256 newRate);

    /**
     * @dev Constructor
     * @param asset_ The underlying asset token
     * @param name_ The name of the vault token
     * @param symbol_ The symbol of the vault token
     * @param feeRecipient_ The address that receives collected fees
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address feeRecipient_
    ) OrangeFeeVault(
        asset_,
        name_,
        symbol_,
        feeRecipient_,
        50,   // 0.5% deposit fee
        50,   // 0.5% withdrawal fee
        200,  // 2% annual management fee
        2000  // 20% performance fee
    ) {
        maxTotalDeposits = type(uint256).max;
        maxUserDeposits = type(uint256).max;
        simulatedYieldBps = 500; // 5% annual yield simulation
    }


    /**
     * @notice Sets the maximum total deposits for the vault
     * @param newMax New maximum total deposits
     */
    function setMaxTotalDeposits(uint256 newMax) external onlyOwner {
        emit MaxTotalDepositsUpdated(maxTotalDeposits, newMax);
        maxTotalDeposits = newMax;
    }

    /**
     * @notice Sets the maximum deposits per user
     * @param newMax New maximum deposits per user
     */
    function setMaxUserDeposits(uint256 newMax) external onlyOwner {
        emit MaxUserDepositsUpdated(maxUserDeposits, newMax);
        maxUserDeposits = newMax;
    }


    /**
     * @notice Toggles the whitelist mode
     * @param enabled Whether whitelist is enabled
     */
    function setWhitelistEnabled(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
        emit WhitelistToggled(enabled);
    }

    /**
     * @notice Adds or removes an address from the whitelist
     * @param account Address to update
     * @param status Whitelist status
     */
    function setWhitelist(address account, bool status) external onlyOwner {
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    /**
     * @notice Batch updates the whitelist
     * @param accounts Addresses to update
     * @param statuses Whitelist statuses
     */
    function setWhitelistBatch(
        address[] calldata accounts,
        bool[] calldata statuses
    ) external onlyOwner {
        uint256 length = accounts.length;
        if (length != statuses.length) revert LengthMismatch();
        
        for (uint256 i; i < length;) {
            whitelist[accounts[i]] = statuses[i];
            emit WhitelistUpdated(accounts[i], statuses[i]);
            unchecked { ++i; }
        }
    }


    /**
     * @notice Activates emergency mode - disables deposits
     */
    function activateEmergency() external onlyOwner {
        emergencyMode = true;
        emit EmergencyModeActivated();
    }

    /**
     * @notice Deactivates emergency mode
     */
    function deactivateEmergency() external onlyOwner {
        emergencyMode = false;
        emit EmergencyModeDeactivated();
    }

    /**
     * @notice Withdraws all assets to owner in emergency
     * @dev Only callable in emergency mode
     */
    function emergencyWithdrawAll() external onlyOwner {
        if (!emergencyMode) revert NotInEmergencyMode();
        
        IERC20 _asset = IERC20(asset());
        uint256 balance = _asset.balanceOf(address(this));
        SafeERC20.safeTransfer(_asset, owner(), balance);
    }


    /**
     * @notice Sets the simulated annual yield rate
     * @param newYieldBps New yield rate in basis points
     */
    function setSimulatedYieldRate(uint16 newYieldBps) external onlyOwner {
        emit SimulatedYieldRateUpdated(simulatedYieldBps, newYieldBps);
        simulatedYieldBps = newYieldBps;
    }

    /**
     * @notice Simulates yield generation by minting tokens to the vault
     * @dev In production, this would be replaced by actual yield strategies
     * @param orangeToken Address of the OrangeToken (for minting)
     */
    function simulateYield(address orangeToken) external onlyOwner {
        uint256 currentAssets = totalAssets();
        uint256 _lastFeeCollection = lastFeeCollection;
        uint256 _simulatedYieldBps = simulatedYieldBps;
        
        if (currentAssets == 0 || block.timestamp <= _lastFeeCollection) return;

        uint256 timeElapsed = block.timestamp - _lastFeeCollection;
        uint256 numerator = _simulatedYieldBps * timeElapsed;
        uint256 denominator = uint256(365 days) * BPS_DENOMINATOR;
        uint256 yieldAmount = currentAssets.mulDiv(numerator, denominator);

        if (yieldAmount != 0) {
            (bool success, ) = orangeToken.call(
                abi.encodeWithSignature("mint(address,uint256)", address(this), yieldAmount)
            );
            if (!success) revert YieldSimulationFailed();
            emit YieldSimulated(yieldAmount);
        }
    }


    /**
     * @notice Returns the maximum deposit amount for a receiver
     * @dev Enforces emergency mode, whitelist, and deposit caps
     */
    function maxDeposit(address receiver) public view virtual override returns (uint256) {
        if (emergencyMode) return 0;
        if (whitelistEnabled && !whitelist[receiver]) return 0;

        uint256 _totalAssets = totalAssets();
        uint256 _maxTotalDeposits = maxTotalDeposits;
        uint256 _maxUserDeposits = maxUserDeposits;

        uint256 totalCap;
        unchecked {
            totalCap = _maxTotalDeposits > _totalAssets 
                ? _maxTotalDeposits - _totalAssets 
                : 0;
        }

        uint256 userBalance = convertToAssets(balanceOf(receiver));
        uint256 userCap;
        unchecked {
            userCap = _maxUserDeposits > userBalance 
                ? _maxUserDeposits - userBalance 
                : 0;
        }

        return totalCap < userCap ? totalCap : userCap;
    }

    /**
     * @notice Returns the maximum mint amount for a receiver
     * @dev Enforces emergency mode, whitelist, and deposit caps
     */
    function maxMint(address receiver) public view virtual override returns (uint256) {
        return _convertToShares(maxDeposit(receiver), Math.Rounding.Floor);
    }

    /**
     * @dev Override _deposit to enforce constraints
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (emergencyMode) revert EmergencyModeActive();
        if (whitelistEnabled && !whitelist[receiver]) revert NotWhitelisted();
        if (totalAssets() + assets > maxTotalDeposits) revert ExceedsTotalCap();
        if (convertToAssets(balanceOf(receiver)) + assets > maxUserDeposits) revert ExceedsUserCap();

        super._deposit(caller, receiver, assets, shares);
    }


    /**
     * @notice Returns the vault configuration
     */
    function getVaultConfig() external view returns (
        uint256 totalCap,
        uint256 userCap,
        bool whitelistOn,
        bool emergency,
        uint256 yieldRate
    ) {
        return (
            maxTotalDeposits,
            maxUserDeposits,
            whitelistEnabled,
            emergencyMode,
            simulatedYieldBps
        );
    }

    /**
     * @notice Checks if an address can deposit
     * @param account Address to check
     * @return canDep Whether the address can deposit
     * @return reason Reason if cannot deposit
     */
    function canDeposit(address account) external view returns (bool canDep, string memory reason) {
        if (emergencyMode) return (false, "Emergency mode active");
        if (whitelistEnabled && !whitelist[account]) return (false, "Not whitelisted");
        if (totalAssets() >= maxTotalDeposits) return (false, "Total deposit cap reached");
        if (convertToAssets(balanceOf(account)) >= maxUserDeposits) return (false, "User deposit cap reached");
        return (true, "");
    }
}
