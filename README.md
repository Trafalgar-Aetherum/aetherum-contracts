# Aetherum Contracts

ERC-3643 compliance modules for Aetherum's crypto-collateralized lending infrastructure for U.S. credit unions.

## Compliance Modules

### AetherumUSJurisdictionModule

Restricts token transfers to wallets whose on-chain identity claims include a valid U.S. jurisdiction (country code `840`). Ensures only verified U.S. residents participate in credit union lending pools.

### AetherumCollateralLTVModule

Enforces per-borrower maximum Loan-to-Value (LTV) ratios on collateral token positions. Each credit union configures its own LTV ceiling in basis points (default 70%, hard cap 80%). Tracks internal balances to avoid re-entrancy during transfer checks.

### AetherumCUMemberModule

Restricts transfers to verified credit union members. Each compliance contract (one per CU) maintains its own member registry. Only addresses added by the CU agent can send or receive collateral tokens.

## Local Deployment Addresses (Hardhat)

| Module | Proxy Address |
|--------|---------------|
| AetherumUSJurisdictionModule | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| AetherumCollateralLTVModule | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` |
| AetherumCUMemberModule | `0x5FC8d32690cc91D4c39d9d3abcBD16989F875707` |

> These are ephemeral local Hardhat network addresses for development/testing only.

## Setup

```bash
npm install
```

## Compile

```bash
npx hardhat compile
```

## Deploy (local Hardhat network)

```bash
npx hardhat run scripts/deploy.ts
```

## Tech Stack

- Solidity 0.8.17
- Hardhat + TypeScript
- OpenZeppelin Upgradeable Proxies
- ERC-3643 / T-REX modular compliance interface

## License

GPL-3.0
