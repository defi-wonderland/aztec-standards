import { Fr } from '@aztec/aztec.js/fields';
import { UniqueNote } from '@aztec/aztec.js/note';
import { createLogger } from '@aztec/aztec.js/log';
import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { deriveMasterIncomingViewingSecretKey } from '@aztec/stdlib/keys';
import { createAztecNodeClient, waitForNode } from '@aztec/aztec.js/node';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';
import { registerInitialSandboxAccountsInWallet, TestWallet } from '@aztec/test-wallet/server';
import { AuthWitness, SetPublicAuthwitContractInteraction } from '@aztec/aztec.js/authorization';
import { Contract, DeployOptions, ContractFunctionInteraction } from '@aztec/aztec.js/contracts';
import {
  INITIAL_TEST_SECRET_KEYS,
  INITIAL_TEST_ACCOUNT_SALTS,
  INITIAL_TEST_ENCRYPTION_KEYS,
} from '@aztec/accounts/testing';

import type { PXE } from '@aztec/pxe/server';
import { createStore } from '@aztec/kv-store/lmdb-v2';
import { createPXE, getPXEConfig } from '@aztec/pxe/server';
import type { AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';

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

/**
 * Setup the PXE and the store
 * @returns The PXE and the store
 */
export const setupPXE = async () => {
  const store: AztecLMDBStoreV2 = await createStore('pxe', pxeVersion, {
    dataDirectory: 'store',
    dataStoreMapSizeKb: 1e6,
  });
  const pxe: PXE = await createPXE(node, fullConfig, { store });
  await waitForNode(node);
  return { pxe, store };
};

/**
 * Setup the PXE, the store and the wallet
 * @returns The PXE, the store, the wallet and the accounts
 */
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

/**
 * Add test accounts to the wallet, which is by default 3
 * Use before calling registerInitialSandboxAccountsInWallet
 * @param count - The number of accounts to add to the wallet.
 */
export function addTestAccounts(count: number) {
  for (let i = 0; i < count; i++) {
    const secret = Fr.random();
    INITIAL_TEST_SECRET_KEYS.push(secret);
    INITIAL_TEST_ENCRYPTION_KEYS.push(deriveMasterIncomingViewingSecretKey(secret));
    INITIAL_TEST_ACCOUNT_SALTS.push(Fr.ZERO);
  }
}

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

// TODO: adapt this function to the new API
// /**
//  * Initializes a transfer commitment
//  * @param token - The token contract instance.
//  * @param caller - The wallet that will interact with the token contract.
//  * @param from - The address of the sender.
//  * @param to - The address of the recipient.
//  * @param completer - The address allowed to complete the partial note.
//  * @returns Partial note commitment
//  */
// export async function initializeTransferCommitment(
//   token: TokenContract,
//   caller: AccountWallet,
//   to: AztecAddress,
//   completer: AztecAddress,
// ) {
//   // alice prepares partial note for bob
//   const fnAbi = TokenContract.artifact.functions.find((f) => f.name === 'initialize_transfer_commitment')!;
//   const fn_interaction = token.methods.initialize_transfer_commitment(to, completer);

//   // Build the request once
//   const req = await fn_interaction.create({ fee: { estimateGas: false } }); // set the same fee options you’ll use

//   // Simulate using the exact request
//   const sim = await caller.simulateTx(
//     req,
//     true /* simulatePublic */,
//     undefined /* skipTxValidation */,
//     true /* skipFeeEnforcement */,
//   );
//   const rawReturnValues = sim.getPrivateReturnValues().nested[0].values; // decode as needed
//   const commitment = decodeFromAbi(fnAbi.returnTypes, rawReturnValues as Fr[]);

//   // Prove and send the exact same request
//   const prov = await caller.proveTx(req, sim.privateExecutionResult);
//   const tx = await prov.toTx();
//   const txHash = await caller.sendTx(tx);
//   await caller.getTxReceipt(txHash);

//   return commitment as bigint;
// }
