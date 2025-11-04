import { Fr } from '@aztec/aztec.js/fields';
import { UniqueNote } from '@aztec/aztec.js/note';
import { createLogger } from '@aztec/aztec.js/log';
import type { AccountManager, Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { createAztecNodeClient, waitForNode } from '@aztec/aztec.js/node';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';
import { registerInitialSandboxAccountsInWallet, TestWallet } from '@aztec/test-wallet/server';
import { AuthWitness, SetPublicAuthwitContractInteraction } from '@aztec/aztec.js/authorization';
import { Contract, DeployOptions, ContractFunctionInteraction } from '@aztec/aztec.js/contracts';
import type { PXE } from '@aztec/pxe/server';
import { createStore } from '@aztec/kv-store/lmdb-v2';
import { createPXE, getPXEConfig } from '@aztec/pxe/server';
import type { AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';

// Imports addede for testing the commitment computation
import { decodeFromAbi } from '@aztec/stdlib/abi';
import { GeneratorIndex } from '@aztec/constants';
import { poseidon2HashWithSeparator } from '@aztec/foundation/crypto';

import { TokenContract, TokenContractArtifact } from '../../../artifacts/Token.js';
import { NFTContractArtifact } from '../../../artifacts/NFT.js';

export const logger = createLogger('aztec:aztec-standards');

const { NODE_URL = 'http://localhost:8080' } = process.env;
const node = createAztecNodeClient(NODE_URL);
const { PXE_VERSION = '2' } = process.env;
const pxeVersion = parseInt(PXE_VERSION);
const l1Contracts = await node.getL1ContractAddresses();
const config = getPXEConfig();
const fullConfig = { ...config, l1Contracts };
fullConfig.proverEnabled = false;

export const setupPXE = async () => {
  const store: AztecLMDBStoreV2 = await createStore('pxe', pxeVersion, {
    dataDirectory: 'store',
    dataStoreMapSizeKb: 1e6,
  });
  const pxe: PXE = await createPXE(node, fullConfig, { store });
  await waitForNode(node);
  return { pxe, store };
};

export const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const aztecNode = createAztecNodeClient(NODE_URL);
  const wallet: TestWallet = await TestWallet.create(aztecNode);
  const accounts: AztecAddress[] = await registerInitialSandboxAccountsInWallet(wallet);

  return {
    pxe,
    store,
    wallet,
    accounts,
  };
};

// --- Token Utils ---
export const expectUintNote = (note: UniqueNote, amount: bigint, owner: AztecAddress) => {
  expect(note.note.items[0]).toEqual(new Fr(owner.toBigInt()));
  expect(note.note.items[2]).toEqual(new Fr(amount));
};

export const expectTokenBalances = async (
  token: TokenContract,
  address: AztecAddress | { getAddress: () => AztecAddress },
  publicBalance: bigint | number | Fr,
  privateBalance: bigint | number | Fr,
  caller?: AztecAddress | { getAddress: () => AztecAddress },
) => {
  const aztecAddress = address instanceof AztecAddress ? address : address.getAddress();
  logger.info('checking balances for', aztecAddress.toString());
  // We can't use an account that is not in the wallet to simulate the balances, so we use the caller if provided.
  const from = caller ? (caller instanceof AztecAddress ? caller : caller.getAddress()) : aztecAddress;

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

/**
 * Deploys the NFT contract with a specified minter.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The account to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployNFTWithMinter(wallet: Wallet, deployer: AztecAddress, options?: DeployOptions) {
  const contract = await Contract.deploy(
    wallet,
    NFTContractArtifact,
    ['NFT', 'NFT', deployer, deployer],
    'constructor_with_minter',
  )
    .send({ ...options, from: deployer })
    .deployed();
  return contract;
}

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
 * @param from - The address of the sender.
 * @param to - The address of the recipient.
 * @param completer - The address allowed to complete the partial note.
 * @returns Partial note commitment
 */
export async function initializeTransferCommitment(
  wallet: TestWallet,
  token: TokenContract,
  caller: AztecAddress,
  to: AztecAddress,
  completer: AztecAddress,
  accountManager: AccountManager,
) {
  const fn_interaction = token.methods.initialize_transfer_commitment(to, completer);

  // Create the request ONCE with the same options you'll use everywhere
  const req = await fn_interaction.request();

  // Simulate using the exact same request
  const sim = await wallet.simulateTx(req, {
    from: caller,
    skipTxValidation: undefined,
    skipFeeEnforcement: true,
  });
  // Extract the commitment from simulation result
  const fnAbi = TokenContract.artifact.functions.find((f) => f.name === 'initialize_transfer_commitment')!;
  const rawReturnValues = sim.getPrivateReturnValues().nested[0]?.values || sim.getPrivateReturnValues().values;
  const simCommitment = decodeFromAbi(fnAbi.returnTypes, rawReturnValues as Fr[]);

  // Prove using the EXACT SAME request
  const proof = await wallet.proveTx(req, { from: caller });
  const tx = await proof.send().wait();
  await wallet.getTxReceipt(tx.txHash);

  const txEffect = await node.getTxEffect(tx.txHash);
  if (!txEffect?.data.privateLogs) {
    throw new Error('No private logs found');
  }
  const privateLogs = txEffect?.data.privateLogs;

  const noirDecryptedLog = await token
    .withWallet(wallet)
    .methods.decrypt_raw_log(privateLogs[0].fields.slice(1), to)
    .simulate({ from: caller });
  const computedCommitment = await computePartialCommitmentFromParts(
    noirDecryptedLog[1],
    noirDecryptedLog[3],
    noirDecryptedLog[4],
  );

  // Added this utility function in the token contract to decrypt the raw log, this is used to decrypt the private logs and get the commitment from the decrypted log
  /*
    Added an utility function in the token contract to decrypt the raw log, this is used to decrypt the private logs and get the commitment from the decrypted log

    use aztec::messages::encryption::{aes128::AES128, message_encryption::MessageEncryption},

    #[external("utility")]
    unconstrained fn decrypt_raw_log(ciphertext: [Field; 17], recipient: AztecAddress) -> [Field; 14] {
        let message_ciphertext = BoundedVec::from_array(ciphertext);
        let plaintext = AES128::decrypt(message_ciphertext, recipient);
        plaintext.storage()
    }
  */

  console.log(
    `X: ${noirDecryptedLog[0].toString(16)}\n
    STORAGE SLOT: ${noirDecryptedLog[1].toString(16)}\n
    COMMITMENT: ${noirDecryptedLog[2].toString(16)}\n
    TO: ${noirDecryptedLog[3].toString(16)}\n
    RANDOMNESS: ${noirDecryptedLog[4].toString(16)}`,
  );

  const secretKey = accountManager.getSecretKey();
  const recipientIvskM = deriveMasterIncomingViewingSecretKey(secretKey);

  const decryptedRawLog = await decryptRawPrivateLog(
    privateLogs[0].fields.slice(1),
    await accountManager.getCompleteAddress(),
    recipientIvskM,
  );

  if (simCommitment.toString(16) === computedCommitment.toBigInt().toString(16)) {
    throw new Error('Simulation commitment matches the noir decrypted log commitment');
  }

  // Check that the noir implementation works as the javascript one
  if (
    decryptedRawLog[0].toBigInt().toString(16) !== noirDecryptedLog[0].toString(16) ||
    decryptedRawLog[1].toBigInt().toString(16) !== noirDecryptedLog[1].toString(16) ||
    decryptedRawLog[2].toBigInt().toString(16) !== noirDecryptedLog[2].toString(16) ||
    decryptedRawLog[3].toBigInt().toString(16) !== noirDecryptedLog[3].toString(16) ||
    decryptedRawLog[4].toBigInt().toString(16) !== noirDecryptedLog[4].toString(16)
  ) {
    throw new Error('Decrypted raw log does not match the noir implementation');
  }

  // We compute the commitment manually and compare it to the decrypted log commitment, it should match
  if (computedCommitment.toBigInt().toString(16) !== noirDecryptedLog[2].toString(16)) {
    throw new Error('Computed commitment does not match the decrypted log commitment');
  }

  return computedCommitment;

  // APP_LOGIC phase reverted! 0x27ec4e36f7eba4f36362122fdf51987209f09847d43f2e8215327c330c6dddaf:0xd427610c failed with reason: Tag mismatch at offset 33039, got FIELD, expected UINT32
  // Traced the that the reversion comes from this line https://github.com/AztecProtocol/aztec-packages/blob/c539f41e386ed029e9e644a3284c1c7663285585/noir-projects/aztec-nr/uint-note/src/uint_note.nr#L247
  // This error can be solver by doing the following:
  // export VERSION=3.0.0-devnet.2
  // aztec-up && docker pull aztecprotocol/aztec:$VERSION && docker tag aztecprotocol/aztec:$VERSION aztecprotocol/aztec:latest
}

/**
 * Computes a partial commitment from parts.
 * @param storageSlot - The storage slot.
 * @param ownerField - The owner field.
 * @param randomness - The randomness.
 * @returns The partial commitment.
 */
export async function computePartialCommitmentFromParts(storageSlot: Fr, ownerField: Fr, randomness: Fr): Promise<Fr> {
  // pack order must match Rust: [owner, randomness, storage_slot]
  const input = [ownerField, randomness, storageSlot];

  return poseidon2HashWithSeparator(input, GeneratorIndex.NOTE_HASH);
}

import { Point } from '@aztec/foundation/fields';
import { Aes128 } from '@aztec/foundation/crypto';
import { PRIVATE_LOG_CIPHERTEXT_LEN } from '@aztec/constants';
import { deriveEcdhSharedSecret } from '@aztec/stdlib/logs';
import { computeAddressSecret, deriveMasterIncomingViewingSecretKey } from '@aztec/stdlib/keys';
import { GrumpkinScalar } from '@aztec/foundation/fields';
import { CompleteAddress } from '@aztec/stdlib/contract';

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
