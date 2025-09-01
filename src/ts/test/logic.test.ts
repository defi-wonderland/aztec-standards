import {
  ContractDeployer,
  Fr,
  TxStatus,
  getContractInstanceFromDeployParams,
  Contract,
  AccountWalletWithSecretKey,
  AccountWallet,
  PublicKeys,
  AztecAddress,
  GrumpkinScalar,
  getContractClassFromArtifact,
} from '@aztec/aztec.js';
import {
  computeInitializationHash,
  computeContractAddressFromInstance,
  computeSaltedInitializationHash,
} from '@aztec/stdlib/contract';
import { getDefaultInitializer } from '@aztec/stdlib/abi';
import { deriveKeys } from '@aztec/stdlib/keys';
import { setupPXE } from './utils.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { LogicContractArtifact, LogicContract, EscrowDetailsLogContent } from '../../../artifacts/Logic.js';
import { EscrowContractArtifact, EscrowContract } from '../../../artifacts/Escrow.js';

/**
 * Deploys the Logic contract.
 * @param deployer - The wallet to deploy the contract with.
 * @param escrowClassId - The class id of the escrow contract.
 * @returns A deployed contract instance.
 */
export async function deployLogicWithPublicKeys(publicKeys: PublicKeys, deployer: AccountWallet, escrowClassId: Fr) {
  const contract = await Contract.deployWithPublicKeys(
    publicKeys,
    deployer,
    LogicContractArtifact,
    [deployer.getAddress(), escrowClassId],
    'constructor',
  )
    .send()
    .deployed();
  return contract as LogicContract;
}

/**
 * Deploys the Escrow contract.
 * @param publicKeys - The public keys to use for the contract.
 * @param deployer - The wallet to deploy the contract with.
 * @param salt - The salt to use for the contract address. If not provided, a random salt will be used.
 * @returns A deployed contract instance.
 */
export async function deployEscrowWithPublicKeysAndSalt(
  publicKeys: PublicKeys,
  deployer: AccountWallet,
  salt: Fr = Fr.random(),
  args: unknown[] = [],
  constructor?: string,
): Promise<EscrowContract> {
  const contract = await Contract.deployWithPublicKeys(publicKeys, deployer, EscrowContractArtifact, args, constructor)
    .send({ contractAddressSalt: salt, universalDeploy: true })
    .deployed();
  return contract as EscrowContract;
}

/**
 * Predicts the contract address for a given artifact and constructor arguments.
 * @param artifact - The contract artifact.
 * @param constructorArgs - The arguments to pass to the constructor.
 * @param deployer - The address of the deployer.
 * @param salt - The salt to use for the contract address. If not provided, a random salt will be used.
 * @param publicKeys - The public keys to use for the contract.
 * @returns The predicted contract address.
 */
export async function deriveContractAddress(
  artifact: any,
  constructorArgs: any,
  deployer: AztecAddress = AztecAddress.ZERO,
  salt: Fr = Fr.random(),
  publicKeys: PublicKeys,
) {
  if (!publicKeys) {
    publicKeys = await PublicKeys.random();
  }

  const contractClass = await getContractClassFromArtifact(artifact);
  const contractClassId = contractClass.id;
  const constructorArtifact = getDefaultInitializer(artifact);
  const initializationHash = await computeInitializationHash(constructorArtifact, constructorArgs);
  const saltedInitializationHash = await computeSaltedInitializationHash({
    initializationHash,
    salt,
    deployer,
  });

  const address = await computeContractAddressFromInstance({
    originalContractClassId: contractClassId,
    saltedInitializationHash: saltedInitializationHash,
    publicKeys: publicKeys,
  });

  return { address, initializationHash, saltedInitializationHash };
}

export function grumpkinScalarToFr(scalar: GrumpkinScalar) {
  return new Fr(scalar.toBigInt());
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
  let logic: LogicContract;
  let logicSk: Fr;
  let logicKeys: {
    masterNullifierSecretKey: GrumpkinScalar;
    masterIncomingViewingSecretKey: GrumpkinScalar;
    masterOutgoingViewingSecretKey: GrumpkinScalar;
    masterTaggingSecretKey: GrumpkinScalar;
    publicKeys: PublicKeys;
  };
  let logicSecretKeys: Fr[];

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
  let secretKeys: Fr[];

  beforeAll(async () => {
    ({ pxe, deployer, wallets, store } = await setupTestSuite());

    [alice, bob, carl] = wallets;

    // Derive the keys for the logic contract
    logicSk = Fr.ONE;
    logicKeys = await deriveKeys(logicSk);
    logicSecretKeys = [
      grumpkinScalarToFr(logicKeys.masterNullifierSecretKey),
      grumpkinScalarToFr(logicKeys.masterIncomingViewingSecretKey),
      grumpkinScalarToFr(logicKeys.masterOutgoingViewingSecretKey),
      grumpkinScalarToFr(logicKeys.masterTaggingSecretKey),
    ];

    // Get the class id of the escrow contract
    escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

    // We default to a secret key of 1 for testing purposes
    escrowSk = Fr.ONE.add(Fr.ONE);

    // Derive the keys from the secret key
    escrowKeys = await deriveKeys(escrowSk);

    // Convert the keys to Fr
    secretKeys = [
      grumpkinScalarToFr(escrowKeys.masterNullifierSecretKey),
      grumpkinScalarToFr(escrowKeys.masterIncomingViewingSecretKey),
      grumpkinScalarToFr(escrowKeys.masterOutgoingViewingSecretKey),
      grumpkinScalarToFr(escrowKeys.masterTaggingSecretKey),
    ];
  });

  beforeEach(async () => {
    // // Logic is deployed with the public keys because it sends encrypted events to the recipient and with the escrow class id
    logic = (await deployLogicWithPublicKeys(logicKeys.publicKeys, alice, escrowClassId)) as LogicContract;

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
      const deploymentData = await getContractInstanceFromDeployParams(LogicContractArtifact, {
        constructorArtifact: 'constructor',
        constructorArgs: [alice.getAddress(), escrowClassId],
        salt: escrowSalt,
        deployer: alice.getAddress(),
      });

      const deployer = new ContractDeployer(LogicContractArtifact, alice, undefined, 'constructor');
      const tx = deployer.deploy(alice.getAddress(), escrowClassId).send({
        contractAddressSalt: escrowSalt,
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
      expect(contractMetadata.isContractPubliclyDeployed).toBeTruthy();
      expect(receiptAfterMined).toEqual(
        expect.objectContaining({
          status: TxStatus.SUCCESS,
        }),
      );

      expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
    }, 300_000);

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
    }, 300_000);
  });

  describe('secret_keys_to_public_keys', () => {
    it('logic derives public keys from private keys correctly', async () => {
      const circuitPublicKeys = await logic.methods
        .test_secret_keys_to_public_keys(secretKeys[0], secretKeys[1], secretKeys[2], secretKeys[3])
        .simulate();

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
    }, 300_000);

    it('logic key derivation should fail if the secret key is not correct', async () => {
      // We add 1 to the secret key to make it incorrect
      const circuitPublicKeys = await logic.methods
        .test_secret_keys_to_public_keys(
          secretKeys[0].add(Fr.ONE),
          secretKeys[1].add(Fr.ONE),
          secretKeys[2].add(Fr.ONE),
          secretKeys[3].add(Fr.ONE),
        )
        .simulate();

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
    }, 300_000);
  });

  describe('check_escrow', () => {
    it('logic should be able to check escrow correctly', async () => {
      await logic.methods.test_check_escrow(escrow.instance.address, secretKeys).simulate();
    });

    it('check escrow with incorrect secret keys should fail', async () => {
      // We add 1 to each secret key to make it incorrect
      let secretKeysPlusOne = secretKeys.map((sk) => sk.add(Fr.ONE));

      await expect(
        logic.methods.test_check_escrow(escrow.instance.address, secretKeysPlusOne).send().wait(),
      ).rejects.toThrow(/Assertion failed: Public keys do not match/);
    });

    it('check escrow with non zero deployer should fail', async () => {
      // Re-deploy the escrow contract with no universalDeploy
      escrow = (await Contract.deployWithPublicKeys(escrowKeys.publicKeys, alice, EscrowContractArtifact, [])
        .send({ contractAddressSalt: escrowSalt })
        .deployed()) as EscrowContract;

      await expect(logic.methods.test_check_escrow(escrow.instance.address, secretKeys).send().wait()).rejects.toThrow(
        /Assertion failed: Escrow deployer should be null/,
      );
    });

    it('check escrow with incorrect class id should fail', async () => {
      // Re-deploy the logic contract with an incorrect class id
      logic = (await deployLogicWithPublicKeys(
        logicKeys.publicKeys,
        alice,
        escrowClassId.add(Fr.ONE),
      )) as LogicContract;

      await expect(logic.methods.test_check_escrow(escrow.instance.address, secretKeys).send().wait()).rejects.toThrow(
        /Assertion failed: Escrow class id does not match/,
      );
    });

    it('check escrow with incorrect salt should fail', async () => {
      // Re-deploy the escrow contract with a different salt (different from the logic contract address)
      escrow = (await deployEscrowWithPublicKeysAndSalt(
        escrowKeys.publicKeys,
        alice,
        escrowSalt.add(Fr.ONE),
      )) as EscrowContract;

      await expect(logic.methods.test_check_escrow(escrow.instance.address, secretKeys).send().wait()).rejects.toThrow(
        /Assertion failed: Escrow salt should be equal to the this address/,
      );
    });

    // Testing non-zero initialization hash supposes there is an initialize function in the escrow contract
    // which is not the case for the current escrow contract
  });

  describe('share_escrow', () => {
    it('logic should be able to share escrow correctly', async () => {
      const alicePxe = pxe;
      await alicePxe.registerAccount(bob.getSecretKey(), bob.getCompleteAddress().partialAddress);

      // Register the logic contract as an account
      const partialAddress = await logic.partialAddress;
      await alicePxe.registerAccount(logicSk, partialAddress);

      // Share the escrow contract with bob
      const tx = await logic.methods
        .test_share_escrow(escrow.instance.address, secretKeys, bob.getAddress())
        .send()
        .wait();
      const blockNumber = tx.blockNumber!;

      const bobPxe = pxe;

      const events = await bobPxe.getPrivateEvents<EscrowDetailsLogContent>(
        logic.address,
        LogicContract.events.EscrowDetailsLogContent,
        blockNumber,
        1,
        [bob.getAddress()],
      );

      expect(events.length).toBe(1);

      const event = events[0];

      expect(event.escrow).toEqual(escrow.instance.address);
      expect(event.keys[0]).toEqual(escrowKeys.masterNullifierSecretKey.toBigInt());
      expect(event.keys[1]).toEqual(escrowKeys.masterIncomingViewingSecretKey.toBigInt());
      expect(event.keys[2]).toEqual(escrowKeys.masterOutgoingViewingSecretKey.toBigInt());
      expect(event.keys[3]).toEqual(escrowKeys.masterTaggingSecretKey.toBigInt());
    });

    it('share escrow with multiple recipients correctly', async () => {
      const alicePxe = pxe;

      // Register the logic contract as an account
      const partialAddress = await logic.partialAddress;
      await alicePxe.registerAccount(logicSk, partialAddress);

      // Share the escrow contract with bob
      const txForBob = await logic.methods
        .test_share_escrow(escrow.instance.address, secretKeys, bob.getAddress())
        .send()
        .wait();
      const blockNumberBob = txForBob.blockNumber!;

      const txForCarl = await logic.methods
        .test_share_escrow(escrow.instance.address, secretKeys, carl.getAddress())
        .send()
        .wait();
      const blockNumberCarl = txForCarl.blockNumber!;

      const numberOfBlocks = blockNumberCarl - blockNumberBob + 1;

      const bobPxe = pxe;

      // Get the events for both bob and carl from bob's pxe for simplicity
      const events = await bobPxe.getPrivateEvents<EscrowDetailsLogContent>(
        logic.address,
        LogicContract.events.EscrowDetailsLogContent,
        blockNumberBob,
        numberOfBlocks,
        [bob.getAddress(), carl.getAddress()],
      );

      expect(events.length).toBe(2);

      const eventForBob = events[0];
      expect(eventForBob.escrow).toEqual(escrow.instance.address);
      expect(eventForBob.keys[0]).toEqual(escrowKeys.masterNullifierSecretKey.toBigInt());
      expect(eventForBob.keys[1]).toEqual(escrowKeys.masterIncomingViewingSecretKey.toBigInt());
      expect(eventForBob.keys[2]).toEqual(escrowKeys.masterOutgoingViewingSecretKey.toBigInt());
      expect(eventForBob.keys[3]).toEqual(escrowKeys.masterTaggingSecretKey.toBigInt());

      const eventForCarl = events[1];
      expect(eventForCarl.escrow).toEqual(escrow.instance.address);
      expect(eventForCarl.keys[0]).toEqual(escrowKeys.masterNullifierSecretKey.toBigInt());
      expect(eventForCarl.keys[1]).toEqual(escrowKeys.masterIncomingViewingSecretKey.toBigInt());
      expect(eventForCarl.keys[2]).toEqual(escrowKeys.masterOutgoingViewingSecretKey.toBigInt());
      expect(eventForCarl.keys[3]).toEqual(escrowKeys.masterTaggingSecretKey.toBigInt());
    });
  });
});
