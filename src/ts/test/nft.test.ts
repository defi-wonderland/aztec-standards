import {
  setupTestSuite,
  deployNFTWithMinter,
  assertOwnsPrivateNFT,
  assertOwnsPublicNFT,
  initializeTransferCommitmentNFT,
} from './utils.js';

import { Fr } from '@aztec/aztec.js/fields';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type EmbeddedWallet } from '@aztec/wallets/embedded';
import { ContractDeployer } from '@aztec/aztec.js/deployment';
import { getContractInstanceFromInstantiationParams } from '@aztec/aztec.js/contracts';
import {
  ContractFunctionInteractionCallIntent,
  SetPublicAuthwitContractInteraction,
  lookupValidity,
} from '@aztec/aztec.js/authorization';

import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';

import { NFTContract, NFTContractArtifact } from '../../../src/artifacts/NFT.js';

const TEST_TIMEOUT = 300_000;

describe('NFT', () => {
  let cleanup: () => Promise<void>;
  let wallet: EmbeddedWallet;
  let accounts: AztecAddress[];

  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  let nft: NFTContract;

  beforeAll(async () => {
    ({ cleanup, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    nft = (await deployNFTWithMinter(wallet, alice)) as NFTContract;
  });

  afterAll(async () => {
    await cleanup();
  });

  it(
    'deploys the contract with minter',
    async () => {
      const salt = Fr.random();
      const deployerWallet = alice; // using first account as deployer

      const deploymentData = await getContractInstanceFromInstantiationParams(NFTContractArtifact, {
        constructorArtifact: 'constructor_with_minter',
        constructorArgs: ['TestNFT', 'TNFT', deployerWallet, deployerWallet],
        salt,
        deployer: deployerWallet,
      });

      const deployer = new ContractDeployer(NFTContractArtifact, wallet, undefined, 'constructor_with_minter');

      const contract = await deployer
        .deploy('TestNFT', 'TNFT', deployerWallet, deployerWallet)
        .send({ contractAddressSalt: salt, from: deployerWallet });

      const contractMetadata = await wallet.getContractMetadata(deploymentData.address);
      expect(contractMetadata).toBeDefined();
      expect(contractMetadata.isContractPublished).toBeTruthy();

      expect(contract.address).toEqual(deploymentData.address);
    },
    TEST_TIMEOUT,
  );

  // --- Transfer tests: private to commitment ---

  it(
    'transfers NFT from private to commitment and completes transfer',
    async () => {
      const tokenId = 1n;

      // First mint NFT privately to alice
      await nft.methods.mint_to_private(alice, tokenId).send({ from: alice });

      // Verify alice owns the NFT privately
      await assertOwnsPrivateNFT(nft, tokenId, alice, true);

      // We create a new account manager for bob and override the address for this test
      const bobAccountManager = await wallet.createSchnorrAccount(Fr.random(), Fr.random());
      const bob = bobAccountManager.address;

      // Generate the commitment
      const commitment = await initializeTransferCommitmentNFT(nft, alice, bobAccountManager, alice);

      // Alice transfers NFT to the commitment
      await nft.methods.transfer_private_to_commitment(alice, tokenId, commitment, 0n).send({ from: alice });

      // Verify alice no longer owns the NFT
      await assertOwnsPrivateNFT(nft, tokenId, alice, false);

      // Verify bob now owns the NFT privately
      await assertOwnsPrivateNFT(nft, tokenId, bob, true);
    },
    TEST_TIMEOUT,
  );

  // Skipped: requires `additionalScopes` (not yet available) so bob's PXE can
  // discover alice's private notes when bob submits the tx.
  it.skip(
    'transfers NFT from private to public with authorization',
    async () => {
      const tokenId = 1n;

      // First mint NFT privately to alice
      await nft.methods.mint_to_private(alice, tokenId).send({ from: alice });

      // Create transfer call interface with non-zero nonce
      const transferCallInterface = nft.methods.transfer_private_to_public(alice, bob, tokenId, 1n);

      // Add authorization witness from alice to bob
      const intent: ContractFunctionInteractionCallIntent = {
        caller: bob,
        action: transferCallInterface,
      };
      const witness = await wallet.createAuthWit(alice, intent);

      // Bob executes the transfer with alice's authorization
      await transferCallInterface.send({ from: bob, authWitnesses: [witness] });

      // Verify alice no longer owns the NFT privately
      await assertOwnsPrivateNFT(nft, tokenId, alice, false);

      // Verify bob now owns the NFT publicly
      await assertOwnsPublicNFT(nft, tokenId, bob, true);
    },
    TEST_TIMEOUT,
  );

  // --- Transfer tests: private to public with commitment ---

  // Skipped: requires `additionalScopes` (not yet available) so bob's PXE can
  // discover alice's private notes when bob submits the tx.
  it.skip(
    'transfers NFT from private to public with commitment and authorization',
    async () => {
      const tokenId = 1n;

      // First mint NFT privately to alice
      await nft.methods.mint_to_private(alice, tokenId).send({ from: alice });

      // Create transfer call interface with non-zero nonce
      const transferCallInterface = nft.methods.transfer_private_to_public_with_commitment(alice, bob, tokenId, 1n);

      // Add authorization witness from alice to bob
      const intent: ContractFunctionInteractionCallIntent = {
        caller: bob,
        action: transferCallInterface,
      };
      const witness = await wallet.createAuthWit(alice, intent);

      // Bob executes the transfer with alice's authorization
      await transferCallInterface.send({ from: bob, authWitnesses: [witness] });

      // Verify alice no longer owns the NFT privately
      await assertOwnsPrivateNFT(nft, tokenId, alice, false);

      // Verify bob now owns the NFT publicly
      await assertOwnsPublicNFT(nft, tokenId, bob, true);
    },
    TEST_TIMEOUT,
  );

  // --- Transfer tests: public to private ---

  it(
    'transfers NFT from public to private with authorization',
    async () => {
      const tokenId = 1n;

      // First mint NFT publicly to alice
      await nft.methods.mint_to_public(alice, tokenId).send({ from: alice });

      // Create transfer call interface with non-zero nonce
      const transferCallInterface = nft.methods.transfer_public_to_private(alice, bob, tokenId, 1n);

      // Add authorization witness from alice to bob
      const intent: ContractFunctionInteractionCallIntent = {
        caller: bob,
        action: transferCallInterface,
      };
      const witness = await wallet.createAuthWit(alice, intent);

      // Bob executes the transfer with alice's authorization
      await transferCallInterface.send({ from: bob, authWitnesses: [witness] });

      // Verify alice no longer owns the NFT publicly
      await assertOwnsPublicNFT(nft, tokenId, alice, false);

      // Verify bob now owns the NFT privately
      await assertOwnsPrivateNFT(nft, tokenId, bob, true);
    },
    TEST_TIMEOUT,
  );

  // --- Transfer tests: public to public ---

  it(
    'transfers NFT from public to public with authorization',
    async () => {
      const tokenId = 1n;

      // First mint NFT publicly to alice
      await nft.methods.mint_to_public(alice, tokenId).send({ from: alice });

      // Verify initial ownership
      await assertOwnsPublicNFT(nft, tokenId, alice, true);

      // Create transfer call interface with non-zero nonce
      const action = nft.methods.transfer_public_to_public(alice, bob, tokenId, 1n);

      // Add authorization witness from alice to bob
      const intent: ContractFunctionInteractionCallIntent = {
        caller: bob,
        action,
      };
      const witness = await wallet.createAuthWit(alice, intent);

      // alice authorizes the public authwit
      const setPublicAuthwitInteraction = await SetPublicAuthwitContractInteraction.create(wallet, alice, intent, true);

      await setPublicAuthwitInteraction.send({ from: alice });

      const validity = await lookupValidity(wallet, alice, intent, witness);
      expect(validity.isValidInPrivate).toBeTruthy();
      expect(validity.isValidInPublic).toBeTruthy();

      // Bob executes the transfer with alice's authorization
      await action.send({ from: bob, authWitnesses: [witness] });

      // Verify final ownership
      await assertOwnsPublicNFT(nft, tokenId, bob, true);
    },
    TEST_TIMEOUT,
  );

  // --- Access control tests ---

  it(
    'enforces authorization for transfers',
    async () => {
      const tokenId = 1n;
      const invalidNonce = 999n;

      // Mint NFT to alice
      await nft.methods.mint_to_public(alice, tokenId).send({ from: alice });

      // Bob attempts transfer with invalid authorization
      const transferCallInterface = nft.methods.transfer_public_to_public(alice, bob, tokenId, invalidNonce);

      const intent: ContractFunctionInteractionCallIntent = {
        caller: bob,
        action: transferCallInterface,
      };

      // Create auth witness with wrong nonce
      const witness = await wallet.createAuthWit(carl, intent); // Wrong signer (carl instead of alice)

      // Transfer should fail with invalid authorization
      await expect(transferCallInterface.send({ from: bob, authWitnesses: [witness] })).rejects.toThrow();

      // Alice still owns the NFT
      await assertOwnsPublicNFT(nft, tokenId, alice, true);
    },
    TEST_TIMEOUT,
  );
});
