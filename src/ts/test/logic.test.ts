import {
  ContractDeployer,
  Fr,
  TxStatus,
  getContractInstanceFromInstantiationParams,
  Contract,
  AccountWalletWithSecretKey,
  AccountWallet,
  PublicKeys,
  AztecAddress,
  GrumpkinScalar,
  getContractClassFromArtifact,
} from '@aztec/aztec.js';
import { deriveKeys } from '@aztec/stdlib/keys';
import {
  setupPXE,
  deployTokenWithMinter,
  AMOUNT,
  expectTokenBalances,
  wad,
  deployNFTWithMinter,
  expectUintNote,
} from './utils.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { TestLogicContractArtifact, TestLogicContract, EscrowDetailsLogContent } from '../../../artifacts/TestLogic.js';
import { EscrowContractArtifact, EscrowContract } from '../../../artifacts/Escrow.js';
import { TokenContract } from '../../../artifacts/Token.js';
import { NFTContract } from '../../../artifacts/NFT.js';
import { deployLogic, deployEscrowWithPublicKeysAndSalt, grumpkinScalarToFr, deriveContractAddress } from './utils.js';

// Check if an address owns a specific NFT in private state
async function assertOwnsPrivateNFT(
  nft: NFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  expectToBeTrue: boolean,
  caller?: AccountWallet,
) {
  const n = caller ? nft.withWallet(caller) : nft;
  const [nfts, _] = await n.methods.get_private_nfts(owner, 0).simulate({ from: owner });
  const hasNFT = nfts.some((id: bigint) => id === tokenId);
  expect(hasNFT).toBe(expectToBeTrue);
}

const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const managers = await getInitialTestAccountsManagers(pxe);
  const wallets = await Promise.all(managers.map((acc) => acc.register()));
  const [deployer] = wallets;

  return { pxe, deployer, wallets, store };
};

describe('Logic - Single PXE', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;

  let wallets: AccountWalletWithSecretKey[];
  let deployer: AccountWalletWithSecretKey;

  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let carl: AccountWalletWithSecretKey;

  // Logic contract
  let logic: TestLogicContract;

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
  let escrowClassId: Fr;
  let secretKeys: {
    nsk_m: Fr;
    ivsk_m: Fr;
    ovsk_m: Fr;
    tsk_m: Fr;
  };

  async function setup() {
    ({ pxe, deployer, wallets, store } = await setupTestSuite());

    [alice, bob, carl] = wallets;

    // Get the class id of the escrow contract
    escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

    // We default to a secret key of 1 for testing purposes
    escrowSk = Fr.ONE;

    // Derive the keys from the secret key
    escrowKeys = await deriveKeys(escrowSk);

    // Convert the keys to Fr
    secretKeys = {
      nsk_m: grumpkinScalarToFr(escrowKeys.masterNullifierSecretKey),
      ivsk_m: grumpkinScalarToFr(escrowKeys.masterIncomingViewingSecretKey),
      ovsk_m: grumpkinScalarToFr(escrowKeys.masterOutgoingViewingSecretKey),
      tsk_m: grumpkinScalarToFr(escrowKeys.masterTaggingSecretKey),
    };
  }

  beforeAll(async () => {
    await setup();
  });

  beforeEach(async () => {
    // Logic is deployed with the public keys because it sends encrypted events to the recipient and with the escrow class id
    logic = (await deployLogic(alice, escrowClassId)) as TestLogicContract;

    // Use the logic contract address as the salt for the escrow contract
    escrowSalt = new Fr(logic.instance.address.toBigInt());

    // Deploy an escrow contract
    escrow = (await deployEscrowWithPublicKeysAndSalt(escrowKeys.publicKeys, alice, escrowSalt)) as EscrowContract;
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('Deployment', () => {
    it('deploys logic with correct constructor params', async () => {
      const deploymentData = await getContractInstanceFromInstantiationParams(TestLogicContractArtifact, {
        constructorArtifact: 'constructor',
        constructorArgs: [escrowClassId],
        salt: escrowSalt,
        deployer: alice.getAddress(),
      });

      const deployer = new ContractDeployer(TestLogicContractArtifact, alice, undefined, 'constructor');
      const tx = deployer.deploy(escrowClassId).send({
        contractAddressSalt: escrowSalt,
        from: alice.getAddress(),
      });

      const receipt = await tx.getReceipt();

      expect(receipt).toEqual(
        expect.objectContaining({
          status: TxStatus.PENDING,
          error: '',
        }),
      );

      const receiptAfterMined = await tx.wait({ wallet: alice });

      const contractMetadata = await pxe.getContractMetadata(deploymentData.address);
      expect(contractMetadata).toBeDefined();
      expect(contractMetadata.isContractPublished).toBeTruthy();
      expect(receiptAfterMined).toEqual(
        expect.objectContaining({
          status: TxStatus.SUCCESS,
        }),
      );

      expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
    });

    it('deploys escrow with correctly derived address', async () => {
      const { address, initializationHash } = await deriveContractAddress(
        EscrowContractArtifact,
        [], // constructor args are null
        AztecAddress.ZERO, // deployer is null
        escrowSalt,
        escrowKeys.publicKeys,
      );

      expect(address).toEqual(escrow.instance.address);
      expect(initializationHash).toEqual(Fr.ZERO);
      expect(initializationHash).toEqual(escrow.instance.initializationHash);
    });
  });

  describe('secret_keys_to_public_keys', () => {
    it('logic derives public keys from private keys correctly', async () => {
      const circuitPublicKeys = await logic.methods
        .secret_keys_to_public_keys(secretKeys)
        .simulate({ from: alice.getAddress() });

      expect(new Fr(circuitPublicKeys.npk_m.inner.x).toString()).toBe(
        escrowKeys.publicKeys.masterNullifierPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.npk_m.inner.y).toString()).toBe(
        escrowKeys.publicKeys.masterNullifierPublicKey.y.toString(),
      );
      expect(new Fr(circuitPublicKeys.ivpk_m.inner.x).toString()).toBe(
        escrowKeys.publicKeys.masterIncomingViewingPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.ivpk_m.inner.y).toString()).toBe(
        escrowKeys.publicKeys.masterIncomingViewingPublicKey.y.toString(),
      );
      expect(new Fr(circuitPublicKeys.ovpk_m.inner.x).toString()).toBe(
        escrowKeys.publicKeys.masterOutgoingViewingPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.ovpk_m.inner.y).toString()).toBe(
        escrowKeys.publicKeys.masterOutgoingViewingPublicKey.y.toString(),
      );
      expect(new Fr(circuitPublicKeys.tpk_m.inner.x).toString()).toBe(
        escrowKeys.publicKeys.masterTaggingPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.tpk_m.inner.y).toString()).toBe(
        escrowKeys.publicKeys.masterTaggingPublicKey.y.toString(),
      );
    });

    it('logic key derivation should fail if the secret key is not correct', async () => {
      const secretKeysPlusOne = {
        nsk_m: secretKeys.nsk_m.add(Fr.ONE),
        ivsk_m: secretKeys.ivsk_m.add(Fr.ONE),
        ovsk_m: secretKeys.ovsk_m.add(Fr.ONE),
        tsk_m: secretKeys.tsk_m.add(Fr.ONE),
      };

      // We add 1 to the secret key to make it incorrect
      const circuitPublicKeys = await logic.methods
        .secret_keys_to_public_keys(secretKeysPlusOne)
        .simulate({ from: alice.getAddress() });

      expect(new Fr(circuitPublicKeys.npk_m.inner.x).toString()).not.toBe(
        escrowKeys.publicKeys.masterNullifierPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.npk_m.inner.y).toString()).not.toBe(
        escrowKeys.publicKeys.masterNullifierPublicKey.y.toString(),
      );
      expect(new Fr(circuitPublicKeys.ivpk_m.inner.x).toString()).not.toBe(
        escrowKeys.publicKeys.masterIncomingViewingPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.ivpk_m.inner.y).toString()).not.toBe(
        escrowKeys.publicKeys.masterIncomingViewingPublicKey.y.toString(),
      );
      expect(new Fr(circuitPublicKeys.ovpk_m.inner.x).toString()).not.toBe(
        escrowKeys.publicKeys.masterOutgoingViewingPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.ovpk_m.inner.y).toString()).not.toBe(
        escrowKeys.publicKeys.masterOutgoingViewingPublicKey.y.toString(),
      );
      expect(new Fr(circuitPublicKeys.tpk_m.inner.x).toString()).not.toBe(
        escrowKeys.publicKeys.masterTaggingPublicKey.x.toString(),
      );
      expect(new Fr(circuitPublicKeys.tpk_m.inner.y).toString()).not.toBe(
        escrowKeys.publicKeys.masterTaggingPublicKey.y.toString(),
      );
    });
  });

  describe('check_escrow', () => {
    it('logic should be able to check escrow correctly', async () => {
      await logic.methods.check_escrow(escrow.instance.address, secretKeys).simulate({ from: alice.getAddress() });
    });

    it('check escrow with incorrect secret keys should fail', async () => {
      // We add 1 to each secret key to make it incorrect
      let secretKeysPlusOne = {
        nsk_m: secretKeys.nsk_m.add(Fr.ONE),
        ivsk_m: secretKeys.ivsk_m.add(Fr.ONE),
        ovsk_m: secretKeys.ovsk_m.add(Fr.ONE),
        tsk_m: secretKeys.tsk_m.add(Fr.ONE),
      };

      await expect(
        logic.methods
          .check_escrow(escrow.instance.address, secretKeysPlusOne)
          .send({ from: alice.getAddress() })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Escrow public keys mismatch/);
    });

    it('check escrow with non zero deployer should fail', async () => {
      // Re-deploy the escrow contract with no universalDeploy
      escrow = (await Contract.deployWithPublicKeys(escrowKeys.publicKeys, alice, EscrowContractArtifact, [])
        .send({ contractAddressSalt: escrowSalt, from: alice.getAddress() })
        .deployed()) as EscrowContract;

      await expect(
        logic.methods.check_escrow(escrow.instance.address, secretKeys).send({ from: alice.getAddress() }).wait(),
      ).rejects.toThrow(/Assertion failed: Escrow deployer should be null/);
    });

    it('check escrow with incorrect class id should fail', async () => {
      // Re-deploy the logic contract with an incorrect class id
      logic = (await deployLogic(alice, escrowClassId.add(Fr.ONE))) as TestLogicContract;

      await expect(
        logic.methods.check_escrow(escrow.instance.address, secretKeys).send({ from: alice.getAddress() }).wait(),
      ).rejects.toThrow(/Assertion failed: Escrow class id mismatch/);
    });

    it('check escrow with incorrect salt should fail', async () => {
      // Re-deploy the escrow contract with a different salt (different from the logic contract address)
      escrow = (await deployEscrowWithPublicKeysAndSalt(
        escrowKeys.publicKeys,
        alice,
        escrowSalt.add(Fr.ONE),
      )) as EscrowContract;

      await expect(
        logic.methods.check_escrow(escrow.instance.address, secretKeys).send({ from: alice.getAddress() }).wait(),
      ).rejects.toThrow(/Assertion failed: Escrow salt mismatch/);
    });

    // Testing non-zero initialization hash supposes there is an initialize function in the escrow contract
    // which is not the case for the current escrow contract
  });

  describe('share_escrow', () => {
    it('logic should be able to share escrow correctly', async () => {
      const alicePxe = pxe;
      await alicePxe.registerAccount(bob.getSecretKey(), bob.getCompleteAddress().partialAddress);

      // Share the escrow contract with bob
      const tx = await logic.methods
        .share_escrow(bob.getAddress(), escrow.instance.address, secretKeys)
        .send({ from: alice.getAddress() })
        .wait();
      const blockNumber = tx.blockNumber!;

      const bobPxe = pxe;

      const events = await bobPxe.getPrivateEvents<EscrowDetailsLogContent>(
        logic.address,
        TestLogicContract.events.EscrowDetailsLogContent,
        blockNumber,
        1,
        [bob.getAddress()],
      );

      expect(events.length).toBe(1);

      const event = events[0];

      expect(event.escrow).toEqual(escrow.instance.address);
      expect(event.master_secret_keys.nsk_m).toEqual(escrowKeys.masterNullifierSecretKey.toBigInt());
      expect(event.master_secret_keys.ivsk_m).toEqual(escrowKeys.masterIncomingViewingSecretKey.toBigInt());
      expect(event.master_secret_keys.ovsk_m).toEqual(escrowKeys.masterOutgoingViewingSecretKey.toBigInt());
      expect(event.master_secret_keys.tsk_m).toEqual(escrowKeys.masterTaggingSecretKey.toBigInt());
    });

    it('share escrow with multiple recipients correctly', async () => {
      const alicePxe = pxe;
      await alicePxe.registerAccount(bob.getSecretKey(), bob.getCompleteAddress().partialAddress);

      // Share the escrow contract with bob
      const txForBob = await logic.methods
        .share_escrow(bob.getAddress(), escrow.instance.address, secretKeys)
        .send({ from: alice.getAddress() })
        .wait();
      const blockNumberBob = txForBob.blockNumber!;

      const txForCarl = await logic.methods
        .share_escrow(carl.getAddress(), escrow.instance.address, secretKeys)
        .send({ from: alice.getAddress() })
        .wait();
      const blockNumberCarl = txForCarl.blockNumber!;

      const numberOfBlocks = blockNumberCarl - blockNumberBob + 1;

      const bobPxe = pxe;

      // Get the events for both bob and carl from bob's pxe for simplicity
      const events = await bobPxe.getPrivateEvents<EscrowDetailsLogContent>(
        logic.address,
        TestLogicContract.events.EscrowDetailsLogContent,
        blockNumberBob,
        numberOfBlocks,
        [bob.getAddress(), carl.getAddress()],
      );

      expect(events.length).toBe(2);

      const eventForBob = events[0];
      expect(eventForBob.escrow).toEqual(escrow.instance.address);
      expect(eventForBob.master_secret_keys.nsk_m).toEqual(escrowKeys.masterNullifierSecretKey.toBigInt());
      expect(eventForBob.master_secret_keys.ivsk_m).toEqual(escrowKeys.masterIncomingViewingSecretKey.toBigInt());
      expect(eventForBob.master_secret_keys.ovsk_m).toEqual(escrowKeys.masterOutgoingViewingSecretKey.toBigInt());
      expect(eventForBob.master_secret_keys.tsk_m).toEqual(escrowKeys.masterTaggingSecretKey.toBigInt());

      const eventForCarl = events[1];
      expect(eventForCarl.escrow).toEqual(escrow.instance.address);
      expect(eventForCarl.master_secret_keys.nsk_m).toEqual(escrowKeys.masterNullifierSecretKey.toBigInt());
      expect(eventForCarl.master_secret_keys.ivsk_m).toEqual(escrowKeys.masterIncomingViewingSecretKey.toBigInt());
      expect(eventForCarl.master_secret_keys.ovsk_m).toEqual(escrowKeys.masterOutgoingViewingSecretKey.toBigInt());
      expect(eventForCarl.master_secret_keys.tsk_m).toEqual(escrowKeys.masterTaggingSecretKey.toBigInt());
    });
  });

  describe('withdraw', () => {
    let token: TokenContract;

    beforeEach(async () => {
      token = (await deployTokenWithMinter(alice)) as TokenContract;

      const partialAddressEscrow = await escrow.partialAddress;
      await pxe.registerAccount(escrowSk, partialAddressEscrow);

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.instance.address, escrow.instance.address, AMOUNT)
        .send({ from: alice.getAddress() })
        .wait();
    });

    it('logic should be able to withdraw correctly', async () => {
      const bobPxe = pxe;

      // Add bob to bob's PXE
      await bobPxe.registerAccount(bob.getSecretKey(), bob.getCompleteAddress().partialAddress);

      // Bob needs to register the escrow contract as an account
      const partialAddressEscrow = await escrow.partialAddress;
      await bobPxe.registerAccount(escrowSk, partialAddressEscrow);

      // Bob needs to sync his private state to see the escrow details
      await token.withWallet(bob).methods.sync_private_state().simulate({ from: bob.getAddress() });

      await expectTokenBalances(token, escrow.instance.address, wad(0), AMOUNT, bob);
      await expectTokenBalances(token, bob.getAddress(), wad(0), wad(0), bob);

      const bobWithdrawTx = await logic
        .withWallet(bob)
        .methods.withdraw(escrow.instance.address, bob.getAddress(), token.instance.address, AMOUNT)
        .send({ from: bob.getAddress() })
        .wait();

      await token.withWallet(bob).methods.sync_private_state().simulate({ from: bob.getAddress() });

      await expectTokenBalances(token, escrow.instance.address, wad(0), wad(0), bob);
      await expectTokenBalances(token, bob.getAddress(), wad(0), AMOUNT, bob);

      const notes = await bobPxe.getNotes({ contractAddress: token.address, txHash: bobWithdrawTx.txHash });
      expect(notes.length).toBe(1);
      expectUintNote(notes[0], AMOUNT, bob.getAddress());
    });

    it('withdrawing less than the balance should succeed', async () => {
      const bobPxe = pxe;

      const halfAmount = AMOUNT / 2n;

      // Add bob to bob's PXE
      await bobPxe.registerAccount(bob.getSecretKey(), bob.getCompleteAddress().partialAddress);

      // Bob needs to register the escrow contract as an account
      const partialAddressEscrow = await escrow.partialAddress;
      await bobPxe.registerAccount(escrowSk, partialAddressEscrow);

      // Bob needs to sync his private state to see the escrow details
      await token.withWallet(bob).methods.sync_private_state().simulate({ from: bob.getAddress() });

      await expectTokenBalances(token, escrow.instance.address, wad(0), AMOUNT, bob);
      await expectTokenBalances(token, bob.getAddress(), wad(0), wad(0), bob);

      const bobWithdrawTx = await logic
        .withWallet(bob)
        .methods.withdraw(escrow.instance.address, bob.getAddress(), token.instance.address, halfAmount)
        .send({ from: bob.getAddress() })
        .wait();

      await token.withWallet(bob).methods.sync_private_state().simulate({ from: bob.getAddress() });

      await expectTokenBalances(token, escrow.instance.address, wad(0), halfAmount, bob);
      await expectTokenBalances(token, bob.getAddress(), wad(0), halfAmount, bob);

      const notes = await bobPxe.getNotes({ contractAddress: token.address, txHash: bobWithdrawTx.txHash });
      expect(notes.length).toBe(2);
      // PXE does not guarantee correct order
      if (notes[0].note.items[0].equals(new Fr(escrow.instance.address.toBigInt()))) {
        expectUintNote(notes[0], halfAmount, escrow.instance.address);
        expectUintNote(notes[1], halfAmount, bob.getAddress());
      } else {
        expectUintNote(notes[1], halfAmount, escrow.instance.address);
        expectUintNote(notes[0], halfAmount, bob.getAddress());
      }
    });

    it('withdrawing more than the balance should fail', async () => {
      await expect(
        logic
          .withWallet(bob)
          .methods.withdraw(escrow.instance.address, bob.getAddress(), token.instance.address, AMOUNT + 1n)
          .send({ from: bob.getAddress() })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low/);
    });
  });

  describe('withdraw NFT', () => {
    // Without resetting the store, the test fails with this error:
    // Simulation error: Array must contain at most 100 element(s) (0)
    // at SchnorrAccount.entrypoint
    beforeAll(async () => {
      await store.delete();
      await setup();
    });

    let nft: NFTContract;
    let tokenId: bigint;

    beforeEach(async () => {
      nft = (await deployNFTWithMinter(alice)) as NFTContract;
      tokenId = 1n;

      const partialAddressEscrow = await escrow.partialAddress;
      await pxe.registerAccount(escrowSk, partialAddressEscrow);

      await nft
        .withWallet(alice)
        .methods.mint_to_private(escrow.instance.address, tokenId)
        .send({ from: alice.getAddress() })
        .wait();
    });

    it('logic should be able to withdraw NFT correctly', async () => {
      const bobPxe = pxe;

      // Add bob to bob's PXE
      await bobPxe.registerAccount(bob.getSecretKey(), bob.getCompleteAddress().partialAddress);

      // Bob needs to register the escrow contract as an account
      const partialAddressEscrow = await escrow.partialAddress;
      await bobPxe.registerAccount(escrowSk, partialAddressEscrow);

      // Bob needs to sync his private state to see the escrow details
      await nft.withWallet(bob).methods.sync_private_state().simulate({ from: bob.getAddress() });

      await assertOwnsPrivateNFT(nft, tokenId, escrow.instance.address, true);
      await assertOwnsPrivateNFT(nft, tokenId, bob.getAddress(), false);

      const bobWithdrawTx = await logic
        .withWallet(bob)
        .methods.withdraw_nft(escrow.instance.address, bob.getAddress(), nft.instance.address, tokenId)
        .send({ from: bob.getAddress() })
        .wait();

      await nft.withWallet(bob).methods.sync_private_state().simulate({ from: bob.getAddress() });

      await assertOwnsPrivateNFT(nft, tokenId, escrow.instance.address, false);
      await assertOwnsPrivateNFT(nft, tokenId, bob.getAddress(), true);

      const notes = await bobPxe.getNotes({ contractAddress: nft.address, txHash: bobWithdrawTx.txHash });
      expect(notes.length).toBe(1);
      expectUintNote(notes[0], tokenId, bob.getAddress());
    });

    it('withdrawing non-existent NFT should fail', async () => {
      await expect(
        logic
          .withWallet(bob)
          .methods.withdraw_nft(escrow.instance.address, bob.getAddress(), nft.instance.address, tokenId + 1n)
          .send({ from: bob.getAddress() })
          .wait(),
      ).rejects.toThrow(/Assertion failed: nft not found in private to public/);
    });
  });
});
