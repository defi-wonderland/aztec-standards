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
import { getPXEServiceConfig, type PXEServiceConfig } from '@aztec/pxe/config';
import { createPXEService } from '@aztec/pxe/server';
import { createStore } from '@aztec/kv-store/lmdb';
import { type L1ContractAddresses } from '@aztec/ethereum/l1-contract-addresses';
import { TokenContract, TokenContractArtifact } from '../../artifacts/Token.js';
import { NFTContractArtifact } from '../../artifacts/NFT.js';
import { expect } from 'vitest';

export const logger = createLogger('aztec:aztec-standards');

const { NODE_URL = 'http://localhost:8080' } = process.env;

let l1Contracts: L1ContractAddresses;
let fullConfig: PXEServiceConfig & { l1Contracts: L1ContractAddresses };

const initializeConfig = async () => {
  if (!l1Contracts) {
    const node = createAztecNodeClient(NODE_URL);
    l1Contracts = await node.getL1ContractAddresses();
    const config = getPXEServiceConfig();
    fullConfig = {
      ...config,
      l1Contracts,
      proverEnabled: false,
    };
  }
  return fullConfig;
};

export const setupPXE = async () => {
  const config = await initializeConfig();
  const node = createAztecNodeClient(NODE_URL);
  const store = await createStore('pxe', {
    dataDirectory: 'store',
    dataStoreMapSizeKB: 1e6,
  });
  const pxe = await createPXEService(node, config, { store });
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
