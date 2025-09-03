import { Fr, AccountWalletWithSecretKey, PublicKeys, AztecAddress, GrumpkinScalar } from '@aztec/aztec.js';
import { deriveKeys } from '@aztec/stdlib/keys';
import {
  setupPXE,
  deployTokenWithMinter,
  AMOUNT,
  expectTokenBalances,
  assertOwnsPrivateNFT,
  wad,
  deployNFTWithMinter,
  deployEscrow,
  expectUintNote,
} from './utils.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { EscrowContract } from '../../../artifacts/Escrow.js';
import { TokenContract } from '../../../artifacts/Token.js';
import { NFTContract } from '../../../artifacts/NFT.js';

const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const managers = await getInitialTestAccountsManagers(pxe);
  const wallets = await Promise.all(managers.map((acc) => acc.register()));
  const [deployer] = wallets;

  return { pxe, deployer, wallets, store };
};

describe('Escrow', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;

  let wallets: AccountWalletWithSecretKey[];
  let deployer: AccountWalletWithSecretKey;

  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let logicMock: AccountWalletWithSecretKey;
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
    ({ pxe, deployer, wallets, store } = await setupTestSuite());

    [alice, bob, logicMock] = wallets;

    // We default to a secret key of 1 for testing purposes
    escrowSk = Fr.random();

    // Derive the keys from the secret key
    escrowKeys = await deriveKeys(escrowSk);

    // Use the logic contract address as the salt for the escrow contract
    escrowSalt = new Fr(logicMock.getAddress().toBigInt());

    // Deploy an escrow contract
    escrow = (await deployEscrow(escrowKeys.publicKeys, alice, escrowSalt)) as EscrowContract;

    const partialAddressEscrow = await escrow.partialAddress;
    await pxe.registerAccount(escrowSk, partialAddressEscrow);
  });

  afterEach(async () => {
    await store.delete();
  });

  describe('authorization', () => {
    it('withdrawing tokens from self should fail', async () => {
      await expect(
        escrow.methods.withdraw(AztecAddress.ZERO, 0, AztecAddress.ZERO).simulate({ from: escrow.instance.address }),
      ).rejects.toThrow(/Assertion failed: Not Authorized/);
    });

    it('withdrawing nft from self should fail', async () => {
      await expect(
        escrow.methods
          .withdraw_nft(AztecAddress.ZERO, 0, AztecAddress.ZERO)
          .simulate({ from: escrow.instance.address }),
      ).rejects.toThrow(/Assertion failed: Not Authorized/);
    });

    it('withdrawing tokens from account different than the logic contract should fail', async () => {
      await expect(
        escrow.withWallet(bob).methods.withdraw(AztecAddress.ZERO, 0, AztecAddress.ZERO).send().wait(),
      ).rejects.toThrow(/Assertion failed: Not Authorized/);
    });

    it('withdrawing nft from account different than the logic contract should fail', async () => {
      await expect(
        escrow.withWallet(bob).methods.withdraw_nft(AztecAddress.ZERO, 0, AztecAddress.ZERO).send().wait(),
      ).rejects.toThrow(/Assertion failed: Not Authorized/);
    });
  });

  describe('withdraw', () => {
    beforeEach(async () => {
      token = (await deployTokenWithMinter(alice, {})) as TokenContract;
      await token
        .withWallet(alice)
        .methods.mint_to_private(alice.getAddress(), escrow.instance.address, AMOUNT)
        .send()
        .wait();
    });

    it('logic should be able to withdraw correctly', async () => {
      await expectTokenBalances(token, escrow.instance.address, wad(0), AMOUNT);
      await expectTokenBalances(token, bob.getAddress(), wad(0), wad(0));

      const bobWithdrawTx = await escrow
        .withWallet(logicMock)
        .methods.withdraw(token.instance.address, AMOUNT, bob.getAddress())
        .send()
        .wait();

      await expectTokenBalances(token, escrow.instance.address, wad(0), wad(0));
      await expectTokenBalances(token, bob.getAddress(), wad(0), AMOUNT);

      const notes = await pxe.getNotes({ txHash: bobWithdrawTx.txHash });
      expect(notes.length).toBe(1);
      expectUintNote(notes[0], AMOUNT, bob.getAddress());
    });

    it('withdrawing less than the balance should succeed', async () => {
      const halfAmount = AMOUNT / 2n;

      await expectTokenBalances(token, escrow.instance.address, wad(0), AMOUNT);
      await expectTokenBalances(token, bob.getAddress(), wad(0), wad(0));

      const bobWithdrawTx = await escrow
        .withWallet(logicMock)
        .methods.withdraw(token.instance.address, halfAmount, bob.getAddress())
        .send()
        .wait();

      await expectTokenBalances(token, escrow.instance.address, wad(0), halfAmount);
      await expectTokenBalances(token, bob.getAddress(), wad(0), halfAmount);

      const notes = await pxe.getNotes({ txHash: bobWithdrawTx.txHash });
      expect(notes.length).toBe(2);
      expectUintNote(notes[0], halfAmount, escrow.instance.address);
      expectUintNote(notes[1], halfAmount, bob.getAddress());
    });

    it('withdrawing more than the balance should fail', async () => {
      await expect(
        escrow
          .withWallet(logicMock)
          .methods.withdraw(token.instance.address, AMOUNT + 1n, bob.getAddress())
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low/);
    });
  });

  describe('withdraw NFT', () => {
    let nft: NFTContract;
    let tokenId: bigint;

    beforeEach(async () => {
      tokenId = 1n;
      nft = (await deployNFTWithMinter(alice, {})) as NFTContract;
      await nft.withWallet(alice).methods.mint_to_private(escrow.instance.address, tokenId).send().wait();
    });

    it('logic should be able to withdraw NFT correctly', async () => {
      await assertOwnsPrivateNFT(nft, tokenId, escrow.instance.address);

      const bobWithdrawTx = await escrow
        .withWallet(logicMock)
        .methods.withdraw_nft(nft.instance.address, tokenId, bob.getAddress())
        .send()
        .wait();

      await assertOwnsPrivateNFT(nft, tokenId, bob.getAddress());

      const notes = await pxe.getNotes({ txHash: bobWithdrawTx.txHash });
      expect(notes.length).toBe(1);
      expectUintNote(notes[0], tokenId, bob.getAddress());
    });

    it('withdrawing non-existent NFT should fail', async () => {
      await expect(
        escrow
          .withWallet(logicMock)
          .methods.withdraw_nft(nft.instance.address, tokenId + 1n, bob.getAddress())
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: nft not found in private to public/);
    });
  });
});
