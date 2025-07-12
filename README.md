# Aztec Standards

Aztec Standards is a comprehensive collection of reusable, standardized contracts for the Aztec Network. It provides a robust foundation of token primitives and utilities that support both private and public operations, empowering developers to build innovative privacy-preserving applications with ease.

## Table of Contents
- [Dripper Contract](#dripper-contract)
- [Token Contract](#token-contract)
- [NFT Contract](#nft-contract)
- [Deployment System](#deployment-system)
- [Future Contracts](#future-contracts)

## Dripper Contract

The `Dripper` contract provides a convenient faucet mechanism for minting tokens into private or public balances. Anyone can easily invoke the functions to request tokens for testing or development purposes.

📖 **[View detailed Dripper documentation](src/dripper/README.md)**

## Token Contract

The `Token` contract implements an ERC-20-like token with Aztec-specific privacy extensions. It supports transfers and interactions explicitly through private balances and public balances, offering full coverage of Aztec's confidentiality features.

We published the [AIP-20 Aztec Token Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737) to the forum. Feel free to review and discuss the specification there.

📖 **[View detailed Token documentation](src/token_contract/README.md)**

## NFT Contract

The `NFT` contract implements an ERC-721-like non-fungible token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public ownership, offering full coverage of Aztec's confidentiality features for unique digital assets.

📖 **[View detailed NFT documentation](src/nft_contract/README.md)**

## Deployment System

This repository includes a robust, automated deployment system for deploying contracts to Aztec testnet with built-in retry functionality to handle testnet instability.

### ✨ Features
- 🔄 **Automatic retries** with exponential backoff for testnet stability
- 🤖 **GitHub Actions integration** for automated deployments on main branch merges
- 📋 **Automatic PR creation** with updated deployment addresses
- ✅ **Address validation** and deployment verification
- 📊 **Detailed deployment summaries** and reporting

### 🚀 Quick Start

```bash
# Install dependencies
yarn install

# Deploy contracts to Aztec testnet
yarn deploy
```

The deployment system automatically:
1. Deploys the Dripper contract
2. Deploys ETH, USDC, and DAI token contracts  
3. Updates `src/deployments.json` with new addresses
4. Creates backup files for safety

### 📖 Documentation

📖 **[View complete deployment documentation](DEPLOYMENT.md)**

## Future Contracts

Additional standardized contracts (e.g., staking, governance, pools) will be added under this repository, with descriptions and function lists.