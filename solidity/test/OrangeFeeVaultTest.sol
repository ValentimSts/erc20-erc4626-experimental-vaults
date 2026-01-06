// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {OrangeFeeVault} from "../contracts/OrangeFeeVault.sol";
import {OrangeToken} from "../contracts/OrangeToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OrangeFeeVaultTest is Test {
    OrangeFeeVault public vault;
    OrangeToken public token;

    address public owner;
    address public feeRecipient;
    address public user1;
    address public user2;

    uint16 constant DEPOSIT_FEE = 100;      // 1%
    uint16 constant WITHDRAWAL_FEE = 50;    // 0.5%
    uint16 constant MANAGEMENT_FEE = 200;   // 2% annual
    uint16 constant PERFORMANCE_FEE = 1000; // 10%
    uint16 constant BPS = 10000;

    uint256 constant INITIAL_MINT = 1_000_000e18;

    function setUp() public {
        // Set a reasonable starting timestamp (Jan 1, 2024)
        vm.warp(1704067200);

        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        token = new OrangeToken();
        vault = new OrangeFeeVault(
            IERC20(address(token)),
            "Orange Vault",
            "oVAULT",
            feeRecipient,
            DEPOSIT_FEE,
            WITHDRAWAL_FEE,
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        );

        // Mint tokens to users
        token.mint(user1, INITIAL_MINT);
        token.mint(user2, INITIAL_MINT);

        // Approve vault
        vm.prank(user1);
        token.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        token.approve(address(vault), type(uint256).max);
    }


    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.depositFeeBps(), DEPOSIT_FEE);
        assertEq(vault.withdrawalFeeBps(), WITHDRAWAL_FEE);
        assertEq(vault.managementFeeBps(), MANAGEMENT_FEE);
        assertEq(vault.performanceFeeBps(), PERFORMANCE_FEE);
        assertEq(vault.owner(), owner);
        assertEq(address(vault.asset()), address(token));
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(OrangeFeeVault.ZeroAddress.selector);
        new OrangeFeeVault(
            IERC20(address(token)),
            "Test",
            "TST",
            address(0),
            DEPOSIT_FEE,
            WITHDRAWAL_FEE,
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        );
    }

    function test_Constructor_RevertsOnFeeTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(OrangeFeeVault.FeeTooHigh.selector, 2001, 2000));
        new OrangeFeeVault(
            IERC20(address(token)),
            "Test",
            "TST",
            feeRecipient,
            2001, // Too high
            WITHDRAWAL_FEE,
            MANAGEMENT_FEE,
            PERFORMANCE_FEE
        );
    }


    // ============ Fee Setter Tests ============

    function test_SetDepositFee_Success() public {
        uint16 newFee = 200;
        
        vm.expectEmit(true, true, true, true);
        emit OrangeFeeVault.DepositFeeUpdated(DEPOSIT_FEE, newFee);
        
        vault.setDepositFee(newFee);
        assertEq(vault.depositFeeBps(), newFee);
    }

    function test_SetDepositFee_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setDepositFee(200);
    }

    function test_SetDepositFee_RevertsIfTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(OrangeFeeVault.FeeTooHigh.selector, 2001, 2000));
        vault.setDepositFee(2001);
    }

    function test_SetWithdrawalFee_Success() public {
        uint16 newFee = 100;
        vault.setWithdrawalFee(newFee);
        assertEq(vault.withdrawalFeeBps(), newFee);
    }

    function test_SetManagementFee_Success() public {
        uint16 newFee = 300;
        vault.setManagementFee(newFee);
        assertEq(vault.managementFeeBps(), newFee);
    }

    function test_SetPerformanceFee_Success() public {
        uint16 newFee = 1500;
        vault.setPerformanceFee(newFee);
        assertEq(vault.performanceFeeBps(), newFee);
    }

    function test_SetFeeRecipient_Success() public {
        address newRecipient = makeAddr("newRecipient");
        
        vm.expectEmit(true, true, true, true);
        emit OrangeFeeVault.FeeRecipientUpdated(feeRecipient, newRecipient);
        
        vault.setFeeRecipient(newRecipient);
        assertEq(vault.feeRecipient(), newRecipient);
    }

    function test_SetFeeRecipient_RevertsOnZeroAddress() public {
        vm.expectRevert(OrangeFeeVault.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
    }


    // ============ Deposit Tests ============

    function test_Deposit_Success() public {
        uint256 depositAmount = 10_000e18;
        uint256 expectedFee = depositAmount * DEPOSIT_FEE / BPS;
        uint256 expectedAssetsInVault = depositAmount - expectedFee;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        assertEq(vault.balanceOf(user1), shares);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(vault.totalAssets(), expectedAssetsInVault);
    }

    function test_Deposit_ChargesCorrectFee() public {
        uint256 depositAmount = 10_000e18;
        uint256 expectedFee = depositAmount * DEPOSIT_FEE / BPS; // 1% = 100e18

        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 feeRecipientBalanceAfter = token.balanceOf(feeRecipient);
        assertEq(feeRecipientBalanceAfter - feeRecipientBalanceBefore, expectedFee);
    }

    function test_Deposit_EmitsDepositFeeCharged() public {
        uint256 depositAmount = 10_000e18;
        uint256 expectedFee = depositAmount * DEPOSIT_FEE / BPS;

        vm.expectEmit(true, true, true, true);
        emit OrangeFeeVault.DepositFeeCharged(user1, expectedFee);

        vm.prank(user1);
        vault.deposit(depositAmount, user1);
    }

    function test_PreviewDeposit_ReturnsCorrectShares() public {
        uint256 depositAmount = 10_000e18;
        uint256 expectedAssetsAfterFee = depositAmount - (depositAmount * DEPOSIT_FEE / BPS);

        uint256 previewedShares = vault.previewDeposit(depositAmount);

        // First deposit: 1:1 ratio
        assertEq(previewedShares, expectedAssetsAfterFee);
    }


    // ============ Withdrawal Tests ============

    function test_Withdraw_Success() public {
        uint256 depositAmount = 10_000e18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 withdrawAmount = 5_000e18;
        uint256 expectedFee = withdrawAmount * WITHDRAWAL_FEE / BPS;
        uint256 expectedReceived = withdrawAmount - expectedFee;

        uint256 user1BalanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        vault.withdraw(withdrawAmount, user1, user1);

        uint256 user1BalanceAfter = token.balanceOf(user1);
        assertEq(user1BalanceAfter - user1BalanceBefore, expectedReceived);
    }

    function test_Withdraw_ChargesCorrectFee() public {
        uint256 depositAmount = 10_000e18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Wait to bypass MIN_COLLECTION_INTERVAL
        vm.warp(block.timestamp + 2 hours);

        uint256 withdrawAmount = 5_000e18;
        uint256 expectedFee = withdrawAmount * WITHDRAWAL_FEE / BPS;

        uint256 feeRecipientBalanceBefore = token.balanceOf(feeRecipient);

        vm.prank(user1);
        vault.withdraw(withdrawAmount, user1, user1);

        uint256 feeRecipientBalanceAfter = token.balanceOf(feeRecipient);
        // Fee recipient gets withdrawal fee (deposit fee was already received)
        assertGe(feeRecipientBalanceAfter - feeRecipientBalanceBefore, expectedFee);
    }

    function test_Redeem_Success() public {
        uint256 depositAmount = 10_000e18;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        vm.warp(block.timestamp + 2 hours);

        uint256 sharesToRedeem = shares / 2;

        vm.prank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(user1), shares - sharesToRedeem);
    }

    function test_PreviewRedeem_AccountsForFee() public view {
        uint256 shares = 1000e18;
        uint256 previewedAssets = vault.previewRedeem(shares);
        uint256 expectedAssets = shares - (shares * WITHDRAWAL_FEE / BPS);

        assertEq(previewedAssets, expectedAssets);
    }


    // ============ Management Fee Tests ============

    function test_CollectFees_ManagementFee() public {
        uint256 depositAmount = 100_000e18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Advance time by 1 year
        vm.warp(vm.getBlockTimestamp() + 365 days);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        vault.collectFees();

        uint256 feeRecipientSharesAfter = vault.balanceOf(feeRecipient);

        // Fee recipient should have received shares
        assertGt(feeRecipientSharesAfter, feeRecipientSharesBefore);
    }

    function test_CollectFees_SkipsIfCalledTooSoon() public {
        uint256 depositAmount = 100_000e18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // First collection after MIN_COLLECTION_INTERVAL
        vm.warp(block.timestamp + 2 hours);
        vault.collectFees();

        uint256 lastCollection = vault.lastFeeCollection();

        // Try to collect again immediately
        vault.collectFees();

        // lastFeeCollection should not change
        assertEq(vault.lastFeeCollection(), lastCollection);
    }

    function test_GetPendingManagementFee() public {
        uint256 depositAmount = 100_000e18;
        uint256 assetsAfterDepositFee = depositAmount - (depositAmount * DEPOSIT_FEE / BPS);

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Advance time by 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 pendingFee = vault.getPendingManagementFee();

        // Expected: 2% of assets
        uint256 expectedFee = assetsAfterDepositFee * MANAGEMENT_FEE / BPS;

        // Allow 1% tolerance for timing precision
        assertApproxEqRel(pendingFee, expectedFee, 0.01e18);
    }


    // ============ Performance Fee Tests ============

    function test_CollectFees_PerformanceFee() public {
        uint256 depositAmount = 100_000e18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Simulate profit by minting tokens directly to vault
        uint256 profit = 10_000e18;
        token.mint(address(vault), profit);

        // Advance time
        vm.warp(block.timestamp + 2 hours);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        vault.collectFees();

        uint256 feeRecipientSharesAfter = vault.balanceOf(feeRecipient);

        // Fee recipient should have received performance fee shares
        assertGt(feeRecipientSharesAfter, feeRecipientSharesBefore);
    }

    function test_HighWaterMark_UpdatesOnProfit() public {
        uint256 depositAmount = 100_000e18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 initialHWM = vault.highWaterMark();

        // Simulate profit
        token.mint(address(vault), 10_000e18);

        vm.warp(block.timestamp + 2 hours);
        vault.collectFees();

        uint256 newHWM = vault.highWaterMark();

        assertGt(newHWM, initialHWM);
    }

    function test_PerformanceFee_NotChargedBelowHWM() public {
        uint256 depositAmount = 100_000e18;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Simulate profit then loss
        token.mint(address(vault), 10_000e18);
        vm.warp(block.timestamp + 2 hours);
        vault.collectFees();

        uint256 hwmAfterProfit = vault.highWaterMark();

        // Simulate loss (withdraw tokens from vault)
        vm.prank(user1);
        vault.withdraw(5_000e18, user1, user1);

        vm.warp(block.timestamp + 2 hours);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        vault.collectFees();

        // HWM should not have changed (no new profit)
        assertEq(vault.highWaterMark(), hwmAfterProfit);

        // Fee recipient should have only received management fees
        uint256 feeRecipientSharesAfter = vault.balanceOf(feeRecipient);
        // Shares increased only from management fee, not performance
        assertGe(feeRecipientSharesAfter, feeRecipientSharesBefore);
    }


    // ============ View Function Tests ============

    function test_GetFeeRates() public view {
        (uint256 deposit, uint256 withdrawal, uint256 management, uint256 performance) = vault.getFeeRates();

        assertEq(deposit, DEPOSIT_FEE);
        assertEq(withdrawal, WITHDRAWAL_FEE);
        assertEq(management, MANAGEMENT_FEE);
        assertEq(performance, PERFORMANCE_FEE);
    }

    function test_ShareValue_InitialValue() public view {
        uint256 value = vault.shareValue();
        assertEq(value, 1e18);
    }

    function test_ShareValue_AfterDeposit() public {
        vm.prank(user1);
        vault.deposit(10_000e18, user1);

        uint256 value = vault.shareValue();
        assertEq(value, 1e18); // 1:1 ratio initially
    }

    function test_ShareValue_AfterProfit() public {
        vm.prank(user1);
        vault.deposit(10_000e18, user1);

        // Add profit
        token.mint(address(vault), 1_000e18);

        uint256 value = vault.shareValue();
        assertGt(value, 1e18);
    }


    // ============ Fuzz Tests ============

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1e18, INITIAL_MINT);

        vm.prank(user1);
        uint256 shares = vault.deposit(amount, user1);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user1), shares);
    }

    function testFuzz_DepositFeeCalculation(uint256 amount) public {
        amount = bound(amount, 1e18, INITIAL_MINT);

        uint256 expectedFee = amount * DEPOSIT_FEE / BPS;

        vm.prank(user1);
        vault.deposit(amount, user1);

        assertEq(token.balanceOf(feeRecipient), expectedFee);
    }

    function testFuzz_SetFees(uint16 depositFee, uint16 withdrawalFee) public {
        depositFee = uint16(bound(depositFee, 0, 2000));
        withdrawalFee = uint16(bound(withdrawalFee, 0, 2000));

        vault.setDepositFee(depositFee);
        vault.setWithdrawalFee(withdrawalFee);

        assertEq(vault.depositFeeBps(), depositFee);
        assertEq(vault.withdrawalFeeBps(), withdrawalFee);
    }
}