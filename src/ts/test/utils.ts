import { Fr } from '@aztec/aztec.js/fields';
import { UniqueNote } from '@aztec/aztec.js/note';
import { createLogger } from '@aztec/aztec.js/log';
import type { Wallet } from '@aztec/aztec.js/wallet';
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
  const commitment = decodeFromAbi(fnAbi.returnTypes, rawReturnValues as Fr[]);

  // Prove using the EXACT SAME request
  const proof = await wallet.proveTx(req, { from: caller });
  const tx = await proof.send().wait();
  await wallet.getTxReceipt(tx.txHash);

  const txEffect = await node.getTxEffect(tx.txHash);
  if (!txEffect?.data.privateLogs) {
    throw new Error('No private logs found');
  }
  const privateLogs = txEffect?.data.privateLogs;
  const decryptedLog = await token
    .withWallet(wallet)
    .methods.decrypt_raw_log(privateLogs[0].fields.slice(1), to)
    .simulate({ from: caller });
  const computedCommitment = await computePartialCommitmentFromParts(decryptedLog[1], decryptedLog[3], decryptedLog[4]);

  console.log(
    `X: ${decryptedLog[0].toString(16)}\nSTORAGE SLOT: ${decryptedLog[1].toString(16)}\nCOMMITMENT: ${decryptedLog[2].toString(16)}\nTO: ${decryptedLog[3].toString(16)}\nRANDOMNESS: ${decryptedLog[4].toString(16)}`,
  );
  console.log('decryptedLog[2]', decryptedLog[2]);
  console.log('computedCommitment', computedCommitment);
  console.log('commitment', commitment);
  // We compute the commitment manually and compare it to the decrypted log commitment, it should match
  if (computedCommitment.toBigInt().toString(16) !== decryptedLog[2].toString(16)) {
    throw new Error('Computed commitment does not match the decrypted log commitment');
  }

  // Could not get the same commitment from the simulation as the one in the private logs

  // When returning the simulation commitment, the transaction is reverted because the commitment is not valid
  // return commitment as bigint;
  // Transaction 0x23d442079be64f35319422d9c9634f6d6528f5769d65dfd33e79d5ca91e52285 was app_logic_reverted. Reason:
  // APP_LOGIC phase reverted! 0x0d2abd75f825e4d72c0fbd6219c9736eac801524d2a4d51853452411e82baf98:0xd427610c failed with reason: Assertion failed:

  // When returning the computed commitment, the transaction is reverted because a public log emission problem occurs
  return decryptedLog[2] as bigint;
  // APP_LOGIC phase reverted! 0x27ec4e36f7eba4f36362122fdf51987209f09847d43f2e8215327c330c6dddaf:0xd427610c failed with reason: Tag mismatch at offset 33039, got FIELD, expected UINT32
  // Traced the that the reversion comes from this line https://github.com/AztecProtocol/aztec-packages/blob/c539f41e386ed029e9e644a3284c1c7663285585/noir-projects/aztec-nr/uint-note/src/uint_note.nr#L247
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
