import { Note } from '@aztec/aztec.js/note';
import { createLogger } from '@aztec/aztec.js/log';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { Aes128 } from '@aztec/foundation/crypto/aes128';
import { deriveEcdhSharedSecret } from '@aztec/stdlib/logs';
import { type Wallet, AccountManager } from '@aztec/aztec.js/wallet';
import { Fr, type GrumpkinScalar, Point } from '@aztec/aztec.js/fields';
import { createAztecNodeClient, waitForNode } from '@aztec/aztec.js/node';
import { type ContractInstanceWithAddress } from '@aztec/aztec.js/contracts';
import { PRIVATE_LOG_CIPHERTEXT_LEN, GeneratorIndex } from '@aztec/constants';
import { poseidon2HashWithSeparator } from '@aztec/foundation/crypto/poseidon';
import { registerInitialLocalNetworkAccountsInWallet, TestWallet } from '@aztec/test-wallet/server';
import { deriveMasterIncomingViewingSecretKey, PublicKeys, computeAddressSecret } from '@aztec/stdlib/keys';

import {
  Contract,
  DeployOptions,
  ContractFunctionInteraction,
  getContractClassFromArtifact,
} from '@aztec/aztec.js/contracts';
import { AuthWitness, type ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';
import { getDefaultInitializer } from '@aztec/stdlib/abi';
import {
  CompleteAddress,
  computeInitializationHash,
  computeSaltedInitializationHash,
  computeContractAddressFromInstance,
} from '@aztec/stdlib/contract';

import { createStore } from '@aztec/kv-store/lmdb-v2';
import { getPXEConfig } from '@aztec/pxe/server';
import { type AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';

import { TokenContract, TokenContractArtifact } from '../../../artifacts/Token.js';
import { NFTContract, NFTContractArtifact } from '../../../artifacts/NFT.js';
import { TestLogicContractArtifact, TestLogicContract } from '../../../artifacts/TestLogic.js';
import { EscrowContractArtifact, EscrowContract } from '../../../artifacts/Escrow.js';

export const logger = createLogger('aztec:aztec-standards');

const { NODE_URL = 'http://localhost:8080' } = process.env;
const node = createAztecNodeClient(NODE_URL);
await waitForNode(node);
const { PXE_VERSION = '2' } = process.env;
const pxeVersion = parseInt(PXE_VERSION);
const l1Contracts = await node.getL1ContractAddresses();
const config = getPXEConfig();
let fullConfig = { ...config, l1Contracts };

/**
 * Setup the store, node, wallet and accounts
 * @param suffix - optional - The suffix to use for the store directory.
 * @param proverEnabled - optional - Whether to enable the prover, used for benchmarking.
 * @returns The store, node, wallet and accounts
 */
export const setupTestSuite = async (suffix?: string, proverEnabled: boolean = false) => {
  const storeDir = suffix ? `store-${suffix}` : 'store';

  fullConfig = { ...fullConfig, dataDirectory: storeDir, dataStoreMapSizeKb: 1e6 };

  // Create the store for manual cleanups
  const store: AztecLMDBStoreV2 = await createStore('pxe_data', pxeVersion, {
    dataDirectory: storeDir,
    dataStoreMapSizeKb: 1e6,
  });

  const wallet: TestWallet = await TestWallet.create(node, { ...fullConfig, proverEnabled }, { store });

  const accounts: AztecAddress[] = await registerInitialLocalNetworkAccountsInWallet(wallet);

  return {
    store,
    node,
    wallet,
    accounts,
  };
};

// --- Token Utils ---
export const expectUintNote = (note: Note, amount: bigint, owner: AztecAddress) => {
  expect(note.items[0]).toEqual(new Fr(amount));
};

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
  const contract = await Contract.deploy(
    wallet,
    TokenContractArtifact,
    ['PrivateToken', 'PT', 18, deployer, AztecAddress.ZERO],
    'constructor_with_minter',
  )
    .send({ ...options, from: deployer })
    .deployed();
  return contract;
}

/**
 * Deploys the Token contract with a specified initial supply.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The account to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployTokenWithInitialSupply(wallet: Wallet, deployer: AztecAddress, options?: DeployOptions) {
  const contract = await Contract.deploy(
    wallet,
    TokenContractArtifact,
    ['PrivateToken', 'PT', 18, 0, deployer, deployer],
    'constructor_with_initial_supply',
  )
    .send({ ...options, from: deployer })
    .deployed();
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
export async function deployNFTWithMinter(wallet: TestWallet, deployer: AztecAddress, options?: DeployOptions) {
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

// --- Tokenized Vault Utils ---

/**
 * Deploys the Token contract with a specified minter.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The account to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployVaultAndAssetWithMinter(
  wallet: Wallet,
  deployer: AztecAddress,
  options?: DeployOptions,
): Promise<[Contract, Contract]> {
  const assetContract = await Contract.deploy(
    wallet,
    TokenContractArtifact,
    ['PrivateToken', 'PT', 6, deployer, AztecAddress.ZERO],
    'constructor_with_minter',
  )
    .send({ ...options, from: deployer })
    .deployed();

  const vaultContract = await Contract.deploy(
    wallet,
    TokenContractArtifact,
    ['VaultToken', 'VT', 6, assetContract.address, AztecAddress.ZERO],
    'constructor_with_asset',
  )
    .send({ ...options, from: deployer })
    .deployed();

  return [vaultContract, assetContract];
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
  args: unknown[] = [],
  constructor?: string,
): Promise<{ contract: EscrowContract; instance: ContractInstanceWithAddress }> {
  const { contract, instance } = await Contract.deployWithPublicKeys(
    publicKeys,
    wallet,
    EscrowContractArtifact,
    args,
    constructor,
  )
    .send({ contractAddressSalt: salt, universalDeploy: true, from: deployer })
    .wait();
  return { contract: contract as EscrowContract, instance };
}

// --- General Utils ---

export async function setPrivateAuthWit(
  caller: AztecAddress,
  action: ContractFunctionInteraction,
  authorizer: AztecAddress,
  wallet: TestWallet,
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
  wallet: TestWallet,
) {
  const validateAction = await wallet.setPublicAuthWit(
    authorizer,
    {
      caller: caller,
      action: action,
    },
    true,
  );
  await validateAction.send().wait();
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
  const tx = await token.methods.initialize_transfer_commitment(to.address, completer).send({ from: caller }).wait();
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
  const tx = await nft.methods.initialize_transfer_commitment(to.address, completer).send({ from: caller }).wait();
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
  const contract = await Contract.deploy(wallet, TestLogicContractArtifact, [escrowClassId], 'constructor')
    .send({ from: deployer })
    .deployed();
  return contract as TestLogicContract;
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
  args: unknown[] = [],
  constructor?: string,
): Promise<EscrowContract> {
  const contract = await Contract.deployWithPublicKeys(publicKeys, wallet, EscrowContractArtifact, args, constructor)
    .send({ contractAddressSalt: salt, universalDeploy: true, from: deployer })
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

/**
 * Converts a GrumpkinScalar to an Fr.
 * @param scalar - The GrumpkinScalar to convert.
 * @returns The converted Fr.
 */
export function grumpkinScalarToFr(scalar: GrumpkinScalar) {
  return new Fr(scalar.toBigInt());
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
  const separator1 = kShift + GeneratorIndex.SYMMETRIC_KEY;
  const separator2 = kShift + GeneratorIndex.SYMMETRIC_KEY_2;

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
