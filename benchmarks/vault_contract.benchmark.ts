import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { AuthWitness } from '@aztec/aztec.js/authorization';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

import { parseUnits } from 'viem';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../src/artifacts/Token.js';
import { VaultContract } from '../src/artifacts/Vault.js';
import {
  ensureVaultContractClassPublished,
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  setupTestSuite,
} from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface TokenBenchmarkContext extends BenchmarkContext {
  cleanup: () => Promise<void>;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  vaultContract: VaultContract;
  assetContract: TokenContract;
  sharesContract: TokenContract;
  authWitnesses: AuthWitness[];
  burnAuthWitnesses: AuthWitness[];
}

// --- Helper Functions ---

function amt(x: bigint | number | string) {
  // Using 6 decimals for this token to avoid running into overflows during asset-share conversion
  return parseUnits(x.toString(), 6);
}

// Use export default class extending Benchmark
export default class TokenContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the Vault.
   * Creates wallet, gets accounts, and deploys the vault + asset + shares contracts.
   */
  async setup(): Promise<TokenBenchmarkContext> {
    const { cleanup, wallet, accounts } = await setupTestSuite(true);
    const [deployer] = accounts;
    const bob = accounts[1];
    await ensureVaultContractClassPublished(wallet, deployer);
    const [vaultContract, assetContract, sharesContract] = await deployVaultAndAssetWithMinter(wallet, deployer);
    const assetMethods = assetContract.withWallet(wallet).methods;
    const sharesMethods = sharesContract.withWallet(wallet).methods;

    // Mint initial asset supply to the deployer
    await assetMethods.mint_to_public(deployer, amt(100)).send({ from: deployer });
    for (let i = 0; i < 6; i++) {
      // 1 Note per benchmark test so that a single full Note is used in each.
      await assetMethods.mint_to_private(deployer, amt(1)).send({ from: deployer });
    }

    // Initialize shares total supply by depositing 1 asset and sending 1 share to the zero address
    let action = assetMethods.transfer_public_to_public(deployer, vaultContract.address, amt(1), 1234);
    await setPublicAuthWit(vaultContract.address, action, deployer, wallet);
    await vaultContract
      .withWallet(wallet)
      .methods.deposit_public_to_public(deployer, AztecAddress.ZERO, amt(1), 1234)
      .send({ from: deployer });

    /* ======================= PUBLIC ASSET AUTHWITS ========================== */

    // Set public authwitness for the `transfer_public_to_public` method on the Asset contract to be used by the
    // Vault's following methods:
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

    /* ======================= PRIVATE ASSET AUTHWITS ========================= */

    // Prepare private authwitness for the `transfer_private_to_public` method on the Asset contract to be used by the
    // Vault's following methods:
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

    /* ======================= PUBLIC SHARES AUTHWITS ========================= */

    // Set public authwitness for the `burn_public` method on the Shares contract
    // to be used by the Vault's withdraw/redeem methods that burn public shares.
    // Each uses a unique nonce (200-203) since authwits are consumed on use.
    // 1. withdraw_public_to_public (nonce 200)
    // 2. withdraw_public_to_private (nonce 201, burn happens in settlement)
    // 3. redeem_public_to_public (nonce 202)
    // 4. redeem_public_to_private_exact (nonce 203, burn happens in settlement)
    for (let i = 0; i < 4; i++) {
      const nonce = 200 + i;
      action = sharesMethods.burn_public(bob, amt(1), nonce);
      await setPublicAuthWit(vaultContract.address, action, bob, wallet);
    }

    /* ======================= PRIVATE SHARES AUTHWITS ======================== */

    // Prepare private authwitness for the `burn_private` method on the Shares contract
    // to be used by the Vault's withdraw/redeem methods that burn private shares.
    // Each uses a unique nonce (300-304) since authwits are consumed on use.
    // 1. withdraw_private_to_private (nonce 300)
    // 2. withdraw_private_to_public_exact (nonce 301)
    // 3. withdraw_private_to_private_exact (nonce 302)
    // 4. redeem_private_to_public (nonce 303)
    // 5. redeem_private_to_private_exact (nonce 304)
    const burnAuthWitnesses: AuthWitness[] = [];
    for (let i = 0; i < 5; i++) {
      const nonce = 300 + i;
      action = sharesMethods.burn_private(bob, amt(1), nonce);
      const authWitness = await setPrivateAuthWit(vaultContract.address, action, bob, wallet);
      burnAuthWitnesses.push(authWitness);
    }

    return {
      cleanup,
      wallet,
      deployer,
      accounts,
      vaultContract,
      assetContract,
      sharesContract,
      authWitnesses,
      burnAuthWitnesses,
    };
  }

  /**
   * Returns the list of Vault methods to be benchmarked.
   */
  getMethods(context: TokenBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { vaultContract, deployer, accounts, authWitnesses, burnAuthWitnesses, wallet } = context;
    const alice = deployer;
    const bob = accounts[1];

    let publicNonce = 0;
    let privateNonce = 100;

    const methods: ContractFunctionInteractionCallIntent[] = [
      // Deposit methods
      {
        caller: alice,
        action: vaultContract.withWallet(wallet).methods.deposit_public_to_public(alice, bob, amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_public_to_private(alice, bob, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_private_to_private(alice, bob, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[0]] }),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_private_to_public(alice, bob, amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[1]] }),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_public_to_private_exact(alice, bob, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.deposit_private_to_private_exact(alice, bob, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[2]] }),
      },

      // Issue methods
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_public_to_public(alice, bob, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_public_to_private(alice, bob, amt(1), amt(1), publicNonce++),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_private_to_public_exact(alice, bob, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[3]] }),
      },
      {
        caller: alice,
        action: vaultContract
          .withWallet(wallet)
          .methods.issue_private_to_private_exact(alice, bob, amt(1), amt(1), privateNonce++)
          .with({ authWitnesses: [authWitnesses[4]] }),
      },

      // Withdraw methods
      // Nonces 200-201/300-302 are used for burn authwits on the shares token.
      // The vault passes _nonce through to shares.burn_public/burn_private.
      {
        caller: bob,
        action: vaultContract.withWallet(wallet).methods.withdraw_public_to_public(bob, alice, amt(1), 200),
      },
      {
        caller: bob,
        action: vaultContract.withWallet(wallet).methods.withdraw_public_to_private(bob, alice, amt(1), 201),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_private_to_private(bob, alice, amt(1), amt(1), 300)
          .with({ authWitnesses: [burnAuthWitnesses[0]] }),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_private_to_public_exact(bob, alice, amt(1), amt(1), 301)
          .with({ authWitnesses: [burnAuthWitnesses[1]] }),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.withdraw_private_to_private_exact(bob, alice, amt(1), amt(1), 302)
          .with({ authWitnesses: [burnAuthWitnesses[2]] }),
      },

      // Redeem methods
      // Nonces 202-203/303-304 are used for burn authwits on the shares token.
      {
        caller: bob,
        action: vaultContract.withWallet(wallet).methods.redeem_public_to_public(bob, alice, amt(1), 202),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.redeem_private_to_public(bob, alice, amt(1), 303)
          .with({ authWitnesses: [burnAuthWitnesses[3]] }),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.redeem_private_to_private_exact(bob, alice, amt(1), amt(1), 304)
          .with({ authWitnesses: [burnAuthWitnesses[4]] }),
      },
      {
        caller: bob,
        action: vaultContract
          .withWallet(wallet)
          .methods.redeem_public_to_private_exact(bob, alice, amt(1), amt(1), 203),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: TokenBenchmarkContext): Promise<void> {
    await context.cleanup();
  }
}
