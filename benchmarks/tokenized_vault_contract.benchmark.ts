import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { AuthWitness } from '@aztec/aztec.js/authorization';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

import { parseUnits } from 'viem';

import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../src/artifacts/Token.js';
import { TokenizedVaultContract } from '../src/artifacts/TokenizedVault.js';
import {
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  setupTestSuite,
} from '../src/ts/test/utils.js';

interface TokenizedVaultBenchmarkContext extends BenchmarkContext {
  cleanup: () => Promise<void>;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  vaultContract: TokenizedVaultContract;
  assetContract: TokenContract;
  vaultTokenContract: TokenContract;
  privateDepositAuthWitness: AuthWitness;
}

function amt(x: bigint | number | string) {
  return parseUnits(x.toString(), 6);
}

const NONCES = {
  seedDeposit: 900,
  publicDeposit: 901,
  privateDeposit: 902,
  issue: 903,
  withdraw: 904,
  redeem: 905,
} as const;

export default class TokenizedVaultContractBenchmark extends Benchmark {
  async setup(): Promise<TokenizedVaultBenchmarkContext> {
    const { cleanup, wallet, accounts } = await setupTestSuite(true);
    const [deployer] = accounts;

    const { vaultContract, assetContract, vaultTokenContract } = await deployVaultAndAssetWithMinter(wallet, deployer);

    await assetContract.withWallet(wallet).methods.mint_to_public(deployer, amt(20)).send({ from: deployer });
    await assetContract.withWallet(wallet).methods.mint_to_private(deployer, amt(1)).send({ from: deployer });

    const seedTransfer = assetContract
      .withWallet(wallet)
      .methods.transfer_public_to_public(deployer, vaultContract.address, amt(1), NONCES.seedDeposit);
    await setPublicAuthWit(vaultContract.address, seedTransfer, deployer, wallet);
    await vaultContract
      .withWallet(wallet)
      .methods.deposit_public_to_public(deployer, AztecAddress.ZERO, amt(1), NONCES.seedDeposit)
      .send({ from: deployer });

    const publicDepositTransfer = assetContract
      .withWallet(wallet)
      .methods.transfer_public_to_public(deployer, vaultContract.address, amt(1), NONCES.publicDeposit);
    await setPublicAuthWit(vaultContract.address, publicDepositTransfer, deployer, wallet);

    const issueTransfer = assetContract
      .withWallet(wallet)
      .methods.transfer_public_to_public(deployer, vaultContract.address, amt(1), NONCES.issue);
    await setPublicAuthWit(vaultContract.address, issueTransfer, deployer, wallet);

    const privateDepositTransfer = assetContract
      .withWallet(wallet)
      .methods.transfer_private_to_public(deployer, vaultContract.address, amt(1), NONCES.privateDeposit);
    const privateDepositAuthWitness = await setPrivateAuthWit(
      vaultContract.address,
      privateDepositTransfer,
      deployer,
      wallet,
    );

    const withdrawBurn = vaultTokenContract.withWallet(wallet).methods.burn_public(deployer, amt(1), NONCES.withdraw);
    await setPublicAuthWit(vaultContract.address, withdrawBurn, deployer, wallet);

    const redeemBurn = vaultTokenContract.withWallet(wallet).methods.burn_public(deployer, amt(1), NONCES.redeem);
    await setPublicAuthWit(vaultContract.address, redeemBurn, deployer, wallet);

    return {
      cleanup,
      wallet,
      deployer,
      accounts,
      vaultContract,
      assetContract,
      vaultTokenContract,
      privateDepositAuthWitness,
    };
  }

  getMethods(context: TokenizedVaultBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { vaultContract, deployer, wallet, privateDepositAuthWitness } = context;

    return [
      {
        caller: deployer,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_public_to_public(deployer, deployer, amt(1), NONCES.publicDeposit),
      },
      {
        caller: deployer,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_private_to_public(deployer, deployer, amt(1), NONCES.privateDeposit)
          .with({ authWitnesses: [privateDepositAuthWitness] }),
      },
      {
        caller: deployer,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_public_to_public(deployer, deployer, amt(1), amt(1), NONCES.issue),
      },
      {
        caller: deployer,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_public_to_public(deployer, deployer, amt(1), NONCES.withdraw),
      },
      {
        caller: deployer,
        action: vaultContract
          .withWallet(wallet)
          .methods.redeem_public_to_public(deployer, deployer, amt(1), NONCES.redeem),
      },
    ];
  }

  async teardown(context: TokenizedVaultBenchmarkContext): Promise<void> {
    await context.cleanup();
  }
}
