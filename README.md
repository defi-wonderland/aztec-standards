# Aztec Standards

[![npm version](https://img.shields.io/npm/v/@defi-wonderland/aztec-standards.svg)](https://www.npmjs.com/package/@defi-wonderland/aztec-standards)

Aztec Standards is a comprehensive collection of reusable, standardized contracts for the Aztec Network. It provides a robust foundation of token primitives and utilities that support both private and public operations, empowering developers to build innovative privacy-preserving applications with ease.

## Table of Contents
- [Dripper Contract](#dripper-contract)
- [Token Contract](#token-contract)
- [NFT Contract](#nft-contract)
- [Escrow Standard Contract & Library](#escrow-standard-contract--library)
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

## Escrow Standard Contract & Library

The Escrow Standard contains two elements:
- Escrow Contract: a minimal private contract designed to have keys with which authorized callers can spend private balances of tokens and NFTs compliants with AIP-20 and AIP-721, respectively.
- Escrow Library: a set of contract library methods that standardizes and facilitates the management of Escrow contracts from another contract, a.k.a. the Logic contract. 

📖 **[View detailed Escrow documentation](src/escrow_contract/README.md)**

To see examples of Logic contract implementations, such as a linear vesting contract or a clawback escrow contract, go to [aztec-escrow-extensions](https://github.com/defi-wonderland/aztec-escrow-extensions).

## Future Contracts

Additional standardized contracts (e.g., staking, governance, pools) will be added under this repository, with descriptions and function lists.