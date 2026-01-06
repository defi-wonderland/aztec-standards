import type { PXE } from '@aztec/pxe/server';
import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { AuthWitness } from '@aztec/aztec.js/authorization';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

import { parseUnits } from 'viem';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../artifacts/Token.js';
import {
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  setupTestSuite,
} from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface TokenBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  vaultContract: TokenContract;
  assetContract: TokenContract;
  authWitnesses: AuthWitness[];
}

// --- Helper Functions ---

function amt(x: bigint | number | string) {
  // Using 6 decimals for this token to avoid running into overflows during asset-share conversion
  return parseUnits(x.toString(), 6);
}

// Use export default class extending Benchmark
export default class TokenContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<TokenBenchmarkContext> {
    const { pxe, wallet, accounts } = await setupTestSuite();
    const [deployer] = accounts;
    const [deployedBaseContract, deployedAssetContract] = await deployVaultAndAssetWithMinter(wallet, deployer);
    const vaultContract = await TokenContract.at(deployedBaseContract.address, wallet);
    const assetContract = await TokenContract.at(deployedAssetContract.address, wallet);
    const assetMethods = assetContract.withWallet(wallet).methods;

    // Mint initial asset supply to the deployer
    await assetContract.withWallet(wallet).methods.mint_to_public(deployer, amt(100)).send({ from: deployer }).wait();
    for (let i = 0; i < 6; i++) {
      // 1 Note per benchmark test so that a single full Note is used in each.
      await assetContract.withWallet(wallet).methods.mint_to_private(deployer, amt(1)).send({ from: deployer }).wait();
    }

    // Initialize shares total supply by depositing 1 asset and sending 1 share to the zero address
    let action = assetMethods.transfer_public_to_public(deployer, vaultContract.address, amt(1), 1234);
    await setPublicAuthWit(vaultContract.address, action, deployer, wallet);
    await vaultContract
      .withWallet(wallet)
      .methods.deposit_public_to_public(deployer, AztecAddress.ZERO, amt(1), 1234)
      .send({ from: deployer })
      .wait();

    /* ======================= PUBLIC AUTHWITS ========================== */

    // Set public authwitness for the `transfer_public_to_public` method on the Asset contract to be used by the
    // Tokenized Vault's following methods:
    // 1. deposit_public_to_public
    // 2. deposit_public_to_private
    // 3. deposit_public_to_private_exact
    // 4. issue_public_to_public
    // 5. issue_public_to_private
    for (let i = 0; i < 5; i++) {
      const nonce = i;
      action = assetMethods.transfer_public_to_public(deployer, vaultContract.address, amt(1), nonce);
      await setPublicAuthWit(vaultContract.address, action, deployer, wallet);
    }

    /* ======================= PRIVATE AUTHWITS ========================= */

    // Prepare private authwitness for the `transfer_private_to_public` method on the Asset contract to be used by the
    // Tokenized Vault's following methods:
    // 1. deposit_private_to_private
    // 2. deposit_private_to_public
    // 3. deposit_private_to_private_exact
    // 4. issue_private_to_public_exact
    // 5. issue_private_to_private_exact
    const authWitnesses: AuthWitness[] = [];
    for (let i = 0; i < 5; i++) {
      const nonce = 100 + i;
      action = assetMethods.transfer_private_to_public(deployer, vaultContract.address, amt(1), nonce);
      const authWitness = await setPrivateAuthWit(vaultContract.address, action, deployer, wallet);
      authWitnesses.push(authWitness);
    }

    return { pxe, wallet, deployer, accounts, vaultContract, assetContract, authWitnesses };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: TokenBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { vaultContract, deployer, accounts, authWitnesses, wallet } = context;
    const alice = deployer;
    const bob = accounts[1];
    const aliceAddress = alice;
    const bobAddress = bob;

    let publicNonce = 0;
    let privateNonce = 100;

    const methods: ContractFunctionInteractionCallIntent[] = [
      // Deposit methods
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_public_to_public(aliceAddress, bobAddress, amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_public_to_private(aliceAddress, bobAddress, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_private_to_private(aliceAddress, bobAddress, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[0]] }),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_private_to_public(aliceAddress, bobAddress, amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[1]] }),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_public_to_private_exact(aliceAddress, bobAddress, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_private_to_private_exact(aliceAddress, bobAddress, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[2]] }),
      },

      // Issue methods
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_public_to_public(aliceAddress, bobAddress, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_public_to_private(aliceAddress, bobAddress, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_private_to_public_exact(aliceAddress, bobAddress, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[3]] }),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_private_to_private_exact(aliceAddress, bobAddress, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[4]] }),
      },

      // Withdraw methods
      {
        caller: bob,
        action: vaultContract.withWallet(wallet).methods.withdraw_public_to_public(bobAddress, aliceAddress, amt(1), 0),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_public_to_private(bobAddress, aliceAddress, amt(1), 0),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_private_to_private(bobAddress, aliceAddress, amt(1), amt(1), 0),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_private_to_public_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_private_to_private_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),
      },

      // Redeem methods
      {
        caller: bob,
        action: vaultContract.withWallet(wallet).methods.redeem_public_to_public(bobAddress, aliceAddress, amt(1), 0),
      },
      {
        caller: bob,
        action: vaultContract.withWallet(wallet).methods.redeem_private_to_public(bobAddress, aliceAddress, amt(1), 0),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.redeem_private_to_private_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.redeem_public_to_private_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),
      },
    ];

    return methods.filter(Boolean);
  }
}
