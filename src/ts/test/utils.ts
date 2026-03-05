import { createLogger } from '@aztec/aztec.js/log';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { Aes128 } from '@aztec/foundation/crypto/aes128';
import { deriveEcdhSharedSecret } from '@aztec/stdlib/logs';
import { type Wallet, AccountManager } from '@aztec/aztec.js/wallet';
import { Fr, type GrumpkinScalar, Point } from '@aztec/aztec.js/fields';
import { createAztecNodeClient, waitForNode, type AztecNode } from '@aztec/aztec.js/node';
import { type ContractInstanceWithAddress } from '@aztec/aztec.js/contracts';
import { TxHash } from '@aztec/aztec.js/tx';
import { PRIVATE_LOG_CIPHERTEXT_LEN, DomainSeparator } from '@aztec/constants';
import { poseidon2HashWithSeparator } from '@aztec/foundation/crypto/poseidon';
import { EmbeddedWallet } from '@aztec/wallets/embedded';
import { registerInitialLocalNetworkAccountsInWallet } from '@aztec/wallets/testing';
import { deriveMasterIncomingViewingSecretKey, PublicKeys, computeAddressSecret } from '@aztec/stdlib/keys';

import {
  Contract,
  DeployOptions,
  ContractFunctionInteraction,
  getContractClassFromArtifact,
  getContractInstanceFromInstantiationParams,
} from '@aztec/aztec.js/contracts';
import {
  AuthWitness,
  SetPublicAuthwitContractInteraction,
  type ContractFunctionInteractionCallIntent,
} from '@aztec/aztec.js/authorization';
import { EventSelector, decodeFromAbi } from '@aztec/aztec.js/abi';
import { getDefaultInitializer, getInitializer } from '@aztec/stdlib/abi';
import {
  CompleteAddress,
  computeInitializationHash,
  computeSaltedInitializationHash,
  computeContractAddressFromInstance,
} from '@aztec/stdlib/contract';

import { getPXEConfig } from '@aztec/pxe/server';
import { Barretenberg } from '@aztec/bb.js';

import { TokenContract } from '../../../src/artifacts/Token.js';
import { VaultContract, VaultContractArtifact } from '../../../src/artifacts/Vault.js';
import { NFTContract } from '../../../src/artifacts/NFT.js';
import { TestLogicContract } from '../../../src/artifacts/TestLogic.js';
import { EscrowContract } from '../../../src/artifacts/Escrow.js';

import { expect } from 'vitest';

export const logger = createLogger('aztec:aztec-standards');

import { randomBytes } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { rmSync } from 'node:fs';

/** Default port for Aztec local network. */
export const LOCAL_NETWORK_DEFAULT_PORT = 8080;
export const DEFAULT_NODE_URL = `http://localhost:${LOCAL_NETWORK_DEFAULT_PORT}`;

/** Returns the Aztec node URL. Reads NODE_URL from env; defaults to localhost:8080. */
export function getNodeUrl(): string {
  return process.env.NODE_URL ?? DEFAULT_NODE_URL;
}

const node = createAztecNodeClient(getNodeUrl());
await waitForNode(node);
const config = getPXEConfig();

/**
 * Setup the node, wallet and accounts.
 * Lets createPXE handle store creation and l1Contracts fetching internally.
 * @param proverEnabled - optional - Whether to enable the prover, used for benchmarking.
 * @returns The node, wallet, accounts, and a cleanup function.
 */
export const setupTestSuite = async (proverEnabled: boolean = false) => {
  // Reset Barretenberg singleton so a fresh socket is created. Needed when aztec-benchmark's
  // cleanup destroys all sockets (including the prover's), causing EPIPE on the next benchmark.
  if (proverEnabled) {
    await Barretenberg.destroySingleton();
  }

  const dataDirectory = join(tmpdir(), `aztec-standards-${randomBytes(8).toString('hex')}`);
  const pxeConfig = { ...config, dataDirectory, proverEnabled };

  const wallet: EmbeddedWallet = await EmbeddedWallet.create(node, { pxeConfig });

  const accounts: AztecAddress[] = await registerInitialLocalNetworkAccountsInWallet(wallet);

  const cleanup = async () => {
    await wallet.stop();
    try {
      rmSync(dataDirectory, { recursive: true, force: true });
    } catch {
      // ignore cleanup errors
    }
  };

  return {
    node,
    wallet,
    accounts,
    cleanup,
  };
};

// --- Constants ---

// Maximum value for a u128 (2**128 - 1)
export const MAX_U128_VALUE = 340282366920938463463374607431768211455n;

// --- Token Utils ---

export const expectTokenBalances = async (
  token: TokenContract,
  address: AztecAddress,
  publicBalance: bigint | number | Fr,
  privateBalance: bigint | number | Fr,
  caller?: AztecAddress,
) => {
  const aztecAddress = address instanceof AztecAddress ? address : address;
  logger.info('checking balances for', aztecAddress.toString());
  // We can't use an account that is not in the wallet to simulate the balances, so we use the caller if provided.
  const from = caller ? caller : aztecAddress;

  // Helper to cast to bigint if not already
  const toBigInt = (val: bigint | number | Fr) => {
    if (typeof val === 'bigint') return val;
    if (typeof val === 'number') return BigInt(val);
    if (val instanceof Fr) return val.toBigInt();
    throw new Error('Unsupported type for balance');
  };

  expect(await token.methods.balance_of_public(aztecAddress).simulate({ from })).toBe(toBigInt(publicBalance));
  expect(await token.methods.balance_of_private(aztecAddress).simulate({ from })).toBe(toBigInt(privateBalance));
};

export const AMOUNT = 1000n;
export const wad = (n: number = 1) => AMOUNT * BigInt(n);

/**
 * Deploys the Token contract with a specified minter.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The account to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployTokenWithMinter(wallet: Wallet, deployer: AztecAddress, options?: DeployOptions) {
  const contract = await TokenContract.deployWithOpts(
    { method: 'constructor_with_minter', wallet },
    'PrivateToken',
    'PT',
    18,
    deployer,
  ).send({ ...options, from: deployer });
  return contract;
}

/**
 * Deploys the Token contract with a specified initial supply.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The account to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployTokenWithInitialSupply(wallet: Wallet, deployer: AztecAddress, options?: DeployOptions) {
  const contract = await TokenContract.deployWithOpts(
    { method: 'constructor_with_initial_supply', wallet },
    'PrivateToken',
    'PT',
    18,
    0,
    deployer,
  ).send({ ...options, from: deployer });
  return contract;
}

// --- NFT Utils ---

// Check if an address owns a specific NFT in public state
export async function assertOwnsPublicNFT(
  nft: NFTContract,
  tokenId: bigint,
  expectedOwner: AztecAddress,
  expectToBeTrue: boolean,
  caller?: AztecAddress,
) {
  const from = caller ? (caller instanceof AztecAddress ? caller : caller) : expectedOwner;
  const owner = await nft.methods.public_owner_of(tokenId).simulate({ from });
  expect(owner.equals(expectedOwner)).toBe(expectToBeTrue);
}

// Check if an address owns a specific NFT in private state
export async function assertOwnsPrivateNFT(
  nft: NFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  expectToBeTrue: boolean,
  caller?: AztecAddress,
) {
  const from = caller ? (caller instanceof AztecAddress ? caller : caller) : owner;
  const [nfts, _] = await nft.methods.get_private_nfts(owner, 0).simulate({ from });
  const hasNFT = nfts.some((id: bigint) => id === tokenId);
  expect(hasNFT).toBe(expectToBeTrue);
}

// Deploy NFT contract with a minter
export async function deployNFTWithMinter(wallet: EmbeddedWallet, deployer: AztecAddress, options?: DeployOptions) {
  const contract = await NFTContract.deployWithOpts(
    { method: 'constructor_with_minter', wallet },
    'TestNFT',
    'TNFT',
    deployer,
  ).send({ ...options, from: deployer });
  return contract;
}

// --- Vault Utils ---

/**
 * Deploys 3 contracts: asset token, shares token, and vault.
 * The vault is deployed first without initializer to get its address,
 * then the shares token is deployed with the vault as minter,
 * then the vault is initialized with asset and shares addresses.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The account to deploy the contract with.
 * @returns [vault, asset, shares] contract instances.
 */
export async function deployVaultAndAssetWithMinter(
  wallet: Wallet,
  deployer: AztecAddress,
  options?: DeployOptions,
): Promise<[VaultContract, TokenContract, TokenContract]> {
  // Deploy asset token with deployer as minter
  const assetContract = await TokenContract.deployWithOpts(
    { method: 'constructor_with_minter', wallet },
    'AssetToken',
    'AT',
    6,
    deployer,
  ).send({ ...options, from: deployer });

  // Precompute vault address (no shares needed — breaks circular dependency)
  const salt = Fr.random();
  const { address: vaultAddress } = await deriveContractAddressWithConstructor(
    VaultContractArtifact,
    'constructor',
    [deployer, assetContract.address, 1],
    deployer,
    salt,
  );

  // Deploy shares token with precomputed vault address as minter
  const sharesContract = await TokenContract.deployWithOpts(
    { method: 'constructor_with_minter', wallet },
    'SharesToken',
    'ST',
    18,
    vaultAddress,
    AztecAddress.ZERO,
  ).send({ ...options, from: deployer });

  // Deploy vault at precomputed address with #[initializer] constructor
  const vaultContract = await VaultContract.deploy(wallet, deployer, assetContract.address, 1).send({
    ...options,
    from: deployer,
    contractAddressSalt: salt,
  });

  // Set the shares token on the vault (admin-only, one-shot)
  await vaultContract.methods.set_shares_token(sharesContract.address).send({ from: deployer });

  return [vaultContract as VaultContract, assetContract as TokenContract, sharesContract as TokenContract];
}

/**
 * Deploys a vault with an optional initial deposit for inflation-attack protection.
 * Deploys 3 contracts: vault (without initializer), shares token (with vault as minter), then initializes vault.
 * If initialDeposit > 0, authorizes vault to transfer assets and deposits them.
 * @returns [vault, shares] contract instances.
 */
export async function deployVaultWithInitialDeposit(
  wallet: Wallet,
  deployer: AztecAddress,
  assetContract: TokenContract,
  initialDeposit: bigint,
  depositor: AztecAddress,
  options?: DeployOptions,
): Promise<[VaultContract, TokenContract]> {
  // Precompute vault address (no shares needed — breaks circular dependency)
  const salt = Fr.random();
  const { address: vaultAddress } = await deriveContractAddressWithConstructor(
    VaultContractArtifact,
    'constructor',
    [deployer, assetContract.address, 1],
    deployer,
    salt,
  );

  // Deploy shares token with precomputed vault address as minter
  const sharesContract = await TokenContract.deployWithOpts(
    { method: 'constructor_with_minter', wallet },
    'SharesToken',
    'ST',
    18,
    vaultAddress,
    AztecAddress.ZERO,
  ).send({ ...options, from: deployer });

  // Deploy vault at precomputed address with #[initializer] constructor
  const vaultContract = await VaultContract.deploy(wallet, deployer, assetContract.address, 1).send({
    ...options,
    from: deployer,
    contractAddressSalt: salt,
  });

  if (initialDeposit > 0n) {
    // Authorize vault to transfer assets from depositor
    const transfer = assetContract.methods.transfer_public_to_public(
      depositor,
      vaultContract.address,
      initialDeposit,
      0,
    );
    await setPublicAuthWit(vaultContract.address, transfer, depositor, wallet as EmbeddedWallet);

    // Set shares and make initial deposit
    await vaultContract.methods
      .set_shares_token_with_initial_deposit(sharesContract.address, initialDeposit, depositor, 0)
      .send({ from: deployer });
  } else {
    // Just set shares without initial deposit
    await vaultContract.methods.set_shares_token(sharesContract.address).send({ from: deployer });
  }

  return [vaultContract as VaultContract, sharesContract as TokenContract];
}

// --- Escrow Utils ---

/**
 * Deploys the Escrow contract.
 * @param publicKeys - The public keys to use for the contract.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The address to deploy the contract with.
 * @param salt - The salt to use for the contract address. If not provided, a random salt will be used.
 * @param args - The arguments to pass to the constructor.
 * @param constructor - The constructor to use for the contract.
 * @returns A deployed contract instance.
 */
export async function deployEscrow(
  publicKeys: PublicKeys,
  wallet: Wallet,
  deployer: AztecAddress,
  salt: Fr = Fr.random(),
): Promise<{ contract: EscrowContract; instance: ContractInstanceWithAddress }> {
  const contract = await EscrowContract.deployWithPublicKeys(publicKeys, wallet).send({
    contractAddressSalt: salt,
    universalDeploy: true,
    from: deployer,
  });

  // Get the instance from the node after deployment
  const instance = (await node.getContract(contract.address)) as ContractInstanceWithAddress;
  return { contract, instance };
}

// --- General Utils ---

export async function setPrivateAuthWit(
  caller: AztecAddress,
  action: ContractFunctionInteraction,
  authorizer: AztecAddress,
  wallet: EmbeddedWallet,
): Promise<AuthWitness> {
  const intent: ContractFunctionInteractionCallIntent = {
    caller: caller,
    action: action,
  };
  return wallet.createAuthWit(authorizer, intent);
}

export async function setPublicAuthWit(
  caller: AztecAddress,
  action: ContractFunctionInteraction,
  authorizer: AztecAddress,
  wallet: EmbeddedWallet,
) {
  const validateAction = await SetPublicAuthwitContractInteraction.create(
    wallet,
    authorizer,
    {
      caller: caller,
      action: action,
    },
    true,
  );
  await validateAction.send({ from: authorizer });
}

/**
 * Initializes a transfer commitment
 * @param token - The token contract instance.
 * @param caller - The wallet that will interact with the token contract.
 * @param to - The address of the recipient.
 * @param completer - The address allowed to complete the partial note.
 * @returns Partial note commitment
 */
export async function initializeTransferCommitment(
  token: TokenContract,
  caller: AztecAddress,
  to: AccountManager,
  completer: AztecAddress,
) {
  // Workaround because we could not get the commitment from the simulation, so we decrypt the private log instead
  const tx = await token.methods.initialize_transfer_commitment(to.address, completer).send({ from: caller });
  const txEffect = await node.getTxEffect(tx.txHash);
  if (!txEffect?.data.privateLogs) {
    throw new Error('No private logs found');
  }
  const privateLogs = txEffect?.data.privateLogs;

  const toSK = to.getSecretKey();
  const toIvskM = deriveMasterIncomingViewingSecretKey(toSK);

  const decryptedRawLog = await decryptRawPrivateLog(
    privateLogs[0].fields.slice(1),
    await to.getCompleteAddress(),
    toIvskM,
  );

  // The commitment is the fifth field in the decrypted raw log
  return decryptedRawLog[4].toBigInt();
}

/**
 * Initializes a transfer commitment for an NFT
 * @param nft - The token contract instance.
 * @param caller - The wallet that will interact with the token contract.
 * @param to - The address of the recipient.
 * @param completer - The address allowed to complete the partial note.
 * @returns Partial note commitment
 */
export async function initializeTransferCommitmentNFT(
  nft: NFTContract,
  caller: AztecAddress,
  to: AccountManager,
  completer: AztecAddress,
) {
  // Workaround because we could not get the commitment from the simulation, so we decrypt the private log instead
  const tx = await nft.methods.initialize_transfer_commitment(to.address, completer).send({ from: caller });
  const txEffect = await node.getTxEffect(tx.txHash);
  if (!txEffect?.data.privateLogs) {
    throw new Error('No private logs found');
  }
  const privateLogs = txEffect?.data.privateLogs;

  const toSK = to.getSecretKey();
  const toIvskM = deriveMasterIncomingViewingSecretKey(toSK);

  const decryptedRawLog = await decryptRawPrivateLog(
    privateLogs[0].fields.slice(1),
    await to.getCompleteAddress(),
    toIvskM,
  );

  // The commitment is the fifth field in the decrypted raw log
  return decryptedRawLog[4].toBigInt();
}

// --- Logic Contract Utils ---

/**
 * Deploys the Logic contract.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The address to deploy the contract with.
 * @param escrowClassId - The class id of the escrow contract.
 * @returns A deployed contract instance.
 */
export async function deployLogic(wallet: Wallet, deployer: AztecAddress, escrowClassId: Fr) {
  const contract = await TestLogicContract.deployWithOpts({ method: 'constructor', wallet }, escrowClassId).send({
    from: deployer,
  });

  return contract;
}

/**
 * Deploys the Escrow contract.
 * @param publicKeys - The public keys to use for the contract.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The wallet to deploy the contract with.
 * @param salt - The salt to use for the contract address. If not provided, a random salt will be used.
 * @param args - The arguments to pass to the constructor.
 * @param constructor - The constructor to use for the contract.
 * @returns A deployed contract instance.
 */
export async function deployEscrowWithPublicKeysAndSalt(
  publicKeys: PublicKeys,
  wallet: Wallet,
  deployer: AztecAddress,
  salt: Fr = Fr.random(),
): Promise<EscrowContract> {
  const contract = await EscrowContract.deployWithPublicKeys(publicKeys, wallet).send({
    contractAddressSalt: salt,
    universalDeploy: true,
    from: deployer,
  });
  return contract;
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

/**
 * Predicts the contract address for a given artifact with a specific constructor.
 * Uses the v4 API `getContractInstanceFromInstantiationParams` for address derivation.
 * @param artifact - The contract artifact.
 * @param constructorName - The name of the constructor function to use.
 * @param constructorArgs - The arguments to pass to the constructor.
 * @param deployer - The address of the deployer.
 * @param salt - The salt to use for the contract address.
 * @param publicKeys - The public keys to use for the contract.
 * @returns The predicted contract address and salt.
 */
export async function deriveContractAddressWithConstructor(
  artifact: any,
  constructorName: string,
  constructorArgs: any[],
  deployer: AztecAddress,
  salt: Fr = Fr.random(),
  publicKeys?: PublicKeys,
) {
  // Use v4 API for contract instance derivation
  const instance = await getContractInstanceFromInstantiationParams(artifact, {
    constructorArtifact: constructorName,
    constructorArgs,
    salt,
    deployer,
    publicKeys,
  });

  // For backward compatibility, compute initializationHash and saltedInitializationHash
  // if they're needed by callers (though currently only address is used)
  const constructorArtifact = getInitializer(artifact, constructorName);
  if (!constructorArtifact) {
    throw new Error(`Constructor ${constructorName} not found in artifact`);
  }

  const initializationHash = await computeInitializationHash(constructorArtifact, constructorArgs);
  const saltedInitializationHash = await computeSaltedInitializationHash({
    initializationHash,
    salt,
    deployer,
  });

  return {
    address: instance.address,
    salt,
    initializationHash,
    saltedInitializationHash,
  };
}

// --- Transfer Event Utils ---

/**
 * Sentinel address used in Transfer events to represent the private side of a balance change.
 * Must match the PRIVATE_ADDRESS_MAGIC_VALUE in the Noir contract:
 * sha224sum 'PRIVATE_ADDRESS'
 */
export const PRIVATE_ADDRESS = AztecAddress.fromBigInt(0x1ea7e01501975545617c2e694d931cb576b691a4a867fed81ebd3264n);

/** Represents a decoded Transfer event. */
export type TransferEvent = {
  from: AztecAddress;
  to: AztecAddress;
  amount: bigint;
};

/**
 * Queries the node for public logs emitted in a transaction by a specific contract,
 * and decodes them as Transfer events.
 *
 * @param txHash - The transaction hash to query logs for.
 * @param contractAddress - The contract address to filter logs by.
 * @returns An array of decoded TransferEvent objects.
 */
export async function getTransferEvents(txHash: TxHash, contractAddress: AztecAddress): Promise<TransferEvent[]> {
  const response = await node.getPublicLogs({
    txHash,
    contractAddress,
  });

  const eventMetadata = TokenContract.events.Transfer;

  return response.logs
    .filter((extLog) => {
      const logFields = extLog.log.getEmittedFields();
      // Match the Transfer event selector (last field)
      return EventSelector.fromField(logFields[logFields.length - 1]).equals(eventMetadata.eventSelector);
    })
    .map((extLog) => {
      return decodeFromAbi([eventMetadata.abiType], extLog.log.fields) as TransferEvent;
    });
}

/**
 * Asserts that the Transfer events emitted by a specific contract in a transaction
 * match the expected events exactly (count and content, order-sensitive).
 *
 * Comment convention above expectTransferEvents calls: `operation: [emitter ]Transfer(from, to, amount)[ + ...]`
 * - Single emitter: `// mint_to_public: Transfer(0x0, alice, AMOUNT)`
 * - Multi-emitter: `// deposit_public_to_public: asset Transfer(from, vault, assets) + vault Transfer(0x0, to, shares)`
 * - No events: `// transfer_private_to_private: (no public events)`
 *
 * @param txHash - The transaction hash to query logs for.
 * @param contractAddress - The contract address to filter logs by.
 * @param expected - The expected Transfer events in order.
 */
export async function expectTransferEvents(
  txHash: TxHash,
  contractAddress: AztecAddress,
  expected: TransferEvent[],
): Promise<void> {
  const events = await getTransferEvents(txHash, contractAddress);

  expect(events.length).toBe(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(events[i].from).toEqual(expected[i].from);
    expect(events[i].to).toEqual(expected[i].to);
    expect(events[i].amount).toEqual(expected[i].amount);
  }
}

// --- NFT Transfer Event Utils ---

/** Represents a decoded NFT Transfer event. */
export type NFTTransferEvent = {
  from: AztecAddress;
  to: AztecAddress;
  token_id: bigint;
};

/**
 * Queries the node for public logs emitted in a transaction by a specific NFT contract,
 * and decodes them as Transfer events.
 *
 * @param txHash - The transaction hash to query logs for.
 * @param contractAddress - The NFT contract address to filter logs by.
 * @returns An array of decoded NFTTransferEvent objects.
 */
export async function getNFTTransferEvents(txHash: TxHash, contractAddress: AztecAddress): Promise<NFTTransferEvent[]> {
  const response = await node.getPublicLogs({
    txHash,
    contractAddress,
  });

  const eventMetadata = NFTContract.events.Transfer;

  return response.logs
    .filter((extLog) => {
      const logFields = extLog.log.getEmittedFields();
      // Match the Transfer event selector (last field)
      return EventSelector.fromField(logFields[logFields.length - 1]).equals(eventMetadata.eventSelector);
    })
    .map((extLog) => {
      return decodeFromAbi([eventMetadata.abiType], extLog.log.fields) as NFTTransferEvent;
    });
}

/**
 * Asserts that the Transfer events emitted by a specific NFT contract in a transaction
 * match the expected events exactly (count and content, order-sensitive).
 *
 * Comment convention above expectNFTTransferEvents calls: `operation: Transfer(from, to, tokenId)`
 * - Mint to public:   `// mint_to_public: Transfer(0x0, alice, TOKEN_ID)`
 * - Mint to private:  `// mint_to_private: Transfer(0x0, PRIVATE, TOKEN_ID)`
 * - No events:        `// transfer_private_to_commitment: (no public events)`
 *
 * @param txHash - The transaction hash to query logs for.
 * @param contractAddress - The NFT contract address to filter logs by.
 * @param expected - The expected Transfer events in order.
 */
export async function expectNFTTransferEvents(
  txHash: TxHash,
  contractAddress: AztecAddress,
  expected: NFTTransferEvent[],
): Promise<void> {
  const events = await getNFTTransferEvents(txHash, contractAddress);

  expect(events.length).toBe(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(events[i].from).toEqual(expected[i].from);
    expect(events[i].to).toEqual(expected[i].to);
    expect(events[i].token_id).toEqual(expected[i].token_id);
  }
}

// Private Log Utils ---

// Constants from Noir code
const EPH_PK_X_SIZE_IN_FIELDS = 1;
const EPH_PK_SIGN_BYTE_SIZE_IN_BYTES = 1;
const HEADER_CIPHERTEXT_SIZE_IN_BYTES = 16;
const MESSAGE_CIPHERTEXT_LEN = PRIVATE_LOG_CIPHERTEXT_LEN; // 17

/**
 * Converts fields to bytes (31 bytes per field for ciphertext encoding)
 */
function fieldsToBytes(fields: Fr[]): Buffer {
  const bytes: number[] = [];
  for (const field of fields) {
    const fieldBytes = field.toBuffer();
    // Each field stores 31 bytes (not 32) in ciphertext encoding
    // We need to extract the last 31 bytes (big-endian, so skip the first byte)
    for (let i = 1; i < 32; i++) {
      bytes.push(fieldBytes[i]);
    }
  }
  return Buffer.from(bytes);
}

/**
 * Converts bytes to fields (32 bytes per field for plaintext)
 */
function bytesToFields(bytes: Buffer): Fr[] {
  const fields: Fr[] = [];
  // Each field is 32 bytes
  for (let i = 0; i < bytes.length; i += 32) {
    const fieldBytes = bytes.slice(i, i + 32);
    fields.push(Fr.fromBuffer(fieldBytes));
  }
  return fields;
}

/**
 * Derives AES symmetric key and IV from ECDH shared secret using Poseidon2
 */
async function deriveAesSymmetricKeyAndIv(
  sharedSecret: Point,
  index: number,
): Promise<{ key: Uint8Array; iv: Uint8Array }> {
  // Generate two random 256-bit values using Poseidon2 with different separators
  const kShift = index << 8;
  const separator1 = kShift + DomainSeparator.SYMMETRIC_KEY;
  const separator2 = kShift + DomainSeparator.SYMMETRIC_KEY_2;

  const rand1 = await poseidon2HashWithSeparator([sharedSecret.x, sharedSecret.y], separator1);
  const rand2 = await poseidon2HashWithSeparator([sharedSecret.x, sharedSecret.y], separator2);

  const rand1Bytes = rand1.toBuffer();
  const rand2Bytes = rand2.toBuffer();

  // Extract the last 16 bytes from each (little end of big-endian representation)
  const key = new Uint8Array(16);
  const iv = new Uint8Array(16);

  for (let i = 0; i < 16; i++) {
    // Take bytes from the "little end" of the be-bytes arrays
    key[i] = rand1Bytes[31 - i];
    iv[i] = rand2Bytes[31 - i];
  }

  return { key, iv };
}

/**
 * Decrypts a raw log ciphertext.
 *
 * This function decrypts an encrypted message using AES-128-CBC, following the same
 * algorithm as the Noir `decrypt_raw_log` function.
 *
 * @param ciphertext - Array of 17 fields representing the encrypted message
 * @param recipientCompleteAddress - Complete address of the recipient (needed for address secret computation)
 * @param recipientIvskM - The incoming viewing secret key of the recipient
 * @returns Array of decrypted fields
 */
export async function decryptRawPrivateLog(
  ciphertext: Fr[],
  recipientCompleteAddress: CompleteAddress,
  recipientIvskM: GrumpkinScalar,
): Promise<Fr[]> {
  if (ciphertext.length !== MESSAGE_CIPHERTEXT_LEN) {
    throw new Error(`Ciphertext must be ${MESSAGE_CIPHERTEXT_LEN} fields, got ${ciphertext.length}`);
  }

  // Extract ephemeral public key x-coordinate (first field)
  const ephPkX = ciphertext[0];

  // Get ciphertext without ephemeral public key x-coordinate
  const ciphertextWithoutEphPkX = ciphertext.slice(EPH_PK_X_SIZE_IN_FIELDS);

  // Convert fields to bytes (31 bytes per field)
  const ciphertextBytes = fieldsToBytes(ciphertextWithoutEphPkX);

  // Extract ephemeral public key sign (first byte)
  const ephPkSignByte = ciphertextBytes[0];
  const ephPkSign = ephPkSignByte !== 0;

  // Reconstruct ephemeral public key from x-coordinate and sign
  const ephPk = await Point.fromXAndSign(ephPkX, ephPkSign);

  // Derive shared secret
  // The shared secret is computed as: addressSecret * ephPk
  // where addressSecret = preaddress + ivskM (with proper sign handling)
  const preaddress = await recipientCompleteAddress.getPreaddress();
  const addressSecret = await computeAddressSecret(preaddress, recipientIvskM);
  const sharedSecret = await deriveEcdhSharedSecret(addressSecret, ephPk);

  // Derive symmetric keys for header and body
  const headerKeyIv = await deriveAesSymmetricKeyAndIv(sharedSecret, 1);
  const bodyKeyIv = await deriveAesSymmetricKeyAndIv(sharedSecret, 0);

  // Extract and decrypt header ciphertext
  const headerStart = EPH_PK_SIGN_BYTE_SIZE_IN_BYTES;
  const headerCiphertext = new Uint8Array(
    ciphertextBytes.slice(headerStart, headerStart + HEADER_CIPHERTEXT_SIZE_IN_BYTES),
  );

  const aes128 = new Aes128();
  const headerPlaintext = await aes128.decryptBufferCBC(headerCiphertext, headerKeyIv.iv, headerKeyIv.key);

  // Extract ciphertext length from header (2 bytes, big-endian)
  const ciphertextLength = (headerPlaintext[0] << 8) | headerPlaintext[1];

  // Extract and decrypt main ciphertext
  const ciphertextStart = headerStart + HEADER_CIPHERTEXT_SIZE_IN_BYTES;
  const ciphertextWithPadding = new Uint8Array(ciphertextBytes.slice(ciphertextStart));
  const actualCiphertext = ciphertextWithPadding.slice(0, ciphertextLength);

  const plaintextBytes = await aes128.decryptBufferCBC(actualCiphertext, bodyKeyIv.iv, bodyKeyIv.key);

  // Convert plaintext bytes back to fields (32 bytes per field)
  const plaintextFields = bytesToFields(plaintextBytes);

  return plaintextFields;
}
