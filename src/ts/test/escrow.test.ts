import { TxStatus } from '@aztec/aztec.js/tx';
import { deriveKeys } from '@aztec/stdlib/keys';
import { PublicKeys } from '@aztec/aztec.js/keys';
import { type AztecNode } from '@aztec/aztec.js/node';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
import { BlockNumber } from '@aztec/foundation/branded-types';
import { ContractDeployer } from '@aztec/aztec.js/deployment';
import { type AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import { Fr, type GrumpkinScalar, Point } from '@aztec/aztec.js/fields';
import {
  getContractInstanceFromInstantiationParams,
  getContractClassFromArtifact,
  type ContractInstanceWithAddress,
} from '@aztec/aztec.js/contracts';

import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';

import {
  TestLogicContractArtifact,
  TestLogicContract,
  EscrowDetailsLogContent,
} from '../../../src/artifacts/TestLogic.js';
import { EscrowContractArtifact, EscrowContract } from '../../../src/artifacts/Escrow.js';
import { TokenContract } from '../../../src/artifacts/Token.js';
import { NFTContract } from '../../../src/artifacts/NFT.js';

import {
  setupTestSuite,
  deployTokenWithMinter,
  AMOUNT,
  expectTokenBalances,
  wad,
  deployNFTWithMinter,
  assertOwnsPrivateNFT,
  deployLogic,
  deployEscrowWithPublicKeysAndSalt,
  deriveContractAddress,
} from './utils.js';

type FrInput = Fr | bigint | number | boolean | Buffer;

type NoirWrappedPoint = {
  inner: {
    x: FrInput;
    y: FrInput;
    is_infinite?: boolean;
  };
};

const noirWrappedPointToPoint = (wrapped: NoirWrappedPoint) =>
  new Point(new Fr(wrapped.inner.x), new Fr(wrapped.inner.y), !!wrapped.inner.is_infinite);

describe('Escrow', () => {
  let store: AztecLMDBStoreV2;
  let node: AztecNode;

  let wallet: TestWallet;
  let accounts: AztecAddress[];

  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  // Logic contract (used to interact with escrow)
  let logic: TestLogicContract;

  // Escrow contract
  let escrow: EscrowContract;
  let escrowInstance: ContractInstanceWithAddress;
  let escrowSk: Fr;
  let escrowKeys: {
    masterNullifierHidingKey: GrumpkinScalar;
    masterIncomingViewingSecretKey: GrumpkinScalar;
    masterOutgoingViewingSecretKey: GrumpkinScalar;
    masterTaggingSecretKey: GrumpkinScalar;
    publicKeys: PublicKeys;
  };
  let escrowSalt: Fr;
  let escrowClassId: Fr;

  beforeAll(async () => {
    ({ store, node, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;

    // Get the class id of the escrow contract
    escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

    // We default to a secret key of 1 for testing purposes
    escrowSk = Fr.ONE;

    // Derive the keys from the secret key (for deployment and verification)
    escrowKeys = await deriveKeys(escrowSk);
  });

  beforeEach(async () => {
    // Logic is deployed with the public keys because it sends encrypted events to the recipient and with the escrow class id
    logic = (await deployLogic(wallet, alice, escrowClassId)) as TestLogicContract;

    // Use the logic contract address as the salt for the escrow contract
    escrowSalt = new Fr(logic.address.toBigInt());

    // Deploy an escrow contract
    escrow = (await deployEscrowWithPublicKeysAndSalt(
      escrowKeys.publicKeys,
      wallet,
      alice,
      escrowSalt,
    )) as EscrowContract;

    escrowInstance = (await node.getContract(escrow.address)) as ContractInstanceWithAddress;
    if (escrowInstance) {
      await wallet.registerContract(escrowInstance, EscrowContractArtifact);
    }
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('Deployment', () => {
    it('deploys escrow logic contract with correct constructor params', async () => {
      const deploymentData = await getContractInstanceFromInstantiationParams(TestLogicContractArtifact, {
        constructorArtifact: 'constructor',
        constructorArgs: [escrowClassId],
        salt: escrowSalt,
        deployer: alice,
      });

      const deployer = new ContractDeployer(TestLogicContractArtifact, wallet, undefined, 'constructor');
      const contract = await deployer.deploy(escrowClassId).send({
        contractAddressSalt: escrowSalt,
        from: alice,
      });

      const contractMetadata = await wallet.getContractMetadata(deploymentData.address);
      expect(contractMetadata).toBeDefined();
      expect(contractMetadata.isContractPublished).toBeTruthy();

      expect(contract.address).toEqual(deploymentData.address);
    });

    it('deploys escrow with correctly derived address', async () => {
      const { address, initializationHash } = await deriveContractAddress(
        EscrowContractArtifact,
        [], // constructor args are null
        AztecAddress.ZERO, // deployer is null
        escrowSalt,
        escrowKeys.publicKeys,
      );

      expect(address).toEqual(escrow.address);
      expect(initializationHash).toEqual(Fr.ZERO);
      expect(initializationHash).toEqual(escrowInstance.initializationHash);
    });
  });

  describe('secret_keys_to_public_keys', () => {
    it('derives escrow public keys from secret key correctly', async () => {
      const circuitPublicKeys = await logic.methods.secret_keys_to_public_keys(escrowSk).simulate({ from: alice });

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
  });

  describe('get_escrow', () => {
    it('should be able to get escrow address correctly', async () => {
      const escrow_address = await logic.methods.get_escrow(escrowSk).simulate({ from: alice });

      const publicKeys = await logic.methods.secret_keys_to_public_keys(escrowSk).simulate({ from: alice });
      const publicKeysObj = new PublicKeys(
        noirWrappedPointToPoint(publicKeys.npk_m),
        noirWrappedPointToPoint(publicKeys.ivpk_m),
        noirWrappedPointToPoint(publicKeys.ovpk_m),
        noirWrappedPointToPoint(publicKeys.tpk_m),
      );
      const escrow_instance = await getContractInstanceFromInstantiationParams(EscrowContractArtifact, {
        salt: escrowSalt,
        publicKeys: publicKeysObj,
      });

      expect(escrow_address).toEqual(escrow_instance.address);
    });

    it('get escrow with non zero deployer should fail', async () => {
      const escrow_address = await logic.methods.get_escrow(escrowSk).simulate({ from: alice });

      const publicKeys = await logic.methods.secret_keys_to_public_keys(escrowSk).simulate({ from: alice });
      const publicKeysObj = new PublicKeys(
        noirWrappedPointToPoint(publicKeys.npk_m),
        noirWrappedPointToPoint(publicKeys.ivpk_m),
        noirWrappedPointToPoint(publicKeys.ovpk_m),
        noirWrappedPointToPoint(publicKeys.tpk_m),
      );
      const incorrect_escrow_instance = await getContractInstanceFromInstantiationParams(EscrowContractArtifact, {
        salt: escrowSalt,
        publicKeys: publicKeysObj,
        deployer: alice,
      });

      expect(escrow_address).not.toEqual(incorrect_escrow_instance.address);
    });

    it('get escrow with incorrect salt should fail', async () => {
      const escrow_address = await logic.methods.get_escrow(escrowSk).simulate({ from: alice });

      const publicKeys = await logic.methods.secret_keys_to_public_keys(escrowSk).simulate({ from: alice });
      const publicKeysObj = new PublicKeys(
        noirWrappedPointToPoint(publicKeys.npk_m),
        noirWrappedPointToPoint(publicKeys.ivpk_m),
        noirWrappedPointToPoint(publicKeys.ovpk_m),
        noirWrappedPointToPoint(publicKeys.tpk_m),
      );
      const incorrect_escrow_instance = await getContractInstanceFromInstantiationParams(EscrowContractArtifact, {
        salt: new Fr(1),
        publicKeys: publicKeysObj,
      });

      expect(escrow_address).not.toEqual(incorrect_escrow_instance.address);
    });

    // Testing non-zero initialization hash supposes there is an initialize function in the escrow contract
    // which is not the case for the current escrow contract
  });

  describe('share_escrow', () => {
    it('should be able to share escrow correctly', async () => {
      // Share the escrow contract with bob
      const tx = await logic.methods.share_escrow(bob, escrow.address, escrowSk).send({ from: alice });
      const blockNumber = tx.blockNumber!;

      const events = await wallet.getPrivateEvents<EscrowDetailsLogContent>(
        TestLogicContract.events.EscrowDetailsLogContent,
        {
          contractAddress: logic.address,
          fromBlock: blockNumber,
          scopes: [bob],
        },
      );

      expect(events.length).toBe(1);

      const event = events[0].event;

      expect(event.escrow).toEqual(escrow.address);
      expect(event.secret_key).toEqual(escrowSk.toBigInt());
    });

    it('share escrow with multiple recipients correctly', async () => {
      // Share the escrow contract with bob
      const txForBob = await logic.methods.share_escrow(bob, escrow.address, escrowSk).send({ from: alice });
      const blockNumberBob = txForBob.blockNumber!;

      const txForCarl = await logic.methods.share_escrow(carl, escrow.address, escrowSk).send({ from: alice });
      const blockNumberCarl = txForCarl.blockNumber!;

      const numberOfBlocks = blockNumberCarl - blockNumberBob + 1;

      // Get the events for both bob and carl from bob's wallet for simplicity
      const events = await wallet.getPrivateEvents<EscrowDetailsLogContent>(
        TestLogicContract.events.EscrowDetailsLogContent,
        {
          contractAddress: logic.address,
          fromBlock: blockNumberBob,
          toBlock: BlockNumber(blockNumberBob + numberOfBlocks),
          scopes: [bob, carl],
        },
      );

      expect(events.length).toBe(2);

      const eventForBob = events[0].event;
      expect(eventForBob.escrow).toEqual(escrow.address);
      expect(eventForBob.secret_key).toEqual(escrowSk.toBigInt());

      const eventForCarl = events[1].event;
      expect(eventForCarl.escrow).toEqual(escrow.address);
      expect(eventForCarl.secret_key).toEqual(escrowSk.toBigInt());
    });
  });

  describe('withdraw', () => {
    let token: TokenContract;

    beforeEach(async () => {
      token = (await deployTokenWithMinter(wallet, alice)) as TokenContract;

      await wallet.registerContract(escrowInstance, EscrowContractArtifact, escrowSk);

      await token.withWallet(wallet).methods.mint_to_private(escrow.address, AMOUNT).send({ from: alice });
    });

    it('should be able to withdraw from escrow correctly', async () => {
      const privateBalance = await token.methods.balance_of_private(escrow.address).simulate({ from: bob });

      await expectTokenBalances(token, escrow.address, wad(0), AMOUNT, bob);
      await expectTokenBalances(token, bob, wad(0), wad(0), bob);

      await logic.withWallet(wallet).methods.withdraw(escrow.address, bob, token.address, AMOUNT).send({ from: bob });

      await expectTokenBalances(token, escrow.address, wad(0), wad(0), bob);
      await expectTokenBalances(token, bob, wad(0), AMOUNT, bob);
    });
  });

  describe('withdraw NFT', () => {
    // Without resetting the store, the test fails with this error:
    // Simulation error: Array must contain at most 100 element(s) (0)
    // at SchnorrAccount.entrypoint
    beforeAll(async () => {
      await store.delete();
      ({ store, node, wallet, accounts } = await setupTestSuite());

      [alice, bob, carl] = accounts;

      // Get the class id of the escrow contract
      escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

      // We default to a secret key of 1 for testing purposes
      escrowSk = Fr.ONE;

      // Derive the keys from the secret key
      escrowKeys = await deriveKeys(escrowSk);
    });

    let nft: NFTContract;
    let tokenId: bigint;

    beforeEach(async () => {
      nft = (await deployNFTWithMinter(wallet, alice)) as NFTContract;
      tokenId = 1n;

      await wallet.registerContract(escrowInstance, EscrowContractArtifact, escrowSk);

      await nft.withWallet(wallet).methods.mint_to_private(escrow.address, tokenId).send({ from: alice });
    });

    it('should be able to withdraw NFT from escrow correctly', async () => {
      await assertOwnsPrivateNFT(nft, tokenId, escrow.address, true);
      await assertOwnsPrivateNFT(nft, tokenId, bob, false);

      await logic
        .withWallet(wallet)
        .methods.withdraw_nft(escrow.address, bob, nft.address, tokenId)
        .send({ from: bob });

      await assertOwnsPrivateNFT(nft, tokenId, escrow.address, false);
      await assertOwnsPrivateNFT(nft, tokenId, bob, true);
    });
  });
});
