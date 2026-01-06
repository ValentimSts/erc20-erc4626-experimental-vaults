// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OrangeToken
 * @dev ERC20 token with mint and burn capabilities.
 */
contract OrangeToken is ERC20, ERC20Burnable, Ownable {
    constructor()
        ERC20("OrangeToken", "ORNG")
        Ownable(msg.sender) {}

    /**
     * @dev Mints `amount` tokens to the specified address.
     * @param to The address to receive the minted tokens.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}