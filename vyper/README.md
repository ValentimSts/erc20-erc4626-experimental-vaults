# ERC20/ERC4626 Experimental Vaults - Vyper Implementation

This directory contains Vyper implementations of the OrangeToken, OrangeFeeVault, and OrangeStrategicVault contracts.

## Contracts

### OrangeToken.vy
An ERC20 token with mint and burn capabilities.
- Standard ERC20 functionality (transfer, approve, transferFrom)
- Owner-only minting
- Public burn and burnFrom functions
- Ownership management (transfer, renounce)

### OrangeFeeVault.vy
An ERC4626-compliant vault with custom fee mechanics.

**Fee Structure:**
- **Deposit Fee**: Percentage fee charged when depositing assets (default: 1%)
- **Withdrawal Fee**: Percentage fee charged when withdrawing assets (default: 0.5%)
- **Management Fee**: Annual fee charged on total assets under management (default: 2%)
- **Performance Fee**: Fee charged on profits above a high-water mark (default: 10%)

**Features:**
- All fees expressed in basis points (BPS) for fine granularity
- Gas-optimized storage layout
- Minimum collection interval to prevent excessive fee collection
- High-water mark tracking for performance fees
- Transparent fee collection mechanism

### OrangeStrategicVault.vy
An advanced ERC4626 vault extending OrangeFeeVault functionality.

**Additional Features:**
- Deposit caps (total and per-user)
- Whitelist functionality for controlled access
- Emergency mode with withdrawal protection
- Simulated yield generation (for learning/testing purposes)
- Comprehensive view functions for vault status

## Installation

```bash
npm install
```

## Compilation

```bash
npx hardhat compile
```

## Testing

```bash
npx hardhat test
```

## Gas Optimizations

The Vyper contracts include several gas optimizations:

1. **Storage Layout**: Variables are ordered to minimize storage slots
2. **Caching**: Storage reads are cached in memory variables
3. **Early Returns**: Functions return early when conditions aren't met
4. **Minimal External Calls**: External calls are minimized where possible
5. **BPS Math**: Basis point calculations avoid floating-point operations

## Fee System (BPS)

All fees use basis points (BPS) for precision:
- 1 BPS = 0.01%
- 100 BPS = 1%
- 10,000 BPS = 100%

Maximum fee is capped at 2,000 BPS (20%) for all fee types.

## License

MIT
