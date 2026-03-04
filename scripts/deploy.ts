import 'dotenv/config';
import { Command } from 'commander';
import { PublicKeys } from '@aztec/aztec.js/keys';
import {
  getContractInstanceFromInstantiationParams,
  DeployMethod,
  Contract,
  type InteractionFeeOptions,
  DeployOptions,
} from '@aztec/aztec.js/contracts';
import { TxStatus } from '@aztec/aztec.js/tx';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { Fr } from '@aztec/aztec.js/fields';
import { SponsoredFeePaymentMethod } from '@aztec/aztec.js/fee';
import { AccountWithSecretKey, Account } from '@aztec/aztec.js/account';
import { AccountManager, type Wallet } from '@aztec/aztec.js/wallet';
import { BaseWallet } from '@aztec/wallet-sdk/base-wallet';
import { createAztecNodeClient, type AztecNode } from '@aztec/aztec.js/node';
import { createLogger } from '@aztec/foundation/log';
import { sleep } from '@aztec/foundation/sleep';

import { SingleKeyAccountContract } from '@aztec/accounts/single_key';
import { deriveSigningKey } from '@aztec/stdlib/keys';
import { SponsoredFPCContract } from '@aztec/noir-contracts.js/SponsoredFPC';
import { SPONSORED_FPC_SALT } from '@aztec/constants';
import { poseidon2Hash } from '@aztec/foundation/crypto/poseidon';

import { TokenContract, TokenContractArtifact } from '../src/artifacts/Token.js';
import { DripperContract, DripperContractArtifact } from '../src/artifacts/Dripper.js';

import { createStore } from '@aztec/kv-store/lmdb-v2';
import { createPXE, getPXEConfig } from '@aztec/pxe/server';
import type { PXE, PXECreationOptions } from '@aztec/pxe/server';
import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

import { AztecAddressLike, FieldLike, type ContractArtifact } from '@aztec/aztec.js/abi';
import { getConfig, DeploymentConfig, TokenConfig, type Network } from './deploy-config.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packageJson = JSON.parse(readFileSync(join(__dirname, '../package.json'), 'utf-8'));

const logger = createLogger('aztec:deploy');

// --- Types ---

export interface DeployedContracts {
  weth?: { contract: TokenContract; status: 'deployed' | 'existing' };
  dai?: { contract: TokenContract; status: 'deployed' | 'existing' };
  usdc?: { contract: TokenContract; status: 'deployed' | 'existing' };
  dripper?: { contract: DripperContract; status: 'deployed' | 'existing' };
  deployer?: AccountWithSecretKey;
}

interface TokenConstructorArgs {
  name: string;
  symbol: string;
  decimals: number;
  minter: AztecAddress;
  upgrade_authority: AztecAddress;
}

interface DeploymentToken {
  address: AztecAddress;
  salt: FieldLike;
  deployer: AztecAddress;
  constructorArtifact: string;
  constructorArgs: TokenConstructorArgs;
}

interface DeploymentDripper {
  address: AztecAddressLike;
  salt: FieldLike;
  deployer: AztecAddressLike;
  constructorArtifact: string;
}

export interface DeploymentData {
  tokens: DeploymentToken[];
  dripper?: DeploymentDripper;
}

interface DeployedContract<T> {
  contract: T;
  status: 'deployed' | 'existing';
}

const UNIVERSAL_DEPLOYER = AztecAddress.ZERO;

function getDeploymentData(
  contracts: DeployedContracts | null | undefined,
  config: DeploymentConfig,
  upgradeAuthority: AztecAddress,
): DeploymentData {
  if (!contracts || (!contracts.weth && !contracts.dai && !contracts.usdc && !contracts.dripper)) {
    return { tokens: [] };
  }

  const dripperAddress = contracts.dripper?.contract?.address;
  const minterAddress = dripperAddress || AztecAddress.ZERO;

  const tokens: DeploymentToken[] = [];

  if (contracts.weth) {
    const { name, symbol, decimals, salt } = config.contracts.tokens.weth;
    tokens.push({
      address: contracts.weth.contract.address,
      salt,
      deployer: UNIVERSAL_DEPLOYER,
      constructorArtifact: 'constructor_with_minter',
      constructorArgs: { name, symbol, decimals, minter: minterAddress, upgrade_authority: upgradeAuthority },
    });
  }

  if (contracts.dai) {
    const { name, symbol, decimals, salt } = config.contracts.tokens.dai;
    tokens.push({
      address: contracts.dai.contract.address,
      salt,
      deployer: UNIVERSAL_DEPLOYER,
      constructorArtifact: 'constructor_with_minter',
      constructorArgs: { name, symbol, decimals, minter: minterAddress, upgrade_authority: upgradeAuthority },
    });
  }

  if (contracts.usdc) {
    const { name, symbol, decimals, salt } = config.contracts.tokens.usdc;
    tokens.push({
      address: contracts.usdc.contract.address,
      salt,
      deployer: UNIVERSAL_DEPLOYER,
      constructorArtifact: 'constructor_with_minter',
      constructorArgs: { name, symbol, decimals, minter: minterAddress, upgrade_authority: upgradeAuthority },
    });
  }

  const result: DeploymentData = { tokens };

  if (dripperAddress) {
    result.dripper = {
      address: dripperAddress,
      salt: config.contracts.dripper.salt,
      deployer: UNIVERSAL_DEPLOYER,
      constructorArtifact: 'constructor',
    };
  }

  return result;
}

// --- CLI ---

interface CLIOptions {
  deployerSecret?: string;
  dryRun?: boolean;
  output?: string;
  network: Network;
}

interface RetryOptions {
  maxRetries: number;
  initialDelayMs: number;
  backoffMultiplier: number;
  maxDelayMs: number;
}

async function withRetry<T>(operation: () => Promise<T>, operationName: string, options: RetryOptions): Promise<T> {
  const { maxRetries, initialDelayMs, backoffMultiplier, maxDelayMs } = options;

  let lastError: Error;
  let delayMs = initialDelayMs;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      logger.info(`${operationName}: Attempt ${attempt}/${maxRetries}`);
      return await operation();
    } catch (error) {
      lastError = error as Error;
      logger.warn(`${operationName}: Attempt ${attempt} failed:`, error);

      if (attempt < maxRetries) {
        const actualDelay = Math.min(delayMs, maxDelayMs);
        logger.info(`${operationName}: Retrying in ${actualDelay / 1000} seconds...`);
        await sleep(actualDelay);
        delayMs *= backoffMultiplier;
      }
    }
  }

  logger.error(`${operationName}: All ${maxRetries} attempts failed`);
  throw lastError!;
}

export function logDeployedContracts(contracts: DeployedContracts): void {
  logger.info('Deployed contracts:');

  for (const [key, value] of Object.entries(contracts)) {
    if (value && typeof value === 'object' && 'contract' in value) {
      const status = value.status === 'deployed' ? '[NEWLY DEPLOYED]' : '[EXISTING]';
      logger.info(`${key}: ${value.contract.address.toString()} ${status}`);
    } else if (value instanceof AccountWithSecretKey) {
      logger.info(`${key}: ${value.getAddress().toString()}`);
    } else {
      logger.info(`${key}: ${value}`);
    }
  }
}

export interface TokenDeployParams {
  name: string;
  symbol: string;
  decimals: number;
  minter?: AztecAddress;
  upgradeAuthority?: AztecAddress;
  salt: Fr;
}

export async function setupPXE(node: AztecNode, config: DeploymentConfig): Promise<PXE> {
  const pxeVersion = config.deployer.pxeVersion;

  const isSandbox = config.network.name === 'sandbox';
  const pxeConfig = {
    ...getPXEConfig(),
    proverEnabled: !isSandbox,
  };
  const options: PXECreationOptions = {
    store: await createStore(config.deployer.dataDirectory, pxeVersion, {
      dataDirectory: config.deployer.dataDirectory,
      dataStoreMapSizeKb: 1e6,
    }),
  };
  const pxe = await createPXE(node, pxeConfig, options);
  logger.info('Connected to PXE');

  try {
    const nodeInfo = await node.getNodeInfo();
    logger.info(`Connected to Aztec node version: ${nodeInfo.nodeVersion}`);

    return pxe;
  } catch (error) {
    logger.error('Failed to connect to PXE:', error);
    throw error;
  }
}

class MinimalWallet extends BaseWallet {
  private readonly addressToAccount = new Map<string, AccountWithSecretKey>();

  constructor(pxe: PXE, aztecNode: AztecNode) {
    super(pxe as unknown as any, aztecNode);
  }

  public addAccount(account: AccountWithSecretKey) {
    this.addressToAccount.set(account.getAddress().toString(), account);
  }

  protected async getAccountFromAddress(address: AztecAddress): Promise<Account> {
    const acc = this.addressToAccount.get(address.toString());
    if (!acc) throw new Error(`Account not found in wallet for address: ${address.toString()}`);
    return acc;
  }

  async getAccounts(): Promise<{ alias: string; item: AztecAddress }[]> {
    return Array.from(this.addressToAccount.values()).map((acc) => ({ alias: '', item: acc.getAddress() }));
  }
}

export async function createAccount(
  pxe: PXE,
  node: AztecNode,
  secret: Fr,
): Promise<{ wallet: Wallet; account: AccountWithSecretKey }> {
  logger.info('Creating account...');

  const wallet = new MinimalWallet(pxe, node);
  const signingKey = deriveSigningKey(secret);
  const accountContract = new SingleKeyAccountContract(signingKey);
  const manager = await AccountManager.create(wallet, secret, accountContract, Fr.ZERO);
  const account = await manager.getAccount();
  const instance = manager.getInstance();
  const artifact = await manager.getAccountContract().getContractArtifact();
  await wallet.registerContract(instance, artifact, manager.getSecretKey());
  (wallet as MinimalWallet).addAccount(account);

  logger.info(`Account created: ${account.getAddress().toString()}`);
  return { wallet, account };
}

export async function createSponsoredFeeOptions(pxe: PXE): Promise<InteractionFeeOptions> {
  logger.info('Setting up sponsored fee options...');

  const sponsoredFPCInstance = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, {
    salt: new Fr(SPONSORED_FPC_SALT),
  });

  try {
    await pxe.registerContract({
      instance: sponsoredFPCInstance,
      artifact: SponsoredFPCContract.artifact,
    });
    logger.info(`Registered SponsoredFPC at: ${sponsoredFPCInstance.address.toString()}`);
  } catch (error) {
    logger.debug('SponsoredFPC already registered');
  }

  const paymentMethod = new SponsoredFeePaymentMethod(sponsoredFPCInstance.address);

  return {
    paymentMethod,
  };
}

async function checkContractDeployed(node: AztecNode, address: AztecAddress): Promise<boolean> {
  try {
    logger.info(`Checking if contract deployed at ${address.toString()}...`);
    const instance = await node.getContract(address);
    if (!instance) {
      logger.info(`Contract at ${address.toString()} instance not found`);
      return false;
    }
    logger.info(`Contract instance found at ${address.toString()}`);
    return true;
  } catch (error) {
    logger.info(`Contract at ${address.toString()} not found or not initialized: ${error}`);
    return false;
  }
}

async function deployContractGeneric(
  deployer: Wallet,
  node: AztecNode,
  pxe: PXE,
  artifact: ContractArtifact,
  constructorArgs: any[],
  constructorArtifact: string,
  salt: Fr,
  options: DeployOptions,
  label: string,
): Promise<{ address: AztecAddress; status: 'deployed' | 'existing' }> {
  logger.info(`Checking ${label}...`);

  const instance = await getContractInstanceFromInstantiationParams(artifact, {
    constructorArgs,
    salt,
    publicKeys: PublicKeys.default(),
    deployer: AztecAddress.ZERO,
    constructorArtifact,
  });

  const isDeployed = await checkContractDeployed(node, instance.address);

  if (isDeployed) {
    logger.info(`${label} already deployed at: ${instance.address.toString()}`);

    try {
      await pxe.registerContract({ instance, artifact });
      logger.debug(`${label} registered with PXE`);
    } catch (error) {
      logger.debug(`${label} already registered with PXE`);
    }

    return { address: instance.address, status: 'existing' };
  }

  logger.info(`Deploying ${label}...`);

  const deployMethod = new DeployMethod(
    PublicKeys.default(),
    deployer,
    artifact,
    (inst) => Contract.at(inst.address, artifact, deployer),
    constructorArgs,
    constructorArtifact,
  );

  try {
    await deployMethod.send({
      ...options,
      contractAddressSalt: salt,
      universalDeploy: true,
      wait: { waitForStatus: TxStatus.PROPOSED },
    });
  } catch (error: any) {
    const msg = error?.message || error?.cause?.message || String(error);
    if (msg.includes('Existing nullifier')) {
      logger.info(`${label} already deployed (existing nullifier) at: ${instance.address.toString()}`);
      return { address: instance.address, status: 'existing' };
    }
    throw error;
  }

  logger.info(`${label} deployed at: ${instance.address.toString()}`);
  return { address: instance.address, status: 'deployed' };
}

export async function deployToken(
  deployer: Wallet,
  node: AztecNode,
  pxe: PXE,
  params: TokenDeployParams,
  options: DeployOptions,
): Promise<{ contract: TokenContract; status: 'deployed' | 'existing' }> {
  const minter = params.minter || AztecAddress.ZERO;
  const upgradeAuthority = params.upgradeAuthority || AztecAddress.ZERO;

  const result = await deployContractGeneric(
    deployer, node, pxe,
    TokenContractArtifact,
    [params.name, params.symbol, params.decimals, minter, upgradeAuthority],
    'constructor_with_minter',
    params.salt,
    options,
    `Token ${params.name} (${params.symbol})`,
  );

  const contract = await TokenContract.at(result.address, deployer);
  return { contract, status: result.status };
}

export async function deployDripper(
  deployer: Wallet,
  node: AztecNode,
  pxe: PXE,
  salt: Fr,
  options: DeployOptions,
): Promise<{ contract: DripperContract; status: 'deployed' | 'existing' }> {
  const result = await deployContractGeneric(
    deployer, node, pxe,
    DripperContractArtifact,
    [],
    'constructor',
    salt,
    options,
    'Dripper',
  );

  const contract = await DripperContract.at(result.address, deployer);
  return { contract, status: result.status };
}

export async function deployTokenWithRetry(
  deployer: Wallet,
  node: AztecNode,
  pxe: PXE,
  params: TokenDeployParams,
  options: DeployOptions,
  retryOptions: RetryOptions,
): Promise<{ contract: TokenContract; status: 'deployed' | 'existing' }> {
  return withRetry(
    () => deployToken(deployer, node, pxe, params, options),
    `Deploy Token ${params.name} (${params.symbol})`,
    retryOptions,
  );
}

interface ComputedAddresses {
  weth: AztecAddress;
  dai: AztecAddress;
  usdc: AztecAddress;
  dripper: AztecAddress;
  upgradeAuthority: AztecAddress;
}

async function computeContractAddresses(config: DeploymentConfig): Promise<ComputedAddresses> {
  const upgradeAuthority = config.contracts.upgradeAuthority
    ? AztecAddress.fromString(config.contracts.upgradeAuthority)
    : AztecAddress.ZERO;

  let dripper: AztecAddress;
  if (config.contracts.dripper.existingAddress) {
    dripper = config.contracts.dripper.existingAddress;
  } else {
    const dripperSalt = config.contracts.dripper.salt;
    const dripperInstance = await getContractInstanceFromInstantiationParams(DripperContractArtifact, {
      constructorArgs: [],
      salt: new Fr(dripperSalt),
      publicKeys: PublicKeys.default(),
      deployer: AztecAddress.ZERO,
    });
    dripper = dripperInstance.address;
  }

  const wethConfig = config.contracts.tokens.weth;
  const wethInstance = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
    constructorArgs: [wethConfig.name, wethConfig.symbol, wethConfig.decimals, dripper, upgradeAuthority],
    salt: new Fr(wethConfig.salt),
    publicKeys: PublicKeys.default(),
    deployer: AztecAddress.ZERO,
    constructorArtifact: 'constructor_with_minter',
  });

  const daiConfig = config.contracts.tokens.dai;
  const daiInstance = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
    constructorArgs: [daiConfig.name, daiConfig.symbol, daiConfig.decimals, dripper, upgradeAuthority],
    salt: new Fr(daiConfig.salt),
    publicKeys: PublicKeys.default(),
    deployer: AztecAddress.ZERO,
    constructorArtifact: 'constructor_with_minter',
  });

  const usdcConfig = config.contracts.tokens.usdc;
  const usdcInstance = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
    constructorArgs: [usdcConfig.name, usdcConfig.symbol, usdcConfig.decimals, dripper, upgradeAuthority],
    salt: new Fr(usdcConfig.salt),
    publicKeys: PublicKeys.default(),
    deployer: AztecAddress.ZERO,
    constructorArtifact: 'constructor_with_minter',
  });

  return {
    weth: wethInstance.address,
    dai: daiInstance.address,
    usdc: usdcInstance.address,
    dripper,
    upgradeAuthority,
  };
}

export async function deployContracts(options: CLIOptions, config: DeploymentConfig): Promise<DeployedContracts> {
  logger.info(`Deploying to ${config.network.name}...`);
  logger.info(`Network: ${config.network.nodeUrl}`);

  if (options.dryRun) {
    logger.info('[DRY RUN] Computing contract addresses...');
    const addresses = await computeContractAddresses(config);

    const deploymentData: DeploymentData = {
      tokens: [
        {
          address: addresses.weth,
          salt: config.contracts.tokens.weth.salt,
          deployer: UNIVERSAL_DEPLOYER,
          constructorArtifact: 'constructor_with_minter',
          constructorArgs: {
            name: config.contracts.tokens.weth.name,
            symbol: config.contracts.tokens.weth.symbol,
            decimals: config.contracts.tokens.weth.decimals,
            minter: addresses.dripper,
            upgrade_authority: addresses.upgradeAuthority,
          },
        },
        {
          address: addresses.dai,
          salt: config.contracts.tokens.dai.salt,
          deployer: UNIVERSAL_DEPLOYER,
          constructorArtifact: 'constructor_with_minter',
          constructorArgs: {
            name: config.contracts.tokens.dai.name,
            symbol: config.contracts.tokens.dai.symbol,
            decimals: config.contracts.tokens.dai.decimals,
            minter: addresses.dripper,
            upgrade_authority: addresses.upgradeAuthority,
          },
        },
        {
          address: addresses.usdc,
          salt: config.contracts.tokens.usdc.salt,
          deployer: UNIVERSAL_DEPLOYER,
          constructorArtifact: 'constructor_with_minter',
          constructorArgs: {
            name: config.contracts.tokens.usdc.name,
            symbol: config.contracts.tokens.usdc.symbol,
            decimals: config.contracts.tokens.usdc.decimals,
            minter: addresses.dripper,
            upgrade_authority: addresses.upgradeAuthority,
          },
        },
      ],
      dripper: {
        address: addresses.dripper,
        salt: config.contracts.dripper.salt,
        deployer: UNIVERSAL_DEPLOYER,
        constructorArtifact: 'constructor',
      },
    };

    logger.info('[DRY RUN] Deployment data:');
    logger.info(JSON.stringify(deploymentData, null, 4));

    if (options.output) {
      const jsonOutput = JSON.stringify(deploymentData, null, 4);
      mkdirSync(dirname(options.output), { recursive: true });
      writeFileSync(options.output, jsonOutput);
      logger.info(`[DRY RUN] Deployment data written to ${options.output}`);
    }

    return {};
  }

  try {
    const nodeUrl = config.network.nodeUrl;

    const deployerSecretStr = options.deployerSecret || process.env.DEPLOYER_SECRET;
    if (!deployerSecretStr) {
      throw new Error('Deployer secret is required (use --deployer-secret or DEPLOYER_SECRET env var)');
    }
    const deployerSecret = await poseidon2Hash([Fr.fromBufferReduce(Buffer.from(deployerSecretStr, 'utf8'))]);

    const node = createAztecNodeClient(nodeUrl);
    const pxe = await setupPXE(node, config);
    const deployer = await createAccount(pxe, node, deployerSecret);
    logger.info(`Deployer account: ${deployer.account.getAddress()}`);
    const sponsoredFeeOptions = await createSponsoredFeeOptions(pxe);

    const deployOptions: DeployOptions = {
      from: deployer.account.getAddress(),
      fee: sponsoredFeeOptions,
    };

    logger.info(`Deploying with account: ${deployer.account.getAddress().toString()}`);

    const upgradeAuthority = config.contracts.upgradeAuthority
      ? AztecAddress.fromString(config.contracts.upgradeAuthority)
      : AztecAddress.ZERO;

    if (config.contracts.upgradeAuthority) {
      logger.info(`Using upgrade authority: ${upgradeAuthority.toString()}`);
    } else {
      logger.info('No upgrade authority set (using zero address)');
    }

    const computedAddresses = await computeContractAddresses(config);
    logger.info('\n=== Computed Contract Addresses ===');
    logger.info(`Dripper: ${computedAddresses.dripper.toString()}`);
    logger.info(`WETH: ${computedAddresses.weth.toString()}`);
    logger.info(`DAI: ${computedAddresses.dai.toString()}`);
    logger.info(`USDC: ${computedAddresses.usdc.toString()}`);
    logger.info('===================================\n');

    let dripper: { contract: DripperContract; status: 'deployed' | 'existing' } | undefined;

    if (config.contracts.dripper.existingAddress) {
      logger.info(`Using existing dripper at ${config.contracts.dripper.existingAddress}`);
      const dripperAddress = config.contracts.dripper.existingAddress;

      const dripperInstance = await node.getContract(dripperAddress);
      if (!dripperInstance) throw new Error('Dripper not found');

      logger.info(`Dripper found at: ${dripperAddress.toString()}`);

      try {
        await pxe.registerContract({
          instance: dripperInstance,
          artifact: DripperContractArtifact,
        });
        logger.debug('Dripper registered with PXE');
      } catch (error) {
        logger.debug('Dripper already registered');
      }

      const dripperContract = await DripperContract.at(dripperAddress, deployer.wallet);
      dripper = { contract: dripperContract, status: 'existing' };
    } else {
      logger.info('Deploying or checking dripper contract...');
      const dripperSalt = new Fr(config.contracts.dripper.salt);
      dripper = await withRetry(
        () => deployDripper(deployer.wallet, node, pxe, dripperSalt, deployOptions),
        'Deploy Dripper',
        config.deployment.retryOptions,
      );
    }

    if (!dripper) {
      throw new Error('Dripper deployment failed');
    }

    logger.info('Deploying/checking token contracts...');

    const tokenEntries = Object.entries(config.contracts.tokens) as [string, TokenConfig][];
    const deployedTokens: Record<string, DeployedContract<TokenContract>> = {};

    for (const [key, tokenConfig] of tokenEntries) {
      const result = await deployTokenWithRetry(
        deployer.wallet,
        node,
        pxe,
        {
          name: tokenConfig.name,
          symbol: tokenConfig.symbol,
          decimals: tokenConfig.decimals,
          minter: dripper.contract.address,
          upgradeAuthority,
          salt: new Fr(tokenConfig.salt),
        },
        deployOptions,
        config.deployment.retryOptions,
      );

      deployedTokens[key] = result;

      if (result.status === 'deployed') {
        await sleep(config.deployment.deployDelay);
      }
    }

    logger.info('Deployment completed successfully!');

    const deployedContracts: DeployedContracts = {
      weth: deployedTokens['weth'],
      dai: deployedTokens['dai'],
      usdc: deployedTokens['usdc'],
      dripper,
      deployer: deployer.account,
    };

    return deployedContracts;
  } catch (error) {
    logger.error('Deployment failed:', error);
    throw error;
  }
}

const program = new Command();

program
  .name('deploy')
  .description('Deploy Aztec Standards contracts')
  .version(packageJson.version)
  .option('--deployer-secret <secret>', 'Deployer secret (or use DEPLOYER_SECRET env var)')
  .option('--dry-run', 'Show configuration without deploying')
  .option('--output <file>', 'Write deployment JSON to file')
  .option('-n, --network <network>', 'Target network: devnet-2, testnet, sandbox', 'devnet-2')
  .action(async (options: CLIOptions) => {
    try {
      const activeConfig = getConfig(options.network);

      const contracts = await deployContracts(options, activeConfig);
      logDeployedContracts(contracts);

      if (options.output && !options.dryRun) {
        const upgradeAuthority = activeConfig.contracts.upgradeAuthority
          ? AztecAddress.fromString(activeConfig.contracts.upgradeAuthority)
          : AztecAddress.ZERO;
        const deploymentData = getDeploymentData(contracts, activeConfig, upgradeAuthority);
        const jsonOutput = JSON.stringify(deploymentData, null, 4);
        mkdirSync(dirname(options.output), { recursive: true });
        writeFileSync(options.output, jsonOutput);
        logger.info(`Deployment data written to ${options.output}`);
      }

      process.exit(0);
    } catch (error) {
      logger.error('Deployment failed:', error);
      process.exit(1);
    }
  });

if (import.meta.url === `file://${process.argv[1]}`) {
  program.parse(process.argv);
}
