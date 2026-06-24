import { createLogger } from '@aztec/aztec.js/log';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type Wallet, AccountManager } from '@aztec/aztec.js/wallet';
import { Fr } from '@aztec/aztec.js/fields';
import { createAztecNodeClient, waitForNode, waitForTx } from '@aztec/aztec.js/node';
import { type ContractInstanceWithAddress } from '@aztec/aztec.js/contracts';
import { TxHash } from '@aztec/aztec.js/tx';
import { EmbeddedWallet } from '@aztec/wallets/embedded';
import { registerInitialLocalNetworkAccountsInWallet } from '@aztec/wallets/testing';
import { PublicKeys } from '@aztec/stdlib/keys';

import {
  DeployOptions,
  ContractFunctionInteraction,
  getContractClassFromArtifact,
  getContractInstanceFromInstantiationParams,
} from '@aztec/aztec.js/contracts';
import { AuthWitness, SetPublicAuthwitContractInteraction } from '@aztec/aztec.js/authorization';
import { getPublicEvents } from '@aztec/aztec.js/events';
import { getDefaultInitializer, getInitializer } from '@aztec/stdlib/abi';
import {
  computeInitializationHash,
  computeSaltedInitializationHash,
  computeContractAddressFromInstance,
} from '@aztec/stdlib/contract';

import { getPXEConfig } from '@aztec/pxe/server';
import { type TxExecutionRequest, type TxProvingResult } from '@aztec/stdlib/tx';
import { type ExecutionPayload } from '@aztec/stdlib/tx';
import { type FeeOptions } from '@aztec/wallet-sdk/base-wallet';
import { Barretenberg } from '@aztec/bb.js';

/**
 * Subset of protected BaseWallet methods needed to prove a tx and extract private return values.
 * These are not part of the public Wallet interface, so we define a local type to avoid `as any`.
 */
interface WalletWithInternals {
  completeFeeOptions(
    from: AztecAddress,
    feePayer: AztecAddress | undefined,
    gasSettings: undefined,
  ): Promise<FeeOptions>;
  createTxExecutionRequestFromPayloadAndFee(
    executionPayload: ExecutionPayload,
    from: AztecAddress,
    feeOptions: FeeOptions,
  ): Promise<TxExecutionRequest>;
  scopesFrom(from: AztecAddress): AztecAddress[];
  pxe: {
    proveTx(
      txRequest: TxExecutionRequest,
      opts: { scopes: AztecAddress[]; senderForTags?: AztecAddress },
    ): Promise<TxProvingResult>;
  };
}

import { TokenContract, TokenContractArtifact } from '../../../src/artifacts/Token.js';
import { VaultContract, VaultContractArtifact } from '../../../src/artifacts/Vault.js';
import { VaultDeployerContract, VaultDeployerContractArtifact } from '../../../src/artifacts/VaultDeployer.js';
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
  const pxe = { ...config, dataDirectory, proverEnabled };

  const wallet: EmbeddedWallet = await EmbeddedWallet.create(node, { pxe });

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

  expect((await token.methods.balance_of_public(aztecAddress).simulate({ from })).result).toBe(toBigInt(publicBalance));
  expect((await token.methods.balance_of_private(aztecAddress).simulate({ from })).result).toBe(
    toBigInt(privateBalance),
  );
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
  const { contract } = await TokenContract.deployWithOpts(
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
  const { contract } = await TokenContract.deployWithOpts(
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
  const { result: owner } = await nft.methods.public_owner_of(tokenId).simulate({ from });
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
  const {
    result: [nfts, _],
  } = await nft.methods.get_private_nfts(owner, 0).simulate({ from });
  const hasNFT = nfts.some((id: bigint) => id === tokenId);
  expect(hasNFT).toBe(expectToBeTrue);
}

// Deploy NFT contract with a minter
export async function deployNFTWithMinter(wallet: EmbeddedWallet, deployer: AztecAddress, options?: DeployOptions) {
  const { contract } = await NFTContract.deployWithOpts(
    { method: 'constructor_with_minter', wallet },
    'TestNFT',
    'TNFT',
    deployer,
  ).send({ ...options, from: deployer });
  return contract;
}

// --- Vault Utils ---

/**
 * Publishes the Vault contract class on-chain (needed before deploying pool VaultDeployer instances).
 * Each vault pool deploys its own VaultDeployer instance via initializers; there is no shared factory.
 */
export async function ensureVaultContractClassPublished(wallet: Wallet, deployer: AztecAddress): Promise<void> {
  await VaultContract.deploy(wallet, deployer, 1).send({ from: deployer });
}

/**
 * Deploys asset token plus a new VaultDeployer instance (initializer deploy_vault) that atomically
 * publishes and wires vault + shares. Child deployer addresses use this pool deployer instance address.
 * @param wallet - The wallet to deploy the contract with.
 * @param deployer - The account that deploys the pool VaultDeployer instance (parent deployer).
 * @returns [vault, asset, shares] contract instances.
 */
export async function deployVaultAndAssetWithMinter(
  wallet: Wallet,
  deployer: AztecAddress,
): Promise<[VaultContract, TokenContract, TokenContract]> {
  const { contract: assetContract } = await TokenContract.deployWithOpts(
    { method: 'constructor_with_minter', wallet },
    'AssetToken',
    'AT',
    6,
    deployer,
  ).send({ from: deployer });

  const vaultClass = await getContractClassFromArtifact(VaultContractArtifact);
  const tokenClass = await getContractClassFromArtifact(TokenContractArtifact);

  const poolDeployerSalt = Fr.random();

  const poolDeployerArgs = [assetContract.address, 1, vaultClass.id, 'SharesToken', 'ST', 18, tokenClass.id] as const;

  const poolDeployerInstance = await getContractInstanceFromInstantiationParams(VaultDeployerContractArtifact, {
    constructorArtifact: 'deploy_vault',
    constructorArgs: [...poolDeployerArgs],
    salt: poolDeployerSalt,
    deployer,
  });

  const vaultInstance = await getContractInstanceFromInstantiationParams(VaultContractArtifact, {
    constructorArtifact: 'constructor',
    constructorArgs: [assetContract.address, 1],
    salt: poolDeployerSalt,
    deployer: poolDeployerInstance.address,
  });

  const sharesInstance = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
    constructorArtifact: 'constructor_with_minter',
    constructorArgs: ['SharesToken', 'ST', 18, vaultInstance.address],
    salt: poolDeployerSalt,
    deployer: poolDeployerInstance.address,
  });

  await wallet.registerContract(poolDeployerInstance, VaultDeployerContractArtifact);
  await wallet.registerContract(vaultInstance, VaultContractArtifact);
  await wallet.registerContract(sharesInstance, TokenContractArtifact);

  await VaultDeployerContract.deployWithOpts(
    { method: 'deploy_vault', wallet, instantiation: { salt: poolDeployerSalt } },
    ...poolDeployerArgs,
  ).send({ from: deployer });

  const vaultContract = await VaultContract.at(vaultInstance.address, wallet);
  const sharesContract = await TokenContract.at(sharesInstance.address, wallet);

  return [vaultContract as VaultContract, assetContract as TokenContract, sharesContract as TokenContract];
}

/**
 * Deploys a new pool VaultDeployer (initializer deploy_vault_with_initial_deposit) to atomically
 * deploy vault + shares and seed the vault from the depositor.
 * @returns [vault, shares] contract instances.
 */
export async function deployVaultWithInitialDeposit(
  wallet: Wallet,
  deployer: AztecAddress,
  assetContract: TokenContract,
  initialDeposit: bigint,
  depositor: AztecAddress,
): Promise<[VaultContract, TokenContract]> {
  const vaultClass = await getContractClassFromArtifact(VaultContractArtifact);
  const tokenClass = await getContractClassFromArtifact(TokenContractArtifact);

  const poolDeployerSalt = Fr.random();

  const poolDeployerArgs = [
    assetContract.address,
    1,
    vaultClass.id,
    'SharesToken',
    'ST',
    18,
    tokenClass.id,
    initialDeposit,
    depositor,
    0,
  ] as const;

  const poolDeployerInstance = await getContractInstanceFromInstantiationParams(VaultDeployerContractArtifact, {
    constructorArtifact: 'deploy_vault_with_initial_deposit',
    constructorArgs: [...poolDeployerArgs],
    salt: poolDeployerSalt,
    deployer,
  });

  const vaultInstance = await getContractInstanceFromInstantiationParams(VaultContractArtifact, {
    constructorArtifact: 'constructor',
    constructorArgs: [assetContract.address, 1],
    salt: poolDeployerSalt,
    deployer: poolDeployerInstance.address,
  });

  const sharesInstance = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
    constructorArtifact: 'constructor_with_minter',
    constructorArgs: ['SharesToken', 'ST', 18, vaultInstance.address],
    salt: poolDeployerSalt,
    deployer: poolDeployerInstance.address,
  });

  await wallet.registerContract(poolDeployerInstance, VaultDeployerContractArtifact);
  await wallet.registerContract(vaultInstance, VaultContractArtifact);
  await wallet.registerContract(sharesInstance, TokenContractArtifact);

  const transfer = assetContract.methods.transfer_public_to_public(depositor, vaultInstance.address, initialDeposit, 0);
  await setPublicAuthWit(vaultInstance.address, transfer, depositor, wallet as EmbeddedWallet);

  await VaultDeployerContract.deployWithOpts(
    { method: 'deploy_vault_with_initial_deposit', wallet, instantiation: { salt: poolDeployerSalt } },
    ...poolDeployerArgs,
  ).send({ from: deployer });

  const vaultContract = await VaultContract.at(vaultInstance.address, wallet);
  const sharesContract = await TokenContract.at(sharesInstance.address, wallet);

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
  const { contract } = await EscrowContract.deploy(wallet, { publicKeys, salt, universalDeploy: true }).send({
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
  return wallet.createAuthWit(authorizer, {
    caller,
    call: await action.getFunctionCall(),
  });
}

export async function setPublicAuthWit(
  caller: AztecAddress,
  action: ContractFunctionInteraction,
  authorizer: AztecAddress,
  wallet: EmbeddedWallet,
) {
  const validateAction = await SetPublicAuthwitContractInteraction.create(wallet, authorizer, { caller, action }, true);
  await validateAction.send();
}

// TODO: Replace wallet internals (privateExecutionResult) with simulate() + send() to get private return values via public API.
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
): Promise<bigint> {
  // Use wallet internals to prove the tx and extract the private return value (the commitment)
  const interaction = token.methods.initialize_transfer_commitment(to.address, completer);
  const executionPayload = await interaction.request();
  const w = token.wallet as unknown as WalletWithInternals;
  const feeOptions = await w.completeFeeOptions(caller, executionPayload.feePayer, undefined);
  const txRequest = await w.createTxExecutionRequestFromPayloadAndFee(executionPayload, caller, feeOptions);
  const provenTx = await w.pxe.proveTx(txRequest, { scopes: w.scopesFrom(caller), senderForTags: caller });

  // Extract the commitment from the nested private execution results
  const entrypoint = provenTx.privateExecutionResult.entrypoint;
  const nestedResults = entrypoint.nestedExecutionResults;
  // The first nested result is the actual function call (account contract is entrypoint)
  const returnValues = nestedResults[0].returnValues;
  const commitment = returnValues[0].toBigInt();

  // Submit the proven tx to the node
  const tx = await provenTx.toTx();
  const txHash = tx.getTxHash();
  await node.sendTx(tx);
  await waitForTx(node, txHash);

  return commitment;
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
): Promise<bigint> {
  // Use wallet internals to prove the tx and extract the private return value (the commitment)
  const interaction = nft.methods.initialize_transfer_commitment(to.address, completer);
  const executionPayload = await interaction.request();
  const w = nft.wallet as unknown as WalletWithInternals;
  const feeOptions = await w.completeFeeOptions(caller, executionPayload.feePayer, undefined);
  const txRequest = await w.createTxExecutionRequestFromPayloadAndFee(executionPayload, caller, feeOptions);
  const provenTx = await w.pxe.proveTx(txRequest, { scopes: w.scopesFrom(caller), senderForTags: caller });

  const entrypoint = provenTx.privateExecutionResult.entrypoint;
  const nestedResults = entrypoint.nestedExecutionResults;
  const returnValues = nestedResults[0].returnValues;
  const commitment = returnValues[0].toBigInt();

  const tx = await provenTx.toTx();
  const txHash = tx.getTxHash();
  await node.sendTx(tx);
  await waitForTx(node, txHash);

  return commitment;
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
  const { contract } = await TestLogicContract.deployWithOpts({ method: 'constructor', wallet }, escrowClassId).send({
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
  const { contract } = await EscrowContract.deploy(wallet, { publicKeys, salt, universalDeploy: true }).send({
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
    immutablesHash: Fr.ZERO,
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
    immutablesHash: Fr.ZERO,
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
 * Queries the node for public Transfer events emitted in a transaction by a specific contract.
 *
 * @param txHash - The transaction hash to query events for.
 * @param contractAddress - The contract address to filter events by.
 * @returns An array of decoded TransferEvent objects.
 */
export async function getTransferEvents(txHash: TxHash, contractAddress: AztecAddress): Promise<TransferEvent[]> {
  const { events } = await getPublicEvents<TransferEvent>(node, TokenContract.events.Transfer, {
    contractAddress,
    txHash,
  });
  return events.map((e) => e.event);
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
 * Queries the node for public Transfer events emitted in a transaction by a specific NFT contract.
 *
 * @param txHash - The transaction hash to query events for.
 * @param contractAddress - The NFT contract address to filter events by.
 * @returns An array of decoded NFTTransferEvent objects.
 */
export async function getNFTTransferEvents(txHash: TxHash, contractAddress: AztecAddress): Promise<NFTTransferEvent[]> {
  const { events } = await getPublicEvents<NFTTransferEvent>(node, NFTContract.events.Transfer, {
    contractAddress,
    txHash,
  });
  return events.map((e) => e.event);
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
