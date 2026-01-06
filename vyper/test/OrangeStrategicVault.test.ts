import { expect } from "chai";
import hre from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { getAddress, parseEther } from "viem";

describe("OrangeStrategicVault", function () {
  const DEPOSIT_FEE = 50n;       // 0.5%
  const WITHDRAWAL_FEE = 50n;    // 0.5%
  const MANAGEMENT_FEE = 200n;   // 2% annual
  const PERFORMANCE_FEE = 2000n; // 20%
  const BPS = 10000n;

  const INITIAL_MINT = parseEther("1000000");
  const DEFAULT_DEPOSIT_CAP = parseEther("10000000");    // 10M tokens
  const DEFAULT_WITHDRAWAL_CAP = parseEther("1000000");  // 1M tokens per tx

  async function deployVaultFixture() {
    const [owner, feeRecipient, user1, user2, user3] = await hre.viem.getWalletClients();

    // Deploy OrangeToken
    const token = await hre.viem.deployContract("OrangeToken");

    // Deploy OrangeStrategicVault with all 10 constructor params
    const vault = await hre.viem.deployContract("OrangeStrategicVault", [
      token.address,
      "Orange Strategic Vault",
      "osVAULT",
      feeRecipient.account.address,
      Number(DEPOSIT_FEE),
      Number(WITHDRAWAL_FEE),
      Number(MANAGEMENT_FEE),
      Number(PERFORMANCE_FEE),
      DEFAULT_DEPOSIT_CAP,
      DEFAULT_WITHDRAWAL_CAP,
    ]);

    const publicClient = await hre.viem.getPublicClient();

    // Mint tokens to users
    await token.write.mint([user1.account.address, INITIAL_MINT]);
    await token.write.mint([user2.account.address, INITIAL_MINT]);
    await token.write.mint([user3.account.address, INITIAL_MINT]);

    // Approve vault
    await token.write.approve([vault.address, INITIAL_MINT * 10n], { account: user1.account });
    await token.write.approve([vault.address, INITIAL_MINT * 10n], { account: user2.account });
    await token.write.approve([vault.address, INITIAL_MINT * 10n], { account: user3.account });

    return { token, vault, owner, feeRecipient, user1, user2, user3, publicClient };
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

    it("Should set correct caps", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      expect(await vault.read.deposit_cap()).to.equal(DEFAULT_DEPOSIT_CAP);
      expect(await vault.read.withdrawal_cap()).to.equal(DEFAULT_WITHDRAWAL_CAP);
    });

    it("Should set default whitelist and emergency mode", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      expect(await vault.read.whitelist_enabled()).to.equal(false);
      expect(await vault.read.emergency_mode()).to.equal(false);
    });
  });

  // ============ Deposit Cap Tests ============

  describe("Deposit Caps", function () {
    it("Should set deposit cap", async function () {
      const { vault, publicClient } = await loadFixture(deployVaultFixture);

      const newCap = parseEther("500000");

      const hash = await vault.write.setDepositCap([newCap]);
      await publicClient.waitForTransactionReceipt({ hash });

      expect(await vault.read.deposit_cap()).to.equal(newCap);
    });

    it("Should set withdrawal cap", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const newCap = parseEther("100000");
      await vault.write.setWithdrawalCap([newCap]);

      expect(await vault.read.withdrawal_cap()).to.equal(newCap);
    });

    it("Should revert if deposit exceeds cap", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      // Set a smaller cap
      await vault.write.setDepositCap([parseEther("10000")]);

      await expect(
        vault.write.deposit([parseEther("20000"), user1.account.address], { account: user1.account })
      ).to.be.rejectedWith("Deposit cap exceeded");
    });

    it("Should return 0 maxDeposit when cap reached", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      // Set cap to 100k
      const depositCap = parseEther("100000");
      await vault.write.setDepositCap([depositCap]);
      
      // Deposit slightly more than cap (accounting for deposit fee)
      // After 0.5% fee, we need to deposit ~100503 to have ~100000 in vault
      // But we can only deposit up to the cap
      // Let's deposit the cap amount - the fee will make actual deposit less
      await vault.write.deposit([depositCap, user1.account.address], { account: user1.account });

      // After deposit fee (0.5%), vault has ~99500 assets
      // maxDeposit should be cap - current assets = 100000 - 99500 = 500
      const maxDeposit = await vault.read.maxDeposit([user1.account.address]);
      expect(maxDeposit > 0n).to.be.true;
      expect(maxDeposit < parseEther("1000")).to.be.true; // Should be ~500
    });

    it("Should return remaining cap in maxDeposit", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      // Set cap to 100k and deposit 60k
      await vault.write.setDepositCap([parseEther("100000")]);
      await vault.write.deposit([parseEther("60000"), user1.account.address], { account: user1.account });

      // After 0.5% deposit fee: 60000 - 300 = 59700 deposited
      // maxDeposit should be ~40300 (100k - 59700)
      const maxDeposit = await vault.read.maxDeposit([user1.account.address]);
      expect(maxDeposit > parseEther("40000")).to.be.true;
      expect(maxDeposit < parseEther("41000")).to.be.true;
    });
  });

  // ============ Whitelist Tests ============

  describe("Whitelist", function () {
    it("Should enable whitelist", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setWhitelistEnabled([true]);
      expect(await vault.read.whitelist_enabled()).to.equal(true);
    });

    it("Should disable whitelist", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setWhitelistEnabled([true]);
      await vault.write.setWhitelistEnabled([false]);
      expect(await vault.read.whitelist_enabled()).to.equal(false);
    });

    it("Should add to whitelist", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.updateWhitelist([user1.account.address, true]);
      expect(await vault.read.isWhitelisted([user1.account.address])).to.equal(true);
    });

    it("Should remove from whitelist", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.updateWhitelist([user1.account.address, true]);
      await vault.write.updateWhitelist([user1.account.address, false]);
      expect(await vault.read.isWhitelisted([user1.account.address])).to.equal(false);
    });

    it("Should revert deposit if not whitelisted", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.setWhitelistEnabled([true]);

      await expect(
        vault.write.deposit([parseEther("1000"), user1.account.address], { account: user1.account })
      ).to.be.rejectedWith("Not whitelisted");
    });

    it("Should allow deposit if whitelisted", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.setWhitelistEnabled([true]);
      await vault.write.updateWhitelist([user1.account.address, true]);

      await vault.write.deposit([parseEther("1000"), user1.account.address], { account: user1.account });

      const balance = await vault.read.balanceOf([user1.account.address]);
      expect(balance > 0n).to.be.true;
    });

    it("Should return 0 maxDeposit if not whitelisted", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.setWhitelistEnabled([true]);

      const maxDeposit = await vault.read.maxDeposit([user1.account.address]);
      expect(maxDeposit).to.equal(0n);
    });
  });

  // ============ Emergency Mode Tests ============

  describe("Emergency Mode", function () {
    it("Should enable emergency mode", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setEmergencyMode([true]);
      expect(await vault.read.emergency_mode()).to.equal(true);
    });

    it("Should disable emergency mode", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      await vault.write.setEmergencyMode([true]);
      await vault.write.setEmergencyMode([false]);
      expect(await vault.read.emergency_mode()).to.equal(false);
    });

    it("Should revert deposit in emergency mode", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.setEmergencyMode([true]);

      await expect(
        vault.write.deposit([parseEther("1000"), user1.account.address], { account: user1.account })
      ).to.be.rejectedWith("Emergency mode");
    });

    it("Should return 0 maxDeposit in emergency mode", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await vault.write.setEmergencyMode([true]);

      const maxDeposit = await vault.read.maxDeposit([user1.account.address]);
      expect(maxDeposit).to.equal(0n);
    });

    it("Should allow withdraw in emergency mode", async function () {
      const { vault, token, user1 } = await loadFixture(deployVaultFixture);

      // First deposit
      await vault.write.deposit([parseEther("1000"), user1.account.address], { account: user1.account });
      const sharesBefore = await vault.read.balanceOf([user1.account.address]);
      expect(sharesBefore > 0n).to.be.true;

      // Enable emergency and withdraw
      await vault.write.setEmergencyMode([true]);

      const balanceBefore = await token.read.balanceOf([user1.account.address]);
      await vault.write.redeem([sharesBefore, user1.account.address, user1.account.address], { account: user1.account });
      const balanceAfter = await token.read.balanceOf([user1.account.address]);

      expect(balanceAfter > balanceBefore).to.be.true;
    });
  });

  // ============ Yield Simulation Tests ============

  describe("Yield Simulation", function () {
    it("Should simulate yield by direct transfer", async function () {
      const { vault, token, user1 } = await loadFixture(deployVaultFixture);

      // Deposit first
      await vault.write.deposit([parseEther("10000"), user1.account.address], { account: user1.account });

      const totalAssetsBefore = await vault.read.totalAssets();

      // Simulate yield (user mints tokens to vault)
      const yieldAmount = parseEther("1000");
      await token.write.mint([vault.address, yieldAmount]);

      const totalAssetsAfter = await vault.read.totalAssets();
      expect(totalAssetsAfter).to.equal(totalAssetsBefore + yieldAmount);
    });

    it("Should increase share value after yield", async function () {
      const { vault, token, user1 } = await loadFixture(deployVaultFixture);

      // Deposit first
      await vault.write.deposit([parseEther("10000"), user1.account.address], { account: user1.account });

      const shareValueBefore = await vault.read.shareValue();

      // Simulate yield
      await token.write.mint([vault.address, parseEther("1000")]);

      const shareValueAfter = await vault.read.shareValue();
      expect(shareValueAfter > shareValueBefore).to.be.true;
    });
  });

  // ============ View Functions Tests ============

  describe("View Functions", function () {
    it("Should return fee rates", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const [deposit, withdrawal, management, performance] = await vault.read.getFeeRates();

      expect(deposit).to.equal(DEPOSIT_FEE);
      expect(withdrawal).to.equal(WITHDRAWAL_FEE);
      expect(management).to.equal(MANAGEMENT_FEE);
      expect(performance).to.equal(PERFORMANCE_FEE);
    });

    it("Should return strategic params", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const [depositCap, withdrawalCap, whitelistEnabled, emergencyMode] = await vault.read.getStrategicParams();

      expect(depositCap).to.equal(DEFAULT_DEPOSIT_CAP);
      expect(withdrawalCap).to.equal(DEFAULT_WITHDRAWAL_CAP);
      expect(whitelistEnabled).to.equal(false);
      expect(emergencyMode).to.equal(false);
    });

    it("Should return initial share value of 1e18", async function () {
      const { vault } = await loadFixture(deployVaultFixture);

      const value = await vault.read.shareValue();
      expect(value).to.equal(parseEther("1"));
    });
  });

  // ============ Access Control Tests ============

  describe("Access Control", function () {
    it("Should revert if non-owner sets deposit cap", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await expect(
        vault.write.setDepositCap([parseEther("1000")], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });

    it("Should revert if non-owner sets withdrawal cap", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await expect(
        vault.write.setWithdrawalCap([parseEther("1000")], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });

    it("Should revert if non-owner manages whitelist", async function () {
      const { vault, user1, user2 } = await loadFixture(deployVaultFixture);

      await expect(
        vault.write.setWhitelistEnabled([true], { account: user1.account })
      ).to.be.rejectedWith("Only owner");

      await expect(
        vault.write.updateWhitelist([user2.account.address, true], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });

    it("Should revert if non-owner sets emergency mode", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await expect(
        vault.write.setEmergencyMode([true], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });

    it("Should revert if non-owner sets fees", async function () {
      const { vault, user1 } = await loadFixture(deployVaultFixture);

      await expect(
        vault.write.setDepositFee([100], { account: user1.account })
      ).to.be.rejectedWith("Only owner");

      await expect(
        vault.write.setWithdrawalFee([100], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });
  });

  // ============ Integration Tests ============

  describe("Integration", function () {
    it("Should allow multiple users to deposit", async function () {
      const { vault, user1, user2 } = await loadFixture(deployVaultFixture);

      await vault.write.deposit([parseEther("10000"), user1.account.address], { account: user1.account });
      await vault.write.deposit([parseEther("20000"), user2.account.address], { account: user2.account });

      const balance1 = await vault.read.balanceOf([user1.account.address]);
      const balance2 = await vault.read.balanceOf([user2.account.address]);

      expect(balance1 > 0n).to.be.true;
      expect(balance2 > 0n).to.be.true;
    });

    it("Should handle full deposit/withdraw cycle", async function () {
      const { vault, token, user1 } = await loadFixture(deployVaultFixture);

      const initialBalance = await token.read.balanceOf([user1.account.address]);

      // Deposit
      await vault.write.deposit([parseEther("10000"), user1.account.address], { account: user1.account });

      // Withdraw all
      const shares = await vault.read.balanceOf([user1.account.address]);
      await vault.write.redeem([shares, user1.account.address, user1.account.address], { account: user1.account });

      const finalBalance = await token.read.balanceOf([user1.account.address]);

      // Final balance should be less than initial due to fees
      expect(finalBalance < initialBalance).to.be.true;
      // But should have most of it back
      expect(finalBalance > initialBalance * 95n / 100n).to.be.true;
    });

    it("Should work with whitelist enabled then disabled", async function () {
      const { vault, user1, user2 } = await loadFixture(deployVaultFixture);

      // Enable whitelist and add user1 only
      await vault.write.setWhitelistEnabled([true]);
      await vault.write.updateWhitelist([user1.account.address, true]);

      // user1 can deposit
      await vault.write.deposit([parseEther("1000"), user1.account.address], { account: user1.account });

      // user2 cannot deposit
      await expect(
        vault.write.deposit([parseEther("1000"), user2.account.address], { account: user2.account })
      ).to.be.rejectedWith("Not whitelisted");

      // Disable whitelist
      await vault.write.setWhitelistEnabled([false]);

      // Now user2 can deposit
      await vault.write.deposit([parseEther("1000"), user2.account.address], { account: user2.account });
      const balance2 = await vault.read.balanceOf([user2.account.address]);
      expect(balance2 > 0n).to.be.true;
    });
  });
});
