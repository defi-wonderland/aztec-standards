import {
  AccountWallet,
  AccountWalletWithSecretKey,
  AztecAddress,
  Contract,
  ContractBase,
  createLogger,
  createPXEClient,
  DeployOptions,
  Fr,
  getContractInstanceFromDeployParams,
  PXE,
  sleep,
  waitForPXE,
  WaitOpts,
} from '@aztec/aztec.js';
import { SponsoredFeePaymentMethod } from '@aztec/aztec.js/fee/testing';
import { getUnsafeSchnorrAccount } from '@aztec/accounts/single_key';
import { SponsoredFPCContract } from '@aztec/noir-contracts.js/SponsoredFPC';
import { SPONSORED_FPC_SALT } from '@aztec/constants';
import { type UserFeeOptions } from '@aztec/entrypoints/interfaces';
import { poseidon2Hash, poseidon2HashWithSeparator } from '@aztec/foundation/crypto';
import { TokenContract, TokenContractArtifact } from '../../artifacts/Token.js';
import { DripperContract, DripperContractArtifact } from '../../artifacts/Dripper.js';

const amt = (n: number = 1, decimals: number = 1) => {
  return BigInt(n * 10 ** decimals);
};

const logger = createLogger('aztec:deploy');

interface DeployedContracts {
  weth?: TokenContract;
  dai?: TokenContract;
  usdc?: TokenContract;
  dripper?: DripperContract;
  deployer?: AccountWalletWithSecretKey;
}

// const DRIPPER_ADDRESS = '0x2460b20e4a0ded84818a28cfc04448dc702c80188a36662258e256dd9854564b'
const DRIPPER_ADDRESS = '';
const DEPLOYER_SECRET = await poseidon2Hash([
  Fr.fromBufferReduce(Buffer.from('a highly secret string padpadpad', 'utf8')),
]);

const defaultWaitOptions: WaitOpts = {
  timeout: 600,
};

interface RetryOptions {
  maxRetries?: number;
  initialDelayMs?: number;
  backoffMultiplier?: number;
  maxDelayMs?: number;
}

const defaultRetryOptions: RetryOptions = {
  maxRetries: 3,
  initialDelayMs: 5000,
  backoffMultiplier: 2,
  maxDelayMs: 30000,
};

async function withRetry<T>(
  operation: () => Promise<T>,
  operationName: string,
  options: RetryOptions = {},
): Promise<T> {
  const { maxRetries, initialDelayMs, backoffMultiplier, maxDelayMs } = {
    ...defaultRetryOptions,
    ...options,
  };

  let lastError: Error;
  let delayMs = initialDelayMs!;

  for (let attempt = 1; attempt <= maxRetries!; attempt++) {
    try {
      logger.info(`${operationName}: Attempt ${attempt}/${maxRetries}`);
      return await operation();
    } catch (error) {
      lastError = error as Error;
      logger.warn(`${operationName}: Attempt ${attempt} failed:`, error);

      if (attempt < maxRetries!) {
        const actualDelay = Math.min(delayMs, maxDelayMs!);
        logger.info(`${operationName}: Retrying in ${actualDelay / 1000} seconds...`);
        await sleep(actualDelay);
        delayMs *= backoffMultiplier!;
      }
    }
  }

  logger.error(`${operationName}: All ${maxRetries} attempts failed`);
  throw lastError!;
}

export function logDeployedContracts(contracts: DeployedContracts): void {
  logger.info('Deployed contracts:');

  for (const [key, value] of Object.entries(contracts)) {
    if (value instanceof ContractBase) {
      console.log(`${key}: ${value?.address.toString()}`);
    } else {
      console.log(`${key}: ${value}`);
    }
  }
}

export interface TokenDeployParams {
  name: string;
  symbol: string;
  decimals: number;
  minter?: AztecAddress;
  upgradeAuthority?: AztecAddress;
}

export async function setupPXE(): Promise<PXE> {
  const pxeUrl = process.env.PXE_URL || 'http://localhost:8081';
  logger.info(`Setting up PXE to ${pxeUrl}...`);
  const pxe = createPXEClient(pxeUrl);

  try {
    await waitForPXE(pxe, logger);
    logger.info('Connected to PXE');

    const nodeInfo = await pxe.getNodeInfo();
    logger.info(`Connected to Aztec node version: ${nodeInfo.nodeVersion}`);

    return pxe;
  } catch (error) {
    logger.error('Failed to connect to PXE:', error);
    throw error;
  }
}

export async function createAccount(pxe: PXE): Promise<AccountWalletWithSecretKey> {
  logger.info('Creating account...');

  // const contracts = await pxe.getContracts();
  // console.log(contracts.map(c => c.toString()));
  // let accounts = await pxe.getRegisteredAccounts();
  // console.log(accounts.map(a => a.toString()));

  let secret: Fr;
  if (!DEPLOYER_SECRET) {
    console.log('No DEPLOYER_SECRET found, generating random secret');
    secret = Fr.random();
    console.log(`Random secret: ${secret.toString()}`);
  } else {
    console.log('Using DEPLOYER_SECRET');
    secret = DEPLOYER_SECRET;
  }
  // const secret = DEPLOYER_SECRET || Fr.random();
  const manager = await getUnsafeSchnorrAccount(pxe, secret, Fr.ZERO);
  const wallet = await manager.register();

  // accounts = await pxe.getRegisteredAccounts();
  // console.log(accounts.map(a => a.toString()));

  logger.info(`Account created: ${wallet.getAddress().toString()}`);
  return wallet;
}

export async function createSponsoredFeeOptions(pxe: PXE): Promise<UserFeeOptions> {
  logger.info('Setting up sponsored fee options...');

  const sponsoredFPCInstance = await getContractInstanceFromDeployParams(SponsoredFPCContract.artifact, {
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
    estimateGas: true,
  };
}

export async function deployToken(
  deployer: AccountWallet,
  params: TokenDeployParams,
  options: DeployOptions,
): Promise<TokenContract> {
  logger.info(`Deploying Token: ${params.name} (${params.symbol})`);
  console.log(params);
  const minter = params.minter || deployer.getAddress();
  const upgradeAuthority = params.upgradeAuthority || AztecAddress.ZERO;

  const contract = await Contract.deploy(
    deployer,
    TokenContractArtifact,
    [params.name, params.symbol, params.decimals, minter, upgradeAuthority],
    'constructor_with_minter',
  )
    .send(options)
    .deployed(defaultWaitOptions);

  const tokenContract = await TokenContract.at(contract.address, deployer);
  logger.info(`Token deployed at: ${contract.address.toString()}`);

  return tokenContract;
}

export async function deployDefaultToken(
  pxe: PXE,
  deployer: AccountWallet,
  name: string = 'Private Token',
  symbol: string = 'PT',
  decimals: number = 18,
  options?: DeployOptions,
): Promise<TokenContract> {
  const sponsoredFeeOptions = await createSponsoredFeeOptions(pxe);

  const deployOptions: DeployOptions = {
    fee: sponsoredFeeOptions,
    universalDeploy: true,
    ...options,
  };

  const tokenParams: TokenDeployParams = {
    name,
    symbol,
    decimals,
    minter: deployer.getAddress(),
    upgradeAuthority: AztecAddress.ZERO,
  };

  return deployToken(deployer, tokenParams, deployOptions);
}

export async function deployDripper(deployer: AccountWallet, options: DeployOptions): Promise<DripperContract> {
  logger.info('Deploying Dripper contract...');

  const contract = await Contract.deploy(deployer, DripperContractArtifact, [], 'constructor')
    .send(options)
    .deployed(defaultWaitOptions);

  const dripperContract = await DripperContract.at(contract.address, deployer);
  logger.info(`Dripper deployed at: ${contract.address.toString()}`);
  await sleep(24000);
  return dripperContract;
}

export async function dripToPublic(
  dripper: DripperContract,
  tokenAddress: AztecAddress,
  amount: bigint,
  fromWallet: AccountWallet,
  options: DeployOptions,
): Promise<void> {
  logger.info(`Dripping ${amount} tokens to public balance for ${tokenAddress.toString()}`);

  const dripperWithWallet = await DripperContract.at(dripper.address, fromWallet);

  const tx = await dripperWithWallet.methods
    .drip_to_public(tokenAddress, amount)
    .send(options)
    .wait(defaultWaitOptions);

  logger.info(`Public drip completed, tx hash: ${tx.txHash.toString()}`);
}

export async function dripToPrivate(
  dripper: DripperContract,
  tokenAddress: AztecAddress,
  amount: bigint,
  fromWallet: AccountWallet,
  options: DeployOptions,
): Promise<void> {
  logger.info(`Dripping ${amount} tokens to private balance for ${tokenAddress.toString()}`);

  const dripperWithWallet = await DripperContract.at(dripper.address, fromWallet);

  const sendOptions = options;
  const waitOptions = defaultWaitOptions;

  const tx = await dripperWithWallet.methods.drip_to_private(tokenAddress, amount).send(sendOptions).wait(waitOptions);

  logger.info(`Private drip completed, tx hash: ${tx.txHash.toString()}`);
}

export async function deployTokenWithRetry(
  deployer: AccountWallet,
  params: TokenDeployParams,
  options: DeployOptions,
  retryOptions?: RetryOptions,
): Promise<TokenContract> {
  return withRetry(
    () => deployToken(deployer, params, options),
    `Deploy Token ${params.name} (${params.symbol})`,
    retryOptions,
  );
}

export async function deployDripperWithRetry(
  deployer: AccountWallet,
  options: DeployOptions,
  retryOptions?: RetryOptions,
): Promise<DripperContract> {
  return withRetry(() => deployDripper(deployer, options), 'Deploy Dripper', retryOptions);
}

export async function dripToPublicWithRetry(
  dripper: DripperContract,
  tokenAddress: AztecAddress,
  amount: bigint,
  fromWallet: AccountWallet,
  options: DeployOptions,
  retryOptions?: RetryOptions,
): Promise<void> {
  return withRetry(
    () => dripToPublic(dripper, tokenAddress, amount, fromWallet, options),
    `Drip to public for ${tokenAddress.toString()}`,
    retryOptions,
  );
}

export async function dripToPrivateWithRetry(
  dripper: DripperContract,
  tokenAddress: AztecAddress,
  amount: bigint,
  fromWallet: AccountWallet,
  options: DeployOptions,
  retryOptions?: RetryOptions,
): Promise<void> {
  return withRetry(
    () => dripToPrivate(dripper, tokenAddress, amount, fromWallet, options),
    `Drip to private for ${tokenAddress.toString()}`,
    retryOptions,
  );
}

export async function deployToTestnet(): Promise<DeployedContracts> {
  logger.info('Deploying to Aztec Testnet...');

  try {
    const pxe = await setupPXE();
    const deployer = await createAccount(pxe);
    const sponsoredFeeOptions = await createSponsoredFeeOptions(pxe);

    const deployOptions: DeployOptions = {
      fee: sponsoredFeeOptions,
      universalDeploy: true,
    };

    logger.info(`Deploying with account: ${deployer.getAddress().toString()}`);

    // Deploy dripper first, as it will be the token's minter
    let dripper: DripperContract;
    if (DRIPPER_ADDRESS) {
      logger.info(`Using existing dripper at ${DRIPPER_ADDRESS}`);
      dripper = await DripperContract.at(AztecAddress.fromString(DRIPPER_ADDRESS), deployer);
      logger.info(`Dripper at: ${dripper.address.toString()}`);
      try {
        await pxe.registerContract({
          instance: dripper.instance,
          artifact: DripperContractArtifact,
        });
      } catch (error) {
        logger.debug('Dripper already registered');
      }
    } else {
      dripper = await deployDripperWithRetry(deployer, deployOptions);
    }

    // Deploy token with dripper as the minter
    // const tokenParams: TokenDeployParams = {
    //   name: 'Private Token',
    //   symbol: 'PT',
    //   decimals: 18,
    //   minter: dripper.address,
    //   upgradeAuthority: AztecAddress.ZERO,
    // };

    const weth = await deployTokenWithRetry(
      deployer,
      {
        name: 'WETH',
        symbol: 'WETH',
        decimals: 18,
        minter: dripper.address,
        upgradeAuthority: AztecAddress.ZERO,
      },
      deployOptions,
    );
    await sleep(24000);
    const dai = await deployTokenWithRetry(
      deployer,
      {
        name: 'DAI',
        symbol: 'DAI',
        decimals: 9,
        minter: dripper.address,
        upgradeAuthority: AztecAddress.ZERO,
      },
      deployOptions,
    );
    const usdc = await deployTokenWithRetry(
      deployer,
      {
        name: 'USDC',
        symbol: 'USDC',
        decimals: 6,
        minter: dripper.address,
        upgradeAuthority: AztecAddress.ZERO,
      },
      deployOptions,
    );

    await dripToPublicWithRetry(dripper, weth.address, amt(1), deployer, deployOptions);
    await dripToPublicWithRetry(dripper, dai.address, amt(1000, 9), deployer, deployOptions);
    await dripToPublicWithRetry(dripper, usdc.address, amt(1000, 6), deployer, deployOptions);
    await dripToPrivateWithRetry(dripper, weth.address, amt(1), deployer, deployOptions);
    await dripToPrivateWithRetry(dripper, dai.address, amt(1000, 9), deployer, deployOptions);
    await dripToPrivateWithRetry(dripper, usdc.address, amt(1000, 6), deployer, deployOptions);

    logger.info(`Token minter set to Dripper: ${dripper.address.toString()}`);

    logger.info('Testnet deployment completed successfully!');

    return {
      weth,
      dai,
      usdc,
      dripper,
      deployer,
    };
  } catch (error) {
    logger.error('Testnet deployment failed:', error);
    throw error;
  }
}

console.log('Deploying to testnet...');
if (import.meta.url === `file://${process.argv[1]}`) {
  deployToTestnet()
    .then((contracts) => {
      logDeployedContracts(contracts);
    })
    .catch((error) => {
      logger.error('Deployment failed:', error);
      process.exit(1);
    });
}
