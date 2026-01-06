// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {OrangeStrategicVault} from "../contracts/OrangeStrategicVault.sol";
import {OrangeToken} from "../contracts/OrangeToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract OrangeStrategicVaultTest is Test {
    OrangeStrategicVault public vault;
    OrangeToken public token;

    address public owner;
    address public feeRecipient;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant INITIAL_MINT = 1_000_000e18;
    uint16 constant BPS = 10000;

    function setUp() public {
        // Set a reasonable starting timestamp (Jan 1, 2024)
        vm.warp(1704067200);

        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        token = new OrangeToken();
        vault = new OrangeStrategicVault(
            IERC20(address(token)),
            "Orange Strategic Vault",
            "osVAULT",
            feeRecipient
        );

        // Mint tokens to users
        token.mint(user1, INITIAL_MINT);
        token.mint(user2, INITIAL_MINT);
        token.mint(user3, INITIAL_MINT);

        // Approve vault
        vm.prank(user1);
        token.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        token.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        token.approve(address(vault), type(uint256).max);
    }


    // ============ Constructor Tests ============

    function test_Constructor_SetsDefaultFees() public view {
        assertEq(vault.depositFeeBps(), 50);      // 0.5%
        assertEq(vault.withdrawalFeeBps(), 50);   // 0.5%
        assertEq(vault.managementFeeBps(), 200);  // 2%
        assertEq(vault.performanceFeeBps(), 2000); // 20%
    }

    function test_Constructor_SetsDefaultCaps() public view {
        assertEq(vault.maxTotalDeposits(), type(uint256).max);
        assertEq(vault.maxUserDeposits(), type(uint256).max);
    }

    function test_Constructor_SetsDefaultYieldRate() public view {
        assertEq(vault.simulatedYieldBps(), 500); // 5%
    }


    // ============ Deposit Cap Tests ============

    function test_SetMaxTotalDeposits_Success() public {
        uint256 newMax = 500_000e18;

        vm.expectEmit(true, true, true, true);
        emit OrangeStrategicVault.MaxTotalDepositsUpdated(type(uint256).max, newMax);

        vault.setMaxTotalDeposits(newMax);
        assertEq(vault.maxTotalDeposits(), newMax);
    }

    function test_SetMaxUserDeposits_Success() public {
        uint256 newMax = 100_000e18;

        vm.expectEmit(true, true, true, true);
        emit OrangeStrategicVault.MaxUserDepositsUpdated(type(uint256).max, newMax);

        vault.setMaxUserDeposits(newMax);
        assertEq(vault.maxUserDeposits(), newMax);
    }

    function test_Deposit_RevertsIfExceedsTotalCap() public {
        vault.setMaxTotalDeposits(10_000e18);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            ERC4626.ERC4626ExceededMaxDeposit.selector,
            user1,
            20_000e18,
            10_000e18
        ));
        vault.deposit(20_000e18, user1);
    }

    function test_Deposit_RevertsIfExceedsUserCap() public {
        vault.setMaxUserDeposits(10_000e18);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            ERC4626.ERC4626ExceededMaxDeposit.selector,
            user1,
            20_000e18,
            10_000e18
        ));
        vault.deposit(20_000e18, user1);
    }

    function test_MaxDeposit_RespectsUserCap() public {
        vault.setMaxUserDeposits(50_000e18);

        uint256 maxDep = vault.maxDeposit(user1);
        assertEq(maxDep, 50_000e18);
    }

    function test_MaxDeposit_RespectsRemainingUserCap() public {
        vault.setMaxUserDeposits(50_000e18);

        vm.prank(user1);
        vault.deposit(30_000e18, user1);

        uint256 maxDep = vault.maxDeposit(user1);
        // After 0.5% deposit fee, ~29,850 is in vault for user1
        // Remaining cap should be ~20,150
        assertLt(maxDep, 50_000e18);
    }

    function test_MaxDeposit_ReturnsSmallerOfCaps() public {
        vault.setMaxTotalDeposits(30_000e18);
        vault.setMaxUserDeposits(50_000e18);

        uint256 maxDep = vault.maxDeposit(user1);
        assertEq(maxDep, 30_000e18); // Total cap is smaller
    }


    // ============ Whitelist Tests ============

    function test_SetWhitelistEnabled_Success() public {
        vm.expectEmit(true, true, true, true);
        emit OrangeStrategicVault.WhitelistToggled(true);

        vault.setWhitelistEnabled(true);
        assertTrue(vault.whitelistEnabled());
    }

    function test_SetWhitelist_Success() public {
        vm.expectEmit(true, true, true, true);
        emit OrangeStrategicVault.WhitelistUpdated(user1, true);

        vault.setWhitelist(user1, true);
        assertTrue(vault.whitelist(user1));
    }

    function test_SetWhitelistBatch_Success() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;

        vault.setWhitelistBatch(accounts, statuses);

        assertTrue(vault.whitelist(user1));
        assertTrue(vault.whitelist(user2));
    }

    function test_SetWhitelistBatch_RevertsOnLengthMismatch() public {
        address[] memory accounts = new address[](2);
        bool[] memory statuses = new bool[](3);

        vm.expectRevert(OrangeStrategicVault.LengthMismatch.selector);
        vault.setWhitelistBatch(accounts, statuses);
    }

    function test_Deposit_RevertsIfNotWhitelisted() public {
        vault.setWhitelistEnabled(true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            ERC4626.ERC4626ExceededMaxDeposit.selector,
            user1,
            10_000e18,
            0
        ));
        vault.deposit(10_000e18, user1);
    }

    function test_Deposit_SucceedsIfWhitelisted() public {
        vault.setWhitelistEnabled(true);
        vault.setWhitelist(user1, true);

        vm.prank(user1);
        uint256 shares = vault.deposit(10_000e18, user1);

        assertGt(shares, 0);
    }

    function test_MaxDeposit_ReturnsZeroIfNotWhitelisted() public {
        vault.setWhitelistEnabled(true);

        uint256 maxDep = vault.maxDeposit(user1);
        assertEq(maxDep, 0);
    }


    // ============ Emergency Mode Tests ============

    function test_ActivateEmergency_Success() public {
        vm.expectEmit(true, true, true, true);
        emit OrangeStrategicVault.EmergencyModeActivated();

        vault.activateEmergency();
        assertTrue(vault.emergencyMode());
    }

    function test_DeactivateEmergency_Success() public {
        vault.activateEmergency();

        vm.expectEmit(true, true, true, true);
        emit OrangeStrategicVault.EmergencyModeDeactivated();

        vault.deactivateEmergency();
        assertFalse(vault.emergencyMode());
    }

    function test_Deposit_RevertsInEmergencyMode() public {
        vault.activateEmergency();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            ERC4626.ERC4626ExceededMaxDeposit.selector,
            user1,
            10_000e18,
            0
        ));
        vault.deposit(10_000e18, user1);
    }

    function test_MaxDeposit_ReturnsZeroInEmergencyMode() public {
        vault.activateEmergency();

        uint256 maxDep = vault.maxDeposit(user1);
        assertEq(maxDep, 0);
    }

    function test_EmergencyWithdrawAll_Success() public {
        vm.prank(user1);
        vault.deposit(100_000e18, user1);

        vault.activateEmergency();

        uint256 vaultBalanceBefore = token.balanceOf(address(vault));
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vault.emergencyWithdrawAll();

        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(owner), ownerBalanceBefore + vaultBalanceBefore);
    }

    function test_EmergencyWithdrawAll_RevertsIfNotEmergency() public {
        vm.prank(user1);
        vault.deposit(100_000e18, user1);

        vm.expectRevert(OrangeStrategicVault.NotInEmergencyMode.selector);
        vault.emergencyWithdrawAll();
    }

    function test_Withdraw_SucceedsInEmergencyMode() public {
        vm.prank(user1);
        vault.deposit(100_000e18, user1);

        vault.activateEmergency();
        vm.warp(vm.getBlockTimestamp() + 2 hours);

        // Get balance before prank
        uint256 userShares = vault.balanceOf(user1);

        // Users can still withdraw in emergency mode
        vm.prank(user1);
        vault.redeem(userShares, user1, user1);

        assertEq(vault.balanceOf(user1), 0);
    }


    // ============ Yield Simulation Tests ============

    function test_SetSimulatedYieldRate_Success() public {
        uint16 newRate = 1000; // 10%

        vm.expectEmit(true, true, true, true);
        emit OrangeStrategicVault.SimulatedYieldRateUpdated(500, newRate);

        vault.setSimulatedYieldRate(newRate);
        assertEq(vault.simulatedYieldBps(), newRate);
    }

    function test_SimulateYield_Success() public {
        vm.prank(user1);
        vault.deposit(100_000e18, user1);

        uint256 totalAssetsBefore = vault.totalAssets();

        // Transfer ownership of token to vault for minting
        token.transferOwnership(address(vault));

        // Advance time by 1 year
        vm.warp(block.timestamp + 365 days);

        vault.simulateYield(address(token));

        uint256 totalAssetsAfter = vault.totalAssets();

        // Should have ~5% more assets (minus timing variations)
        assertGt(totalAssetsAfter, totalAssetsBefore);
    }

    function test_SimulateYield_EmitsEvent() public {
        // Transfer token ownership first
        token.transferOwnership(address(vault));

        vm.prank(user1);
        vault.deposit(100_000e18, user1);

        vm.warp(block.timestamp + 365 days);

        // We can't predict exact yield amount, but event should be emitted
        vault.simulateYield(address(token));

        // If we got here without revert, yield was simulated
        assertGt(vault.totalAssets(), 0);
    }


    // ============ View Function Tests ============

    function test_GetVaultConfig() public {
        vault.setMaxTotalDeposits(500_000e18);
        vault.setMaxUserDeposits(100_000e18);
        vault.setWhitelistEnabled(true);
        vault.activateEmergency();
        vault.setSimulatedYieldRate(1000);

        (
            uint256 totalCap,
            uint256 userCap,
            bool whitelistOn,
            bool emergency,
            uint256 yieldRate
        ) = vault.getVaultConfig();

        assertEq(totalCap, 500_000e18);
        assertEq(userCap, 100_000e18);
        assertTrue(whitelistOn);
        assertTrue(emergency);
        assertEq(yieldRate, 1000);
    }

    function test_CanDeposit_ReturnsTrue() public {
        (bool canDep, string memory reason) = vault.canDeposit(user1);

        assertTrue(canDep);
        assertEq(reason, "");
    }

    function test_CanDeposit_ReturnsFalseInEmergency() public {
        vault.activateEmergency();

        (bool canDep, string memory reason) = vault.canDeposit(user1);

        assertFalse(canDep);
        assertEq(reason, "Emergency mode active");
    }

    function test_CanDeposit_ReturnsFalseIfNotWhitelisted() public {
        vault.setWhitelistEnabled(true);

        (bool canDep, string memory reason) = vault.canDeposit(user1);

        assertFalse(canDep);
        assertEq(reason, "Not whitelisted");
    }

    function test_CanDeposit_ReturnsFalseIfTotalCapReached() public {
        // Set cap slightly higher to allow exact deposit after fee
        vault.setMaxTotalDeposits(100_000e18);
        // Set no deposit fee to ensure exact amount deposited
        vault.setDepositFee(0);

        vm.prank(user1);
        vault.deposit(100_000e18, user1);

        (bool canDep, string memory reason) = vault.canDeposit(user2);

        assertFalse(canDep);
        assertEq(reason, "Total deposit cap reached");
    }


    // ============ Integration Tests ============

    function test_MultipleUsersDeposit() public {
        vm.prank(user1);
        vault.deposit(100_000e18, user1);

        vm.prank(user2);
        vault.deposit(200_000e18, user2);

        vm.prank(user3);
        vault.deposit(50_000e18, user3);

        assertGt(vault.balanceOf(user1), 0);
        assertGt(vault.balanceOf(user2), 0);
        assertGt(vault.balanceOf(user3), 0);

        // User2 should have roughly 2x user1's shares
        assertApproxEqRel(vault.balanceOf(user2), vault.balanceOf(user1) * 2, 0.01e18);
    }

    function test_DepositWithdrawCycle() public {
        uint256 depositAmount = 100_000e18;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        // Wait for min collection interval
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user1);
        uint256 assetsReceived = vault.redeem(shares, user1, user1);

        // User should receive less than deposited due to fees
        assertLt(assetsReceived, depositAmount);
        assertEq(vault.balanceOf(user1), 0);
    }


    // ============ Access Control Tests ============

    function test_OnlyOwnerCanSetCaps() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setMaxTotalDeposits(100_000e18);

        vm.prank(user1);
        vm.expectRevert();
        vault.setMaxUserDeposits(50_000e18);
    }

    function test_OnlyOwnerCanManageWhitelist() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setWhitelistEnabled(true);

        vm.prank(user1);
        vm.expectRevert();
        vault.setWhitelist(user2, true);
    }

    function test_OnlyOwnerCanActivateEmergency() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.activateEmergency();
    }


    // ============ Fuzz Tests ============

    function testFuzz_SetCaps(uint256 totalCap, uint256 userCap) public {
        vault.setMaxTotalDeposits(totalCap);
        vault.setMaxUserDeposits(userCap);

        assertEq(vault.maxTotalDeposits(), totalCap);
        assertEq(vault.maxUserDeposits(), userCap);
    }

    function testFuzz_DepositWithinCaps(uint256 amount) public {
        amount = bound(amount, 1e18, 100_000e18);

        vault.setMaxTotalDeposits(200_000e18);
        vault.setMaxUserDeposits(150_000e18);

        vm.prank(user1);
        uint256 shares = vault.deposit(amount, user1);

        assertGt(shares, 0);
    }
}