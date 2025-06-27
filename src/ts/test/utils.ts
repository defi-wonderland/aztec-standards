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
  Wallet,
} from '@aztec/aztec.js';
import { getPXEServiceConfig } from '@aztec/pxe/config';
import { createPXEService } from '@aztec/pxe/server';
import { createStore } from '@aztec/kv-store/lmdb';
import { TokenContract, TokenContractArtifact } from '../../artifacts/Token.js';
import { NFTContractArtifact } from '../../artifacts/NFT.js';

export const logger = createLogger('aztec:aztec-standards');

const { NODE_URL = 'http://localhost:8080' } = process.env;
const node = createAztecNodeClient(NODE_URL);
const l1Contracts = await node.getL1ContractAddresses();
const config = getPXEServiceConfig();
const fullConfig = { ...config, l1Contracts };
fullConfig.proverEnabled = false;

const store = await createStore('pxe', {
  dataDirectory: 'store',
  dataStoreMapSizeKB: 1e6,
});

export const setupPXE = async () => {
  const pxe = await createPXEService(node, fullConfig, { store });
  await waitForPXE(pxe);
  return pxe;
};

// --- Token Utils ---

export const expectUintNote = (note: UniqueNote, amount: bigint, owner: AztecAddress) => {
  expect(note.note.items[0]).toEqual(new Fr(owner.toBigInt()));
  expect(note.note.items[2]).toEqual(new Fr(amount));
};

export const expectTokenBalances = async (
  token: TokenContract,
  address: AztecAddress,
  publicBalance: bigint,
  privateBalance: bigint,
  caller?: AccountWallet,
) => {
  logger.info('checking balances for', address.toString());
  const t = caller ? token.withWallet(caller) : token;
  expect(await t.methods.balance_of_public(address).simulate()).toBe(publicBalance);
  expect(await t.methods.balance_of_private(address).simulate()).toBe(privateBalance);
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
    ['NFT', 'NFT', deployer.getAddress()],
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
  caller: AztecAddress,
  action: ContractFunctionInteraction,
  deployer: AccountWallet,
): Promise<AuthWitness> {
  const intent: IntentAction = {
    caller: caller,
    action: action,
  };
  return deployer.createAuthWit(intent);
}

export async function setPublicAuthWit(
  caller: AztecAddress,
  action: ContractFunctionInteraction,
  deployer: AccountWallet,
) {
  const intent: IntentAction = {
    caller: caller,
    action: action,
  };
  await deployer.createAuthWit(intent);
  await (await deployer.setPublicAuthWit(intent, true)).send().wait();
}
