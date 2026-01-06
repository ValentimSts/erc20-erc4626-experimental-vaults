# ERC20 & ERC4626 Experimental Vaults

ERC4626-compliant tokenized vaults with advanced fee mechanics and strategic features.

## Contracts

- **OrangeToken** - ERC20 token with owner-controlled minting and public burn
- **OrangeFeeVault** - ERC4626 vault with deposit, withdrawal, management, and performance fees
- **OrangeStrategicVault** - Extended vault adding deposit/withdrawal caps, whitelist, and emergency mode

## Implementations

| | Solidity | Vyper |
|---|---|---|
| Path | `solidity/` | `vyper/` |
| Framework | Hardhat | Hardhat + hardhat-vyper |
| Tests | Foundry (Solidity) | TypeScript (viem) |

## Fee System

All fees use basis points (BPS): 1 BPS = 0.01%, 10000 BPS = 100%, max 2000 BPS (20%).
