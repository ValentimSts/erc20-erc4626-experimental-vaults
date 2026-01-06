import { expect } from "chai";
import hre from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { getAddress, parseEther } from "viem";

describe("OrangeFeeVault", function () {
  const DEPOSIT_FEE = 100n;      // 1%
  const WITHDRAWAL_FEE = 50n;    // 0.5%
  const MANAGEMENT_FEE = 200n;   // 2% annual
  const PERFORMANCE_FEE = 1000n; // 10%
  const BPS = 10000n;

  const INITIAL_MINT = parseEther("1000000");

  async function deployVaultFixture() {
    const [owner, feeRecipient, user1, user2] = await hre.viem.getWalletClients();

    // Deploy OrangeToken
    const token = await hre.viem.deployContract("OrangeToken");

    // Deploy OrangeFeeVault
    const vault = await hre.viem.deployContract("OrangeFeeVault", [
      token.address,
      "Orange Vault",
      "oVAULT",
      feeRecipient.account.address,
      Number(DEPOSIT_FEE),
      Number(WITHDRAWAL_FEE),
      Number(MANAGEMENT_FEE),
      Number(PERFORMANCE_FEE),
    ]);

    const publicClient = await hre.viem.getPublicClient();

    // Mint tokens to users
    await token.write.mint([user1.account.address, INITIAL_MINT]);
    await token.write.mint([user2.account.address, INITIAL_MINT]);

    // Approve vault
    await token.write.approve([vault.address, INITIAL_MINT * 10n], { account: user1.account });
    await token.write.approve([vault.address, INITIAL_MINT * 10n], { account: user2.account });

    return { token, vault, owner, feeRecipient, user1, user2, publicClient };
  }

  // ============ Constructor Tests ============

  describe("Constructor", function () {
    it("Should set correct fee values", async function () {
      const { vault, feeRecipient } = await loadFixture(deployVaultFixture);

      expect(await vault.read.fee_recipient()).to.equal(getAddress(feeRecipient.account.address));
      expect(await vault.read.deposit_fee_bps()).to.equal(Number(DEPOSIT_FEE));
      expect(await vault.read.withdrawal_fee_bps()).to.equal(Number(WITHDRAWAL_FEE));
      expect(await vault.read.management_fee_bps()).to.equal(Number(MANAGEMENT_FEE));
      expect(await vault.read.performance_fee_bps()).to.equal(Number(PERFORMANCE_FEE));
    });

    it("Should revert on zero fee recipient", async function () {
      const { token } = await loadFixture(deployVaultFixture);

      await expect(
        hre.viem.deployContract("OrangeFeeVault", [
          token.address,
          "Test",
          "TST",
          "0x0000000000000000000000000000000000000000",
          Number(DEPOSIT_FEE),
          Number(WITHDRAWAL_FEE),
          Number(MANAGEMENT_FEE),
          Number(PERFORMANCE_FEE),
        ])
      ).to.be.rejectedWith("Zero address");
    });

    it("Should revert on fee too high", async function () {
      const { token, feeRecipient } = await loadFixture(deployVaultFixture);

      await expect(
        hre.viem.deployContract("OrangeFeeVault", [
          token.address,
          "Test",
          "TST",
          feeRecipient.account.address,
          2001, // Too high
          Number(WITHDRAWAL_FEE),
          Number(MANAGEMENT_FEE),
          Number(PERFORMANCE_FEE),
        ])
      ).to.be.rejectedWith("Fee too high");
    });
  });

  // ============ Fee Setter Tests ============

  describe("Fee Setters", function () {
    it("Should set deposit fee", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setDepositFee([200]);
      expect(await vault.read.deposit_fee_bps()).to.equal(200);
    });

    it("Should revert setDepositFee if not owner", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await expect(
        vault.write.setDepositFee([200], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });

    it("Should revert setDepositFee if too high", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await expect(vault.write.setDepositFee([2001])).to.be.rejectedWith("Fee too high");
    });

    it("Should set withdrawal fee", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setWithdrawalFee([100]);
      expect(await vault.read.withdrawal_fee_bps()).to.equal(100);
    });

    it("Should set management fee", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setManagementFee([300]);
      expect(await vault.read.management_fee_bps()).to.equal(300);
    });

    it("Should set performance fee", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setPerformanceFee([1500]);
      expect(await vault.read.performance_fee_bps()).to.equal(1500);
    });

    it("Should set fee recipient", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.setFeeRecipient([user1.account.address]);
      expect(await vault.read.fee_recipient()).to.equal(getAddress(user1.account.address));
    });

    it("Should revert setFeeRecipient on zero address", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await expect(
        vault.write.setFeeRecipient(["0x0000000000000000000000000000000000000000"])
      ).to.be.rejectedWith("Zero address");
    });
  });

  // ============ Deposit Tests ============

  describe("Deposits", function () {
    it("Should deposit successfully", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("10000");
      const expectedFee = depositAmount * DEPOSIT_FEE / BPS;
      const expectedAssetsInVault = depositAmount - expectedFee;

      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares = await vault.read.balanceOf([user1.account.address]);
      expect(shares > 0n).to.be.true;
      expect(await vault.read.totalAssets()).to.equal(expectedAssetsInVault);
    });

    it("Should charge correct deposit fee", async function () {
      const { token, vault, feeRecipient, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("10000");
      const expectedFee = depositAmount * DEPOSIT_FEE / BPS;

      const feeRecipientBalanceBefore = await token.read.balanceOf([feeRecipient.account.address]);

      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const feeRecipientBalanceAfter = await token.read.balanceOf([feeRecipient.account.address]);
      expect(feeRecipientBalanceAfter - feeRecipientBalanceBefore).to.equal(expectedFee);
    });

    it("Should emit DepositFeeCharged event", async function () {
      const { vault, user1, publicClient } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("10000");

      const hash = await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });
      await publicClient.waitForTransactionReceipt({ hash });

      const events = await vault.getEvents.DepositFeeCharged();
      expect(events.length).to.equal(1);
    });

    it("Should preview deposit correctly", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("10000");
      const expectedAssetsAfterFee = depositAmount - (depositAmount * DEPOSIT_FEE / BPS);

      const previewedShares = await vault.read.previewDeposit([depositAmount]);

      // First deposit: 1:1 ratio
      expect(previewedShares).to.equal(expectedAssetsAfterFee);
    });
  });

  // ============ Withdrawal Tests ============

  describe("Withdrawals", function () {
    it("Should withdraw successfully", async function () {
      const { token, vault, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("10000");
      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares = await vault.read.balanceOf([user1.account.address]);
      expect(shares > 0n).to.be.true;
      
      const user1BalanceBefore = await token.read.balanceOf([user1.account.address]);

      await vault.write.redeem([shares, user1.account.address, user1.account.address], { account: user1.account });

      const user1BalanceAfter = await token.read.balanceOf([user1.account.address]);
      expect(user1BalanceAfter > user1BalanceBefore).to.be.true;
      expect(await vault.read.balanceOf([user1.account.address])).to.equal(0n);
    });

    it("Should charge withdrawal fee", async function () {
      const { token, vault, feeRecipient, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("10000");
      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const shares = await vault.read.balanceOf([user1.account.address]);
      const feeRecipientBalanceBefore = await token.read.balanceOf([feeRecipient.account.address]);

      await vault.write.redeem([shares, user1.account.address, user1.account.address], { account: user1.account });

      const feeRecipientBalanceAfter = await token.read.balanceOf([feeRecipient.account.address]);
      // Fee recipient should have received at least the withdrawal fee (plus deposit fee from earlier)
      expect(feeRecipientBalanceAfter > feeRecipientBalanceBefore).to.be.true;
    });

    it("Should preview redeem accounting for fee", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const shares = parseEther("1000");
      const previewedAssets = await vault.read.previewRedeem([shares]);
      const expectedAssets = shares - (shares * WITHDRAWAL_FEE / BPS);

      expect(previewedAssets).to.equal(expectedAssets);
    });
  });

  // ============ Management Fee Tests ============

  describe("Management Fees", function () {
    it("Should collect management fees", async function () {
      const { vault, feeRecipient, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("100000");
      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      // Advance time by 1 year
      await time.increase(365 * 24 * 60 * 60);

      const feeRecipientSharesBefore = await vault.read.balanceOf([feeRecipient.account.address]);

      await vault.write.collectFees();

      const feeRecipientSharesAfter = await vault.read.balanceOf([feeRecipient.account.address]);
      expect(feeRecipientSharesAfter > feeRecipientSharesBefore).to.be.true;
    });

    it("Should skip collection if called too soon", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("100000");
      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      // Wait for min collection interval
      await time.increase(7200);
      await vault.write.collectFees();

      const lastCollection = await vault.read.last_fee_collection();

      // Try to collect again immediately
      await vault.write.collectFees();

      // lastFeeCollection should not change
      expect(await vault.read.last_fee_collection()).to.equal(lastCollection);
    });

    it("Should return pending management fee", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("100000");
      const assetsAfterDepositFee = depositAmount - (depositAmount * DEPOSIT_FEE / BPS);

      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      // Advance time by 1 year
      await time.increase(365 * 24 * 60 * 60);

      const pendingFee = await vault.read.getPendingManagementFee();
      const expectedFee = assetsAfterDepositFee * MANAGEMENT_FEE / BPS;

      // Allow 1% tolerance for timing precision using BigInt comparison
      const lowerBound = expectedFee * 99n / 100n;
      const upperBound = expectedFee * 101n / 100n;
      expect(pendingFee >= lowerBound && pendingFee <= upperBound).to.be.true;
    });
  });

  // ============ Performance Fee Tests ============

  describe("Performance Fees", function () {
    it("Should collect performance fees on profit", async function () {
      const { token, vault, feeRecipient, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("100000");
      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      // Simulate profit by minting tokens directly to vault
      const profit = parseEther("10000");
      await token.write.mint([vault.address, profit]);

      // Wait for min collection interval
      await time.increase(7200);

      const feeRecipientSharesBefore = await vault.read.balanceOf([feeRecipient.account.address]);

      await vault.write.collectFees();

      const feeRecipientSharesAfter = await vault.read.balanceOf([feeRecipient.account.address]);
      expect(feeRecipientSharesAfter > feeRecipientSharesBefore).to.be.true;
    });

    it("Should update high water mark on profit", async function () {
      const { token, vault, user1 } = await loadFixture(deployVaultFixture);

      const depositAmount = parseEther("100000");
      await vault.write.deposit([depositAmount, user1.account.address], { account: user1.account });

      const initialHWM = await vault.read.high_water_mark();

      // Simulate profit
      await token.write.mint([vault.address, parseEther("10000")]);

      // Wait and collect
      await time.increase(7200);
      await vault.write.collectFees();

      const newHWM = await vault.read.high_water_mark();
      expect(newHWM > initialHWM).to.be.true;
    });
  });

  // ============ View Function Tests ============

  describe("View Functions", function () {
    it("Should return fee rates", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const [deposit, withdrawal, management, performance] = await vault.read.getFeeRates();

      expect(deposit).to.equal(DEPOSIT_FEE);
      expect(withdrawal).to.equal(WITHDRAWAL_FEE);
      expect(management).to.equal(MANAGEMENT_FEE);
      expect(performance).to.equal(PERFORMANCE_FEE);
    });

    it("Should return initial share value of 1e18", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const value = await vault.read.shareValue();
      expect(value).to.equal(parseEther("1"));
    });

    it("Should return share value of 1e18 after deposit", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.deposit([parseEther("10000"), user1.account.address], { account: user1.account });

      const value = await vault.read.shareValue();
      expect(value).to.equal(parseEther("1"));
    });

    it("Should increase share value after profit", async function () {
      const { token, vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.deposit([parseEther("10000"), user1.account.address], { account: user1.account });

      // Add profit
      await token.write.mint([vault.address, parseEther("1000")]);

      const value = await vault.read.shareValue();
      expect(value > parseEther("1")).to.be.true;
    });
  });
});
