import {
  createLogger,
  Fr,
  AztecAddress,
  UniqueNote,
  AccountWallet,
  Contract,
  DeployOptions,
  createAztecNodeClient,
  waitForPXE,
  IntentAction,
  Wallet,
  AuthWitness,
  ContractFunctionInteraction,
} from '@aztec/aztec.js';
import { decodeFromAbi } from '@aztec/stdlib/abi';
import { getPXEServiceConfig } from '@aztec/pxe/config';
import { createPXEService } from '@aztec/pxe/server';
import { createStore } from '@aztec/kv-store/lmdb';
import { TokenContract, TokenContractArtifact } from '../../../artifacts/Token.js';
import { NFTContractArtifact } from '../../../artifacts/NFT.js';

export const logger = createLogger('aztec:aztec-standards');

const { NODE_URL = 'http://localhost:8080' } = process.env;
const node = createAztecNodeClient(NODE_URL);
const l1Contracts = await node.getL1ContractAddresses();
const config = getPXEServiceConfig();
const fullConfig = { ...config, l1Contracts };
fullConfig.proverEnabled = false;

export const setupPXE = async () => {
  const store = await createStore('pxe', {
    dataDirectory: 'store',
    dataStoreMapSizeKB: 1e6,
  });
  const pxe = await createPXEService(node, fullConfig, { store });
  await waitForPXE(pxe);
  return { pxe, store };
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
  caller?: AccountWallet,
) => {
  const aztecAddress = address instanceof AztecAddress ? address : address.getAddress();
  logger.info('checking balances for', aztecAddress.toString());
  const t = caller ? token.withWallet(caller) : token;

  // Helper to cast to bigint if not already
  const toBigInt = (val: bigint | number | Fr) => {
    if (typeof val === 'bigint') return val;
    if (typeof val === 'number') return BigInt(val);
    if (val instanceof Fr) return val.toBigInt();
    throw new Error('Unsupported type for balance');
  };

  expect(await t.methods.balance_of_public(aztecAddress).simulate()).toBe(toBigInt(publicBalance));
  expect(await t.methods.balance_of_private(aztecAddress).simulate()).toBe(toBigInt(privateBalance));
};

export const AMOUNT = 1000n;
export const wad = (n: number = 1) => AMOUNT * BigInt(n);

/**
 * Deploys the Token contract with a specified minter.
 * @param deployer - The wallet to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployTokenWithMinter(deployer: Wallet, options?: DeployOptions) {
  const contract = await Contract.deploy(
    deployer,
    TokenContractArtifact,
    ['PrivateToken', 'PT', 18, deployer.getAddress(), AztecAddress.ZERO],
    'constructor_with_minter',
  )
    .send(options)
    .deployed();
  return contract;
}

export async function deployTokenWithInitialSupply(deployer: AccountWallet) {
  const contract = await Contract.deploy(
    deployer,
    TokenContractArtifact,
    ['PrivateToken', 'PT', 18, 0, deployer.getAddress(), deployer.getAddress()],
    'constructor_with_initial_supply',
  )
    .send()
    .deployed();
  return contract;
}

/**
 * Deploys the NFT contract with a specified minter.
 * @param deployer - The wallet to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployNFTWithMinter(deployer: AccountWallet, options?: DeployOptions) {
  const contract = await Contract.deploy(
    deployer,
    NFTContractArtifact,
    ['NFT', 'NFT', deployer.getAddress(), deployer.getAddress()],
    'constructor_with_minter',
  )
    .send(options)
    .deployed();
  return contract;
}

/**
 * Deploys the Token contract with a specified minter.
 * @param deployer - The wallet to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployVaultAndAssetWithMinter(deployer: AccountWallet): Promise<[Contract, Contract]> {
  const assetContract = await Contract.deploy(
    deployer,
    TokenContractArtifact,
    ['PrivateToken', 'PT', 6, deployer.getAddress(), AztecAddress.ZERO],
    'constructor_with_minter',
  )
    .send()
    .deployed();

  const vaultContract = await Contract.deploy(
    deployer,
    TokenContractArtifact,
    ['VaultToken', 'VT', 6, assetContract.address, AztecAddress.ZERO],
    'constructor_with_asset',
  )
    .send()
    .deployed();

  return [vaultContract, assetContract];
}

export async function setPrivateAuthWit(
  caller: AztecAddress | { getAddress: () => AztecAddress },
  action: ContractFunctionInteraction,
  deployer: AccountWallet,
): Promise<AuthWitness> {
  const callerAddress = caller instanceof AztecAddress ? caller : caller.getAddress();

  const intent: IntentAction = {
    caller: callerAddress,
    action: action,
  };
  return deployer.createAuthWit(intent);
}

export async function setPublicAuthWit(
  caller: AztecAddress | { getAddress: () => AztecAddress },
  action: ContractFunctionInteraction,
  deployer: AccountWallet,
) {
  const callerAddress = caller instanceof AztecAddress ? caller : caller.getAddress();

  const intent: IntentAction = {
    caller: callerAddress,
    action: action,
  };
  await deployer.createAuthWit(intent);
  await (await deployer.setPublicAuthWit(intent, true)).send().wait();
}

/**
 * Initializes a transfer commitment
 * @param deployer - The wallet to deploy the contract with.
 * @returns Partial not commitment
 */
export async function initializeTransferCommitment(
  token: TokenContract,
  caller: AccountWallet,
  from: AztecAddress,
  to: AztecAddress,
  completer: AztecAddress,
) {
  // alice prepares partial note for bob
  const fnAbi = TokenContract.artifact.functions.find((f) => f.name === 'initialize_transfer_commitment')!;
  const fn_interaction = token.methods.initialize_transfer_commitment(from, to, completer);

  // Build the request once
  const req = await fn_interaction.create({ fee: { estimateGas: false } }); // set the same fee options you’ll use

  // Simulate using the exact request
  const sim = await caller.simulateTx(
    req,
    true /* simulatePublic */,
    undefined /* skipTxValidation */,
    true /* skipFeeEnforcement */,
  );
  const rawReturnValues = sim.getPrivateReturnValues().nested[0].values; // decode as needed
  const commitment = decodeFromAbi(fnAbi.returnTypes, rawReturnValues as Fr[]);

  // Prove and send the exact same request
  const prov = await caller.proveTx(req, sim.privateExecutionResult);
  const txHash = await caller.sendTx(prov.toTx());
  await caller.getTxReceipt(txHash);

  return commitment as bigint;
}
