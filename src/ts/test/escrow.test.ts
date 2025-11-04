import { type PXE } from '@aztec/pxe/server';
import { deriveKeys } from '@aztec/stdlib/keys';
import { PublicKeys } from '@aztec/aztec.js/keys';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
import { type AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import { Fr, type GrumpkinScalar } from '@aztec/aztec.js/fields';

import { EscrowContract, EscrowContractArtifact } from '../../../artifacts/Escrow.js';
import { TokenContract } from '../../../artifacts/Token.js';
import { NFTContract } from '../../../artifacts/NFT.js';

import {
  setupTestSuite,
  deployTokenWithMinter,
  AMOUNT,
  expectTokenBalances,
  assertOwnsPrivateNFT,
  wad,
  deployNFTWithMinter,
  deployEscrow,
  expectUintNote,
} from './utils.js';

describe('Escrow', () => {
  let pxe: PXE;
  let store: AztecLMDBStoreV2;

  let wallet: TestWallet;
  let accounts: AztecAddress[];

  let alice: AztecAddress;
  let bob: AztecAddress;
  let logicMock: AztecAddress;
  let token: TokenContract;

  // Escrow contract
  let escrow: EscrowContract;
  let escrowSk: Fr;
  let escrowKeys: {
    masterNullifierSecretKey: GrumpkinScalar;
    masterIncomingViewingSecretKey: GrumpkinScalar;
    masterOutgoingViewingSecretKey: GrumpkinScalar;
    masterTaggingSecretKey: GrumpkinScalar;
    publicKeys: PublicKeys;
  };
  let escrowSalt: Fr;

  beforeEach(async () => {
    ({ pxe, store, wallet, accounts } = await setupTestSuite());

    [alice, bob, logicMock] = accounts;

    // We default to a secret key of 1 for testing purposes
    escrowSk = Fr.random();

    // Derive the keys from the secret key
    escrowKeys = await deriveKeys(escrowSk);

    // Use the logic contract address as the salt for the escrow contract
    escrowSalt = new Fr(logicMock.toBigInt());

    // Deploy an escrow contract
    escrow = (await deployEscrow(escrowKeys.publicKeys, wallet, alice, escrowSalt)) as EscrowContract;

    await wallet.registerContract(escrow.instance, EscrowContractArtifact, escrowSk);
  });

  afterEach(async () => {
    await store.delete();
  });

  describe('authorization', () => {
    it('withdrawing tokens from account different than the logic contract should fail', async () => {
      await expect(
        escrow.withWallet(wallet).methods.withdraw(AztecAddress.ZERO, 0, AztecAddress.ZERO).send({ from: bob }).wait(),
      ).rejects.toThrow(/Assertion failed: Not Authorized/);
    });

    it('withdrawing nft from account different than the logic contract should fail', async () => {
      await expect(
        escrow
          .withWallet(wallet)
          .methods.withdraw_nft(AztecAddress.ZERO, 0, AztecAddress.ZERO)
          .send({ from: bob })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Not Authorized/);
    });
  });

  describe('withdraw', () => {
    beforeEach(async () => {
      token = (await deployTokenWithMinter(wallet, alice)) as TokenContract;
      await token
        .withWallet(wallet)
        .methods.mint_to_private(escrow.instance.address, AMOUNT)
        .send({ from: alice })
        .wait();
    });

    it('logic should be able to withdraw correctly', async () => {
      await expectTokenBalances(token, escrow.instance.address, wad(0), AMOUNT, bob);
      await expectTokenBalances(token, bob, wad(0), wad(0));

      await escrow
        .withWallet(wallet)
        .methods.withdraw(token.instance.address, AMOUNT, bob)
        .send({ from: logicMock })
        .wait();

      await expectTokenBalances(token, escrow.instance.address, wad(0), wad(0), bob);
      await expectTokenBalances(token, bob, wad(0), AMOUNT);

      const notes = await wallet.getNotes({ contractAddress: token.address, scopes: [bob] });
      expect(notes.length).toBe(1);
      expectUintNote(notes[0], AMOUNT, bob);
    });

    it('withdrawing less than the balance should succeed', async () => {
      const halfAmount = AMOUNT / 2n;

      await expectTokenBalances(token, escrow.instance.address, wad(0), AMOUNT, bob);
      await expectTokenBalances(token, bob, wad(0), wad(0));

      await escrow
        .withWallet(wallet)
        .methods.withdraw(token.instance.address, halfAmount, bob)
        .send({ from: logicMock })
        .wait();

      await expectTokenBalances(token, escrow.instance.address, wad(0), halfAmount, bob);
      await expectTokenBalances(token, bob, wad(0), halfAmount);

      const escrowNote = await wallet.getNotes({ contractAddress: token.address, scopes: [escrow.instance.address] });
      expect(escrowNote.length).toBe(1);
      expectUintNote(escrowNote[0], halfAmount, escrow.instance.address);

      const bobNote = await wallet.getNotes({ contractAddress: token.address, scopes: [bob] });
      expect(bobNote.length).toBe(1);
      expectUintNote(bobNote[0], halfAmount, bob);
    });

    it('withdrawing more than the balance should fail', async () => {
      await expect(
        escrow
          .withWallet(wallet)
          .methods.withdraw(token.instance.address, AMOUNT + 1n, bob)
          .send({ from: logicMock })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low/);
    });
  });

  describe('withdraw NFT', () => {
    let nft: NFTContract;
    let tokenId: bigint;

    beforeEach(async () => {
      tokenId = 1n;
      nft = (await deployNFTWithMinter(wallet, alice)) as NFTContract;
      await nft
        .withWallet(wallet)
        .methods.mint_to_private(escrow.instance.address, tokenId)
        .send({ from: alice })
        .wait();
    });

    it('logic should be able to withdraw NFT correctly', async () => {
      await assertOwnsPrivateNFT(nft, tokenId, escrow.instance.address, bob);

      await escrow
        .withWallet(wallet)
        .methods.withdraw_nft(nft.instance.address, tokenId, bob)
        .send({ from: logicMock })
        .wait();

      await assertOwnsPrivateNFT(nft, tokenId, bob);

      const notes = await wallet.getNotes({ contractAddress: nft.address, scopes: [bob] });
      expect(notes.length).toBe(1);
      expectUintNote(notes[0], tokenId, bob);
    });

    it('withdrawing non-existent NFT should fail', async () => {
      await expect(
        escrow
          .withWallet(wallet)
          .methods.withdraw_nft(nft.instance.address, tokenId + 1n, bob)
          .send({ from: logicMock })
          .wait(),
      ).rejects.toThrow(/Assertion failed: nft not found in private to public/);
    });
  });
});
