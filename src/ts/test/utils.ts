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
import { decodeFromAbi } from '@aztec/aztec.js/abi';
import {
  FunctionSelector,
  encodeArguments,
  getAllFunctionAbis,
  getDefaultInitializer,
  getInitializer,
} from '@aztec/stdlib/abi';
import { HashedValues } from '@aztec/stdlib/tx';
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
import { CyclicDeployerContract } from '../../../src/artifacts/CyclicDeployer.js';
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

const SHARES_NAME = 'SharesToken';
const SHARES_SYMBOL = 'ST';
const SHARES_DECIMALS = 18;
const VAULT_OFFSET = 1;

/**
 * Publishes the Vault contract class on-chain. The CyclicDeployer publishes Vault instances from a private
 * function, which requires the Vault class to be registered beforehand.
 */
export async function ensureVaultContractClassPublished(wallet: Wallet, deployer: AztecAddress): Promise<void> {
  await VaultContract.deploy(wallet, deployer, VAULT_OFFSET, false).send({ from: deployer });
}

/**
 * Constructor dispatch spec for one contract of a cyclic deployment, following the standard's hash-based model.
 * The deployer treats constructor calldata opaquely: it derives the address from `selector` + `initArgsHash`
 * and dispatches the constructor by `calldataHash`. `calldata` is the matching preimage that must be supplied
 * to the tx as an extra hashed arg so the dispatched-by-hash public call resolves.
 */
type ContractCtorSpec = {
  selector: FunctionSelector;
  initArgsHash: Fr;
  calldataHash: Fr;
  calldata: HashedValues;
};

/**
 * Computes the constructor dispatch spec for a contract from its artifact and constructor arguments.
 * `initArgsHash` matches the protocol's public initialization check (`hash_args(calldata[1..])`) and
 * `calldataHash` matches `hash_calldata_array([selector, ...args])` used by the deployer's hash dispatch.
 */
async function computeContractCtorSpec(
  artifact: typeof VaultContractArtifact,
  constructorName: string,
  args: unknown[],
): Promise<ContractCtorSpec> {
  const ctorAbi = getInitializer(artifact, constructorName);
  if (!ctorAbi) {
    throw new Error(`Constructor ${constructorName} not found in artifact`);
  }
  const selector = await FunctionSelector.fromNameAndParameters(ctorAbi.name, ctorAbi.parameters);
  const encodedArgs = encodeArguments(ctorAbi, args);
  const initArgs = await HashedValues.fromArgs(encodedArgs);
  const calldata = await HashedValues.fromCalldata([selector.toField(), ...encodedArgs]);
  return { selector, initArgsHash: initArgs.hash, calldataHash: calldata.hash, calldata };
}

/**
 * Packs a class id and a {@link ContractCtorSpec} into the deployer's `ContractSpec` struct: the four opaque
 * fields the deployer uses to derive the contract address (`class_id` + `init_selector` +
 * `init_args_hash`) and to dispatch its public constructor (`init_calldata_hash`).
 */
function toContractSpec(classId: Fr, spec: ContractCtorSpec) {
  return {
    class_id: classId,
    init_selector: spec.selector.toField(),
    init_args_hash: spec.initArgsHash,
    init_calldata_hash: spec.calldataHash,
  };
}

/**
 * Computes the selector of a Vault setter, the runtime selector the deployer dispatches for the deferred link.
 * The deployer is type-agnostic, so the setter's selector is supplied as data rather than via a typed stub.
 */
async function vaultSetterSelector(name: string): Promise<Fr> {
  // Public functions live in `nonDispatchPublicFunctions`, so search the full ABI set, not just `functions`.
  const fnAbi = getAllFunctionAbis(VaultContractArtifact).find((f) => f.name === name);
  if (!fnAbi) {
    throw new Error(`Function ${name} not found in Vault artifact`);
  }
  const selector = await FunctionSelector.fromNameAndParameters(fnAbi.name, fnAbi.parameters);
  return selector.toField();
}

/**
 * Computes the calldata-hash dispatch spec for an opaque {@link Action} on a Vault public function (the initial
 * deposit). The deployer dispatches it by `calldataHash`; `calldata` is the preimage that must be supplied to the
 * tx as an extra hashed arg.
 */
async function computeVaultActionSpec(
  name: string,
  args: unknown[],
): Promise<{ calldataHash: Fr; calldata: HashedValues }> {
  const fnAbi = getAllFunctionAbis(VaultContractArtifact).find((f) => f.name === name);
  if (!fnAbi) {
    throw new Error(`Function ${name} not found in Vault artifact`);
  }
  const selector = await FunctionSelector.fromNameAndParameters(fnAbi.name, fnAbi.parameters);
  const encodedArgs = encodeArguments(fnAbi, args);
  const calldata = await HashedValues.fromCalldata([selector.toField(), ...encodedArgs]);
  return { calldataHash: calldata.hash, calldata };
}

/**
 * Deploys a reusable CyclicDeployer instance and derives + registers the vault and shares instances it will
 * publish, plus the constructor dispatch specs the deployer consumes. `deploy` is a regular private function,
 * so a single instance can deploy any number of pairs; the per-deployment salt is the sole address
 * disambiguator. Both contracts use the CyclicDeployer instance as their (non-universal) deployer, so their
 * addresses are precomputable here. The shares `minter` is the derived vault address, resolved off-chain and
 * baked into the shares constructor hashes (the deployer dispatches them opaquely).
 * @returns The CyclicDeployer contract, the deployment salt, the derived contract instances, class IDs, and ctor specs.
 */
async function prepareVaultDeployment(
  wallet: Wallet,
  deployer: AztecAddress,
  asset: AztecAddress,
  expectsInitialDeposit: boolean,
) {
  const vaultClass = await getContractClassFromArtifact(VaultContractArtifact);
  const tokenClass = await getContractClassFromArtifact(TokenContractArtifact);

  // Deploy a fresh CyclicDeployer instance (publishing its class on first use). It has no constructor, so
  // its address does not depend on the deployment it performs.
  const { contract: cyclicDeployer } = await CyclicDeployerContract.deploy(wallet).send({ from: deployer });

  const salt = Fr.random();

  // The vault's `initial_deposit_pending` flag is committed in its address, so the deposit vs no-deposit
  // variants derive distinct vaults and the deposit action can only ever run on an armed vault.
  const vaultCtorArgs = [asset, VAULT_OFFSET, expectsInitialDeposit];

  const vaultInstance = await getContractInstanceFromInstantiationParams(VaultContractArtifact, {
    constructorArtifact: 'constructor',
    constructorArgs: vaultCtorArgs,
    salt,
    deployer: cyclicDeployer.address,
  });

  const sharesInstance = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
    constructorArtifact: 'constructor_with_minter',
    constructorArgs: [SHARES_NAME, SHARES_SYMBOL, SHARES_DECIMALS, vaultInstance.address],
    salt,
    deployer: cyclicDeployer.address,
  });

  // Precompute the opaque constructor dispatch specs. The vault is resolved first (no cross-contract arg);
  // the derived vault address is then embedded as the shares `minter`.
  const vaultCtorSpec = await computeContractCtorSpec(VaultContractArtifact, 'constructor', vaultCtorArgs);
  const sharesCtorSpec = await computeContractCtorSpec(TokenContractArtifact, 'constructor_with_minter', [
    SHARES_NAME,
    SHARES_SYMBOL,
    SHARES_DECIMALS,
    vaultInstance.address,
  ]);

  // Register the contract instance preimages so the get_contract_instance oracle resolves them during publication.
  await wallet.registerContract(vaultInstance, VaultContractArtifact);
  await wallet.registerContract(sharesInstance, TokenContractArtifact);

  return {
    cyclicDeployer: cyclicDeployer as CyclicDeployerContract,
    salt,
    vaultInstance,
    sharesInstance,
    vaultSpec: toContractSpec(vaultClass.id, vaultCtorSpec),
    sharesSpec: toContractSpec(tokenClass.id, sharesCtorSpec),
    // The constructor calldata preimages the deployer's hash-dispatched public calls resolve against.
    extraHashedArgs: [vaultCtorSpec.calldata, sharesCtorSpec.calldata],
  };
}

/**
 * Deploys an asset token plus a vault + shares pair atomically published and wired by a CyclicDeployer.
 * @param wallet - The wallet to deploy the contracts with.
 * @param deployer - The account that submits the deployment transactions.
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

  const { cyclicDeployer, salt, vaultInstance, sharesInstance, vaultSpec, sharesSpec, extraHashedArgs } =
    await prepareVaultDeployment(wallet, deployer, assetContract.address, false);

  // linked = vault (defers set_shares_token), target = shares (its ctor embeds the vault as minter).
  // No actions: both action calldata hashes are zero, so neither is dispatched.
  await cyclicDeployer.methods
    .deploy(
      salt,
      vaultSpec,
      sharesSpec,
      { setter_selector: await vaultSetterSelector('set_shares_token') },
      { calldata_hash: Fr.ZERO },
      { calldata_hash: Fr.ZERO },
    )
    // Supply the constructor calldata preimages so the deployer's hash-dispatched public calls resolve.
    .with({ extraHashedArgs })
    .send({ from: deployer });

  const vaultContract = await VaultContract.at(vaultInstance.address, wallet);
  const sharesContract = await TokenContract.at(sharesInstance.address, wallet);

  return [vaultContract as VaultContract, assetContract as TokenContract, sharesContract as TokenContract];
}

/**
 * Deploys a vault + shares pair and seeds the vault from the depositor in the same transaction.
 * @returns [vault, shares] contract instances.
 */
export async function deployVaultWithInitialDeposit(
  wallet: Wallet,
  deployer: AztecAddress,
  assetContract: TokenContract,
  initialDeposit: bigint,
  depositor: AztecAddress,
): Promise<[VaultContract, TokenContract]> {
  const { cyclicDeployer, salt, vaultInstance, sharesInstance, vaultSpec, sharesSpec, extraHashedArgs } =
    await prepareVaultDeployment(wallet, deployer, assetContract.address, true);

  // The vault pulls the initial deposit from the depositor, so the depositor must authorize the
  // (precomputed) vault to transfer on the asset token.
  const transfer = assetContract.methods.transfer_public_to_public(depositor, vaultInstance.address, initialDeposit, 0);
  await setPublicAuthWit(vaultInstance.address, transfer, depositor, wallet as EmbeddedWallet);

  // The initial deposit is an opaque Action dispatched on `linked` (the vault) by calldata hash after wiring.
  const depositAction = await computeVaultActionSpec('initial_deposit', [initialDeposit, depositor, 0]);

  // linked = vault (defers set_shares_token, runs the deposit action), target = shares (embeds vault as minter).
  // The deposit is the `linked` action; the `target` action is zero (no shares-side action).
  await cyclicDeployer.methods
    .deploy(
      salt,
      vaultSpec,
      sharesSpec,
      { setter_selector: await vaultSetterSelector('set_shares_token') },
      { calldata_hash: depositAction.calldataHash },
      { calldata_hash: Fr.ZERO },
    )
    // Supply the constructor calldata preimages plus the action calldata preimage so all hash-dispatched
    // public calls resolve.
    .with({ extraHashedArgs: [...extraHashedArgs, depositAction.calldata] })
    .send({ from: deployer });

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
  const expectedFieldCount = 3; // from, to, amount

  return response.logs
    .filter((extLog) => {
      const eventFields = extLog.log.getEmittedFieldsWithoutTag();
      return eventFields.length === expectedFieldCount;
    })
    .map((extLog) => {
      const eventFields = extLog.log.getEmittedFieldsWithoutTag();
      return decodeFromAbi([eventMetadata.abiType], eventFields) as TransferEvent;
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
  const expectedFieldCount = 3; // from, to, token_id

  return response.logs
    .filter((extLog) => {
      const eventFields = extLog.log.getEmittedFieldsWithoutTag();
      return eventFields.length === expectedFieldCount;
    })
    .map((extLog) => {
      const eventFields = extLog.log.getEmittedFieldsWithoutTag();
      return decodeFromAbi([eventMetadata.abiType], eventFields) as NFTTransferEvent;
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
