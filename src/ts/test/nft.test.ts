import { setupTestSuite } from './utils.js';

import { Fr } from '@aztec/aztec.js/fields';
import type { PXE } from '@aztec/pxe/server';
import { TxStatus } from '@aztec/aztec.js/tx';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import type { TestWallet } from '@aztec/test-wallet/server';
import { ContractDeployer } from '@aztec/aztec.js/deployment';
import type { AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import { Contract, DeployOptions } from '@aztec/aztec.js/contracts';
import { getContractInstanceFromInstantiationParams } from '@aztec/aztec.js/contracts';

import { NFTContract, NFTContractArtifact } from '../../../artifacts/NFT.js';
import { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

// Deploy NFT contract with a minter
async function deployNFTWithMinter(wallet: TestWallet, deployer: AztecAddress, options?: DeployOptions) {
  const contract = await Contract.deploy(
    wallet,
    NFTContractArtifact,
    ['TestNFT', 'TNFT', deployer, deployer],
    'constructor_with_minter',
  )
    .send({
      ...options,
      from: deployer,
    })
    .deployed();
  return contract;
}

// Check if an address owns a specific NFT in public state
async function assertOwnsPublicNFT(
  nft: NFTContract,
  tokenId: bigint,
  expectedOwner: AztecAddress,
  caller?: AztecAddress | { getAddress: () => AztecAddress },
) {
  const from = caller ? (caller instanceof AztecAddress ? caller : caller.getAddress()) : expectedOwner;
  const owner = await nft.methods.public_owner_of(tokenId).simulate({ from });
  expect(owner.equals(expectedOwner)).toBe(true);
}

// Check if an address owns a specific NFT in private state
async function assertOwnsPrivateNFT(
  nft: NFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  caller?: AztecAddress | { getAddress: () => AztecAddress },
) {
  const from = caller ? (caller instanceof AztecAddress ? caller : caller.getAddress()) : owner;
  const [nfts, _] = await nft.methods.get_private_nfts(owner, 0).simulate({ from });
  const hasNFT = nfts.some((id: bigint) => id === tokenId);
  expect(hasNFT).toBe(true);
}

// Check if an NFT has been nullified (no longer owned) in private state
async function assertPrivateNFTNullified(
  nft: NFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  caller?: AztecAddress | { getAddress: () => AztecAddress },
) {
  const from = caller ? (caller instanceof AztecAddress ? caller : caller.getAddress()) : owner;
  const [nfts, _] = await nft.methods.get_private_nfts(owner, 0).simulate({ from });
  const hasNFT = nfts.some((id: bigint) => id === tokenId);
  expect(hasNFT).toBe(false);
}

describe('NFT - Single PXE', () => {
  let pxe: PXE;
  let store: AztecLMDBStoreV2;
  let wallet: TestWallet;
  let accounts: AztecAddress[];

  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  let nft: NFTContract;

  beforeAll(async () => {
    ({ pxe, store, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    nft = (await deployNFTWithMinter(wallet, alice)) as NFTContract;
  });

  afterAll(async () => {
    await store.delete();
  });

  it('deploys the contract with minter', async () => {
    const salt = Fr.random();
    const deployerWallet = alice; // using first account as deployer

    const deploymentData = await getContractInstanceFromInstantiationParams(NFTContractArtifact, {
      constructorArtifact: 'constructor_with_minter',
      constructorArgs: ['TestNFT', 'TNFT', deployerWallet, deployerWallet],
      salt,
      deployer: deployerWallet,
    });

    const deployer = new ContractDeployer(NFTContractArtifact, wallet, undefined, 'constructor_with_minter');

    const tx = deployer
      .deploy('TestNFT', 'TNFT', deployerWallet, deployerWallet)
      .send({ contractAddressSalt: salt, from: deployerWallet });

    const receipt = await tx.getReceipt();

    expect(receipt).toEqual(
      expect.objectContaining({
        status: TxStatus.PENDING,
        error: '',
      }),
    );

    const receiptAfterMined = await tx.wait({ wallet });

    const contractMetadata = await pxe.getContractMetadata(deploymentData.address);
    expect(contractMetadata).toBeDefined();
    // TODO: Fix this
    // expect(contractMetadata.isContractPubliclyDeployed).toBeTruthy();
    expect(receiptAfterMined).toEqual(
      expect.objectContaining({
        status: TxStatus.SUCCESS,
      }),
    );

    expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
  }, 300_000);

  // --- Mint tests ---

  it('mints NFT to public', async () => {
    const tokenId = 1n;
    await nft.methods.mint_to_public(bob, tokenId).send({ from: alice }).wait();

    // Verify bob owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob);
  }, 300_000);

  it('mints NFT to private', async () => {
    const tokenId = 1n;
    await nft.methods.mint_to_private(bob, tokenId).send({ from: alice }).wait();

    // Verify bob owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, bob);
  }, 300_000);

  it('fails to mint when caller is not minter', async () => {
    const tokenId = 1n;

    // Bob attempts to mint when he's not the minter
    await expect(nft.methods.mint_to_public(bob, tokenId).send({ from: bob }).wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );

    await expect(nft.methods.mint_to_private(bob, tokenId).send({ from: bob }).wait()).rejects.toThrow(
      /Assertion failed: caller is not minter/,
    );
  }, 300_000);

  it('fails to mint same token ID twice', async () => {
    const tokenId = 1n;

    // First mint succeeds
    await nft.methods.mint_to_public(bob, tokenId).send({ from: alice }).wait();

    // Second mint with same token ID should fail
    await expect(nft.methods.mint_to_public(carl, tokenId).send({ from: alice }).wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );
  }, 300_000);

  it('fails to mint with token ID zero', async () => {
    const tokenId = 0n;

    await expect(nft.methods.mint_to_public(bob, tokenId).send({ from: alice }).wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );

    await expect(nft.methods.mint_to_private(bob, tokenId).send({ from: alice }).wait()).rejects.toThrow(
      /zero token ID not supported/,
    );
  }, 300_000);

  it('can mint multiple NFTs to same owner', async () => {
    const tokenId1 = 1n;
    const tokenId2 = 2n;

    // Mint two NFTs to bob
    await nft.methods.mint_to_private(bob, tokenId1).send({ from: alice }).wait();
    await nft.methods.mint_to_private(bob, tokenId2).send({ from: alice }).wait();

    // Verify bob owns both NFTs
    await assertOwnsPrivateNFT(nft, tokenId1, bob);
    await assertOwnsPrivateNFT(nft, tokenId2, bob);
  }, 300_000);

  // --- Burn tests ---

  it('burns NFT from public balance', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to bob
    await nft.methods.mint_to_public(bob, tokenId).send({ from: alice }).wait();

    // Verify bob owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob);

    // Bob burns his NFT
    await nft.methods.burn_public(bob, tokenId, 0n).send({ from: bob }).wait();

    // Verify the NFT no longer exists
    const owner = await nft.methods.public_owner_of(tokenId).simulate({ from: bob });
    expect(owner.equals(AztecAddress.ZERO)).toBe(true);
  }, 300_000);

  it('burns NFT from private balance', async () => {
    const tokenId = 1n;

    // First mint NFT privately to bob
    await nft.methods.mint_to_private(bob, tokenId).send({ from: alice }).wait();

    // Verify bob owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, bob);

    // Bob burns his NFT
    await nft.methods.burn_private(bob, tokenId, 0n).send({ from: bob }).wait();

    // Verify the NFT is nullified
    await assertPrivateNFTNullified(nft, tokenId, bob);
  }, 300_000);

  it('fails to burn NFT when caller is not owner', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to bob
    await nft.methods.mint_to_public(bob, tokenId).send({ from: alice }).wait();

    // Carl attempts to burn bob's NFT
    await expect(nft.methods.burn_public(carl, tokenId, 0n).send({ from: carl }).wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );

    // First mint NFT privately to bob
    const tokenId2 = 2n;
    await nft.methods.mint_to_private(bob, tokenId2).send({ from: alice }).wait();

    // Carl attempts to burn bob's private NFT
    await expect(nft.methods.burn_private(carl, tokenId2, 0n).send({ from: carl }).wait()).rejects.toThrow(
      /nft not found/,
    );
  }, 300_000);

  it('fails to burn non-existent NFT', async () => {
    const tokenId = 999n;

    // Try to burn non-existent public NFT
    await expect(nft.methods.burn_public(bob, tokenId, 0n).send({ from: bob }).wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );

    // Try to burn non-existent private NFT
    await expect(nft.methods.burn_private(bob, tokenId, 0n).send({ from: bob }).wait()).rejects.toThrow(
      /nft not found/,
    );
  }, 300_000);

  // --- Transfer tests: private to private ---

  it('transfers NFT from private to private', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Verify alice owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, alice);

    // Transfer NFT from alice to bob privately
    await nft.methods.transfer_private_to_private(alice, bob, tokenId, 0n).send({ from: alice }).wait();

    // Verify alice no longer owns the NFT
    await assertPrivateNFTNullified(nft, tokenId, alice);

    // Verify bob now owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, bob);
  }, 300_000);

  it('fails to transfer private NFT when not owner', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Carl attempts to transfer alice's NFT to bob
    await expect(
      nft.methods.transfer_private_to_private(carl, bob, tokenId, 0n).send({ from: carl }).wait(),
    ).rejects.toThrow(/nft not found/);

    // Verify alice still owns the NFT
    await assertOwnsPrivateNFT(nft, tokenId, alice);
  }, 300_000);

  // --- Transfer tests: private to commitment ---

  // TODO: This is failing because the commitment is not stored or accessible
  it.skip('transfers NFT from private to commitment and completes transfer', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Verify alice owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, alice);

    // Bob initializes a transfer commitment for receiving the NFT
    await nft.methods.initialize_transfer_commitment(bob, bob, bob).send({ from: bob }).wait();

    // Get the commitment value through simulation
    const commitment = await nft.methods.initialize_transfer_commitment(alice, bob, bob).simulate({ from: bob });

    // Alice transfers NFT to the commitment
    await nft.methods.transfer_private_to_commitment(alice, tokenId, commitment, 0n).send({ from: alice }).wait();

    // Verify alice no longer owns the NFT
    await assertPrivateNFTNullified(nft, tokenId, alice);

    // Verify bob now owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, bob);
  }, 300_000);

  it('fails to transfer to invalid commitment', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Create an invalid commitment (using wrong sender)
    const invalidCommitment = await nft.methods.initialize_transfer_commitment(carl, bob, bob).simulate({ from: bob });

    // Alice attempts to transfer to invalid commitment
    await expect(
      nft.methods.transfer_private_to_commitment(alice, tokenId, invalidCommitment, 0n).send({ from: alice }).wait(),
    ).rejects.toThrow(/^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/);

    // Verify alice still owns the NFT
    await assertOwnsPrivateNFT(nft, tokenId, alice);
  }, 300_000);

  // --- Transfer tests: private to public ---

  it('transfers NFT from private to public', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Verify alice owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, alice);

    // Transfer NFT from alice to bob publicly
    await nft.methods.transfer_private_to_public(alice, bob, tokenId, 0n).send({ from: alice }).wait();

    // Verify alice no longer owns the NFT privately
    await assertPrivateNFTNullified(nft, tokenId, alice);

    // Verify bob now owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob);
  }, 300_000);

  it('fails to transfer private NFT to public when not owner', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Carl attempts to transfer alice's NFT to bob
    await expect(
      nft.methods.transfer_private_to_public(carl, bob, tokenId, 0n).send({ from: carl }).wait(),
    ).rejects.toThrow(/nft not found/);

    // Verify alice still owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, alice);
  }, 300_000);

  it('transfers NFT from private to public with authorization', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Create transfer call interface with non-zero nonce
    const transferCallInterface = nft.methods.transfer_private_to_public(alice, bob, tokenId, 1n);

    // Add authorization witness from alice to bob
    const intent: ContractFunctionInteractionCallIntent = {
      caller: bob,
      action: transferCallInterface,
    };
    const witness = await wallet.createAuthWit(alice, intent);

    // Bob executes the transfer with alice's authorization
    await transferCallInterface.send({ from: bob, authWitnesses: [witness] }).wait();

    // Verify alice no longer owns the NFT privately
    await assertPrivateNFTNullified(nft, tokenId, alice);

    // Verify bob now owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob);
  }, 300_000);

  // --- Transfer tests: private to public with commitment ---

  it('transfers NFT from private to public with commitment', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Verify alice owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, alice);

    // Transfer NFT from alice to bob with commitment
    await nft.methods.transfer_private_to_public_with_commitment(alice, bob, tokenId, 0n).send({ from: alice }).wait();

    // Verify alice no longer owns the NFT privately
    await assertPrivateNFTNullified(nft, tokenId, alice);

    // Verify bob now owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob);
  }, 300_000);

  it('fails to transfer private NFT to public with commitment when not owner', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Carl attempts to transfer alice's NFT to bob
    await expect(
      nft.methods.transfer_private_to_public_with_commitment(carl, bob, tokenId, 0n).send({ from: carl }).wait(),
    ).rejects.toThrow(/nft not found/);

    // Verify alice still owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, alice);
  }, 300_000);

  it('transfers NFT from private to public with commitment and authorization', async () => {
    const tokenId = 1n;

    // First mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Create transfer call interface with non-zero nonce
    const transferCallInterface = nft.methods.transfer_private_to_public_with_commitment(alice, bob, tokenId, 1n);

    // Add authorization witness from alice to bob
    const intent: ContractFunctionInteractionCallIntent = {
      caller: bob,
      action: transferCallInterface,
    };
    const witness = await wallet.createAuthWit(alice, intent);

    // Bob executes the transfer with alice's authorization
    await transferCallInterface.send({ from: bob, authWitnesses: [witness] }).wait();

    // Verify alice no longer owns the NFT privately
    await assertPrivateNFTNullified(nft, tokenId, alice);

    // Verify bob now owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob);
  }, 300_000);

  // --- Transfer tests: public to private ---

  it('transfers NFT from public to private', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Verify alice owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, alice);

    // Transfer NFT from alice's public balance to private balance
    await nft.methods.transfer_public_to_private(alice, bob, tokenId, 0n).send({ from: alice }).wait();

    // Verify alice no longer owns the NFT publicly
    const publicOwner = await nft.methods.public_owner_of(tokenId).simulate({ from: alice });
    expect(publicOwner.equals(AztecAddress.ZERO)).toBe(true);

    // Verify bob now owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, bob);
  }, 300_000);

  it('fails to transfer public NFT to private when not owner', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Carl attempts to transfer alice's NFT to bob
    await expect(
      nft.methods.transfer_public_to_private(carl, bob, tokenId, 0n).send({ from: carl }).wait(),
    ).rejects.toThrow(/^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/);

    // Verify alice still owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, alice);
  }, 300_000);

  it('transfers NFT from public to private with authorization', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Create transfer call interface with non-zero nonce
    const transferCallInterface = nft.methods.transfer_public_to_private(alice, bob, tokenId, 1n);

    // Add authorization witness from alice to bob
    const intent: ContractFunctionInteractionCallIntent = {
      caller: bob,
      action: transferCallInterface,
    };
    const witness = await wallet.createAuthWit(alice, intent);

    // Bob executes the transfer with alice's authorization
    await transferCallInterface.send({ from: bob, authWitnesses: [witness] }).wait();

    // Verify alice no longer owns the NFT publicly
    const publicOwner = await nft.methods.public_owner_of(tokenId).simulate({ from: alice });
    expect(publicOwner.equals(AztecAddress.ZERO)).toBe(true);

    // Verify bob now owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, bob);
  }, 300_000);

  // --- Transfer tests: public to public ---

  it('transfers NFT from public to public', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Verify alice owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, alice);

    // Transfer NFT from alice to bob publicly
    await nft.methods.transfer_public_to_public(alice, bob, tokenId, 0n).send({ from: alice }).wait();

    // Verify alice no longer owns the NFT publicly
    const aliceOwner = await nft.methods.public_owner_of(tokenId).simulate({ from: alice });
    expect(aliceOwner.equals(alice)).toBe(false);

    // Verify bob now owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob);
  }, 300_000);

  it('fails to transfer public NFT when not owner', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Carl attempts to transfer alice's NFT to bob
    await expect(
      nft.methods.transfer_public_to_public(carl, bob, tokenId, 0n).send({ from: carl }).wait(),
    ).rejects.toThrow(/^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/);

    // Verify alice still owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, alice);
  }, 300_000);

  // TODO: Pass this test
  it.skip('transfers NFT from public to public with authorization', async () => {
    const tokenId = 1n;

    // First mint NFT publicly to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Verify initial ownership
    const initialOwner = await nft.methods.public_owner_of(tokenId).simulate({ from: alice });
    expect(initialOwner.equals(alice)).toBe(true);

    // Create transfer call interface with non-zero nonce
    const action = nft.methods.transfer_public_to_public(alice, bob, tokenId, 1n);

    // Add authorization witness from alice to bob
    const intent: ContractFunctionInteractionCallIntent = {
      caller: bob,
      action,
    };
    // TODO: failing here
    const witness = await wallet.createAuthWit(alice, intent);

    const validity = await wallet.lookupValidity(alice, intent, witness);
    expect(validity.isValidInPrivate).toBeTruthy();
    expect(validity.isValidInPublic).toBeFalsy();

    // Bob executes the transfer with alice's authorization
    await action.send({ from: bob, authWitnesses: [witness] }).wait();

    // Verify final ownership
    const finalOwner = await nft.methods.public_owner_of(tokenId).simulate({ from: bob });
    expect(finalOwner.equals(bob)).toBe(true);
  }, 300_000);

  // --- View function tests ---

  it('returns correct name and symbol', async () => {
    const name = await nft.methods.public_get_name().simulate({ from: alice });
    const symbol = await nft.methods.public_get_symbol().simulate({ from: alice });
    const nameStr = bigIntToAsciiString(name.value);
    const symbolStr = bigIntToAsciiString(symbol.value);

    expect(nameStr).toBe('TestNFT');
    expect(symbolStr).toBe('TNFT');
  }, 300_000);

  it('returns correct public owner', async () => {
    const tokenId = 1n;

    // Initially no owner (zero address)
    const initialOwner = await nft.methods.public_owner_of(tokenId).simulate({ from: alice });
    expect(initialOwner.equals(AztecAddress.ZERO)).toBe(true);

    // Mint NFT to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Check owner is alice
    const owner = await nft.methods.public_owner_of(tokenId).simulate({ from: alice });
    expect(owner.equals(alice)).toBe(true);
  }, 300_000);

  it('returns private NFTs owned by address', async () => {
    const tokenId1 = 1n;
    const tokenId2 = 2n;

    // Initially no NFTs
    const [initialNfts, initialLimitReached] = await nft.methods.get_private_nfts(alice, 0).simulate({ from: alice });
    expect(initialNfts.every((id: bigint) => id === 0n)).toBe(true);
    expect(initialLimitReached).toBe(false);

    // Mint two NFTs to alice
    await nft.methods.mint_to_private(alice, tokenId1).send({ from: alice }).wait();
    await nft.methods.mint_to_private(alice, tokenId2).send({ from: alice }).wait();

    // Check owned NFTs
    const [ownedNfts, limitReached] = await nft.methods.get_private_nfts(alice, 0).simulate({ from: alice });
    expect(ownedNfts).toContain(tokenId1);
    expect(ownedNfts).toContain(tokenId2);
    expect(limitReached).toBe(false);
  }, 300_000);

  // --- Access control tests ---

  it('enforces minter role for minting', async () => {
    const tokenId = 1n;

    // Deploy new contract with bob as minter
    const nftWithBobMinter = (await deployNFTWithMinter(wallet, bob)) as NFTContract;

    // Alice attempts to mint when she's not the minter
    await expect(nftWithBobMinter.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );

    await expect(nftWithBobMinter.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait()).rejects.toThrow(
      /caller is not minter/,
    );

    // Bob can mint since he's the minter
    await nftWithBobMinter.methods.mint_to_public(alice, tokenId).send({ from: bob }).wait();
    await assertOwnsPublicNFT(nftWithBobMinter, tokenId, alice);
  }, 300_000);

  it('enforces ownership for public transfers', async () => {
    const tokenId = 1n;

    // Mint NFT to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Bob attempts to transfer without ownership or authorization
    await expect(
      nft.methods.transfer_public_to_public(bob, carl, tokenId, 0n).send({ from: bob }).wait(),
    ).rejects.toThrow(/^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/);

    // Alice can transfer since she's the owner
    await nft.methods.transfer_public_to_public(alice, bob, tokenId, 0n).send({ from: alice }).wait();
    await assertOwnsPublicNFT(nft, tokenId, bob);
  }, 300_000);

  it('enforces ownership for private transfers', async () => {
    const tokenId = 1n;

    // Mint NFT privately to alice
    await nft.methods.mint_to_private(alice, tokenId).send({ from: alice }).wait();

    // Bob attempts to transfer without ownership or authorization
    await expect(
      nft.methods.transfer_private_to_private(bob, carl, tokenId, 0n).send({ from: bob }).wait(),
    ).rejects.toThrow(/nft not found/);

    // Alice can transfer since she's the owner
    await nft.methods.transfer_private_to_private(alice, bob, tokenId, 0n).send({ from: alice }).wait();
    await assertOwnsPrivateNFT(nft, tokenId, bob);
  }, 300_000);

  it('enforces authorization for transfers', async () => {
    const tokenId = 1n;
    const invalidNonce = 999n;

    // Mint NFT to alice
    await nft.methods.mint_to_public(alice, tokenId).send({ from: alice }).wait();

    // Bob attempts transfer with invalid authorization
    const transferCallInterface = nft.methods.transfer_public_to_public(alice, bob, tokenId, invalidNonce);

    const intent: ContractFunctionInteractionCallIntent = {
      caller: bob,
      action: transferCallInterface,
    };

    // Create auth witness with wrong nonce
    const witness = await wallet.createAuthWit(carl, intent); // Wrong signer (carl instead of alice)

    // Transfer should fail with invalid authorization
    await expect(transferCallInterface.send({ from: bob, authWitnesses: [witness] }).wait()).rejects.toThrow();

    // Alice still owns the NFT
    await assertOwnsPublicNFT(nft, tokenId, alice);
  }, 300_000);
});

function bigIntToAsciiString(bigInt: any): string {
  // Convert the BigInt to hex string, remove '0x' prefix if present
  let hexString = bigInt.toString(16);

  // Split into pairs of characters (bytes)
  const pairs = [];
  for (let i = 0; i < hexString.length; i += 2) {
    // If we have an odd number of characters, pad with 0
    const pair = hexString.slice(i, i + 2).padStart(2, '0');
    pairs.push(pair);
  }

  // Convert each byte to its ASCII character
  let asciiString = '';
  for (const pair of pairs) {
    const charCode = parseInt(pair, 16);
    // Only add printable ASCII characters
    if (charCode >= 32 && charCode <= 126) {
      asciiString += String.fromCharCode(charCode);
    }
  }
  return asciiString;
}
