// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {OrangeToken} from "../contracts/OrangeToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract OrangeTokenTest is Test {
    OrangeToken public token;

    address public owner;
    address public user1;
    address public user2;

    uint256 constant MINT_AMOUNT = 1000e18;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        token = new OrangeToken();
    }


    // ============ Deployment Tests ============

    function test_Deployment_CorrectName() public view {
        assertEq(token.name(), "OrangeToken");
    }

    function test_Deployment_CorrectSymbol() public view {
        assertEq(token.symbol(), "ORNG");
    }

    function test_Deployment_ZeroInitialSupply() public view {
        assertEq(token.totalSupply(), 0);
    }

    function test_Deployment_OwnerIsDeployer() public view {
        assertEq(token.owner(), owner);
    }


    // ============ Minting Tests ============

    function test_Mint_OwnerCanMint() public {
        token.mint(user1, MINT_AMOUNT);

        assertEq(token.balanceOf(user1), MINT_AMOUNT);
        assertEq(token.totalSupply(), MINT_AMOUNT);
    }

    function test_Mint_NonOwnerCannotMint() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        token.mint(user1, MINT_AMOUNT);
    }

    function test_Mint_ToMultipleAddresses() public {
        token.mint(user1, MINT_AMOUNT);
        token.mint(user2, MINT_AMOUNT * 2);

        assertEq(token.balanceOf(user1), MINT_AMOUNT);
        assertEq(token.balanceOf(user2), MINT_AMOUNT * 2);
        assertEq(token.totalSupply(), MINT_AMOUNT * 3);
    }

    function test_Mint_EmitsTransferEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), user1, MINT_AMOUNT);

        token.mint(user1, MINT_AMOUNT);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);


    // ============ Burning Tests ============

    function test_Burn_HolderCanBurn() public {
        token.mint(owner, MINT_AMOUNT);

        token.burn(MINT_AMOUNT / 2);

        assertEq(token.balanceOf(owner), MINT_AMOUNT / 2);
        assertEq(token.totalSupply(), MINT_AMOUNT / 2);
    }

    function test_Burn_RevertsIfInsufficientBalance() public {
        token.mint(owner, MINT_AMOUNT);

        vm.expectRevert();
        token.burn(MINT_AMOUNT + 1);
    }

    function test_BurnFrom_WithApproval() public {
        token.mint(user1, MINT_AMOUNT);

        vm.prank(user1);
        token.approve(owner, MINT_AMOUNT);

        token.burnFrom(user1, MINT_AMOUNT / 2);

        assertEq(token.balanceOf(user1), MINT_AMOUNT / 2);
    }

    function test_BurnFrom_RevertsWithoutApproval() public {
        token.mint(user1, MINT_AMOUNT);

        vm.expectRevert();
        token.burnFrom(user1, MINT_AMOUNT / 2);
    }


    // ============ Transfer Tests ============

    function test_Transfer_Success() public {
        token.mint(user1, MINT_AMOUNT);

        vm.prank(user1);
        token.transfer(user2, MINT_AMOUNT / 2);

        assertEq(token.balanceOf(user1), MINT_AMOUNT / 2);
        assertEq(token.balanceOf(user2), MINT_AMOUNT / 2);
    }

    function test_Transfer_RevertsIfInsufficientBalance() public {
        token.mint(user1, MINT_AMOUNT);

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, MINT_AMOUNT + 1);
    }


    // ============ Allowance Tests ============

    function test_Approve_Success() public {
        vm.prank(user1);
        token.approve(user2, MINT_AMOUNT);

        assertEq(token.allowance(user1, user2), MINT_AMOUNT);
    }

    function test_TransferFrom_Success() public {
        token.mint(user1, MINT_AMOUNT);

        vm.prank(user1);
        token.approve(user2, MINT_AMOUNT);

        vm.prank(user2);
        token.transferFrom(user1, user2, MINT_AMOUNT / 2);

        assertEq(token.balanceOf(user1), MINT_AMOUNT / 2);
        assertEq(token.balanceOf(user2), MINT_AMOUNT / 2);
        assertEq(token.allowance(user1, user2), MINT_AMOUNT / 2);
    }


    // ============ Fuzz Tests ============

    function testFuzz_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, type(uint128).max);

        token.mint(to, amount);

        assertEq(token.balanceOf(to), amount);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        token.mint(user1, amount);

        vm.prank(user1);
        token.transfer(user2, amount);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), amount);
    }

    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        token.mint(owner, mintAmount);
        token.burn(burnAmount);

        assertEq(token.balanceOf(owner), mintAmount - burnAmount);
    }
}