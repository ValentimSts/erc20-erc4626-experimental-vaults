import { expect } from "chai";
import hre from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { getAddress, parseEther } from "viem";

describe("OrangeToken", function () {
  const MINT_AMOUNT = parseEther("1000");

  async function deployTokenFixture() {
    const [owner, user1, user2] = await hre.viem.getWalletClients();

    const token = await hre.viem.deployContract("OrangeToken");
    const publicClient = await hre.viem.getPublicClient();

    return { token, owner, user1, user2, publicClient };
  }

  // ============ Deployment Tests ============

  describe("Deployment", function () {
    it("Should have correct name", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      expect(await token.read.name()).to.equal("OrangeToken");
    });

    it("Should have correct symbol", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      expect(await token.read.symbol()).to.equal("ORNG");
    });

    it("Should have 18 decimals", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      expect(await token.read.decimals()).to.equal(18);
    });

    it("Should have zero initial supply", async function () {
      const { token } = await loadFixture(deployTokenFixture);
      expect(await token.read.totalSupply()).to.equal(0n);
    });

    it("Should set deployer as owner", async function () {
      const { token, owner } = await loadFixture(deployTokenFixture);
      expect(await token.read.owner()).to.equal(getAddress(owner.account.address));
    });
  });

  // ============ Minting Tests ============

  describe("Minting", function () {
    it("Should allow owner to mint", async function () {
      const { token, user1 } = await loadFixture(deployTokenFixture);

      await token.write.mint([user1.account.address, MINT_AMOUNT]);

      expect(await token.read.balanceOf([user1.account.address])).to.equal(MINT_AMOUNT);
      expect(await token.read.totalSupply()).to.equal(MINT_AMOUNT);
    });

    it("Should revert if non-owner tries to mint", async function () {
      const { token, user1 } = await loadFixture(deployTokenFixture);

      await expect(
        token.write.mint([user1.account.address, MINT_AMOUNT], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });

    it("Should mint to multiple addresses", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);

      await token.write.mint([user1.account.address, MINT_AMOUNT]);
      await token.write.mint([user2.account.address, MINT_AMOUNT * 2n]);

      expect(await token.read.balanceOf([user1.account.address])).to.equal(MINT_AMOUNT);
      expect(await token.read.balanceOf([user2.account.address])).to.equal(MINT_AMOUNT * 2n);
      expect(await token.read.totalSupply()).to.equal(MINT_AMOUNT * 3n);
    });

    it("Should emit Transfer event on mint", async function () {
      const { token, user1, publicClient } = await loadFixture(deployTokenFixture);

      const hash = await token.write.mint([user1.account.address, MINT_AMOUNT]);
      await publicClient.waitForTransactionReceipt({ hash });

      const events = await token.getEvents.Transfer();
      expect(events.length).to.equal(1);
      expect(events[0].args.receiver).to.equal(getAddress(user1.account.address));
      expect(events[0].args.amount).to.equal(MINT_AMOUNT);
    });
  });

  // ============ Burning Tests ============

  describe("Burning", function () {
    it("Should allow holder to burn", async function () {
      const { token, owner } = await loadFixture(deployTokenFixture);

      await token.write.mint([owner.account.address, MINT_AMOUNT]);
      await token.write.burn([MINT_AMOUNT / 2n]);

      expect(await token.read.balanceOf([owner.account.address])).to.equal(MINT_AMOUNT / 2n);
      expect(await token.read.totalSupply()).to.equal(MINT_AMOUNT / 2n);
    });

    it("Should revert if insufficient balance", async function () {
      const { token, owner } = await loadFixture(deployTokenFixture);

      await token.write.mint([owner.account.address, MINT_AMOUNT]);

      await expect(token.write.burn([MINT_AMOUNT + 1n])).to.be.rejectedWith("Insufficient balance");
    });

    it("Should allow burnFrom with approval", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);

      await token.write.mint([user1.account.address, MINT_AMOUNT]);
      await token.write.approve([owner.account.address, MINT_AMOUNT], { account: user1.account });
      await token.write.burnFrom([user1.account.address, MINT_AMOUNT / 2n]);

      expect(await token.read.balanceOf([user1.account.address])).to.equal(MINT_AMOUNT / 2n);
    });

    it("Should revert burnFrom without approval", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);

      await token.write.mint([user1.account.address, MINT_AMOUNT]);

      await expect(
        token.write.burnFrom([user1.account.address, MINT_AMOUNT / 2n])
      ).to.be.rejectedWith("Insufficient allowance");
    });
  });

  // ============ Transfer Tests ============

  describe("Transfer", function () {
    it("Should transfer successfully", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);

      await token.write.mint([user1.account.address, MINT_AMOUNT]);
      await token.write.transfer([user2.account.address, MINT_AMOUNT / 2n], { account: user1.account });

      expect(await token.read.balanceOf([user1.account.address])).to.equal(MINT_AMOUNT / 2n);
      expect(await token.read.balanceOf([user2.account.address])).to.equal(MINT_AMOUNT / 2n);
    });

    it("Should revert if insufficient balance", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);

      await token.write.mint([user1.account.address, MINT_AMOUNT]);

      await expect(
        token.write.transfer([user2.account.address, MINT_AMOUNT + 1n], { account: user1.account })
      ).to.be.rejectedWith("Insufficient balance");
    });
  });

  // ============ Allowance Tests ============

  describe("Allowance", function () {
    it("Should approve successfully", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);

      await token.write.approve([user2.account.address, MINT_AMOUNT], { account: user1.account });

      expect(await token.read.allowance([user1.account.address, user2.account.address])).to.equal(MINT_AMOUNT);
    });

    it("Should transferFrom successfully", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);

      await token.write.mint([user1.account.address, MINT_AMOUNT]);
      await token.write.approve([user2.account.address, MINT_AMOUNT], { account: user1.account });
      await token.write.transferFrom(
        [user1.account.address, user2.account.address, MINT_AMOUNT / 2n],
        { account: user2.account }
      );

      expect(await token.read.balanceOf([user1.account.address])).to.equal(MINT_AMOUNT / 2n);
      expect(await token.read.balanceOf([user2.account.address])).to.equal(MINT_AMOUNT / 2n);
      expect(await token.read.allowance([user1.account.address, user2.account.address])).to.equal(MINT_AMOUNT / 2n);
    });
  });

  // ============ Ownership Tests ============

  describe("Ownership", function () {
    it("Should transfer ownership", async function () {
      const { token, owner, user1 } = await loadFixture(deployTokenFixture);

      await token.write.transferOwnership([user1.account.address]);

      expect(await token.read.owner()).to.equal(getAddress(user1.account.address));
    });

    it("Should revert transferOwnership if not owner", async function () {
      const { token, user1, user2 } = await loadFixture(deployTokenFixture);

      await expect(
        token.write.transferOwnership([user2.account.address], { account: user1.account })
      ).to.be.rejectedWith("Only owner");
    });

    it("Should renounce ownership", async function () {
      const { token } = await loadFixture(deployTokenFixture);

      await token.write.renounceOwnership();

      expect(await token.read.owner()).to.equal("0x0000000000000000000000000000000000000000");
    });
  });
});
