import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import type { AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

import { parseUnits } from 'viem';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../artifacts/Token.js';
import { deployTokenWithMinter, initializeTransferCommitment, setupTestSuite } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface TokenBenchmarkContext extends BenchmarkContext {
  store: AztecLMDBStoreV2;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  tokenContract: TokenContract;
  commitments: bigint[];
}

// --- Helper Functions ---

function amt(x: bigint | number | string) {
  // Using 18 decimals as standard for Token examples
  return parseUnits(x.toString(), 18);
}

// Use export default class extending Benchmark
export default class TokenContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates wallet, gets accounts, and deploys the contract.
   */

  async setup(): Promise<TokenBenchmarkContext> {
    const { store, wallet, accounts } = await setupTestSuite('bench-token', true);
    const [deployer] = accounts;
    const deployedBaseContract = await deployTokenWithMinter(wallet, deployer);
    const tokenContract = TokenContract.at(deployedBaseContract.address, wallet);

    // Initialize partial notes
    const [alice] = accounts;
    const owner = alice;
    // We need an account manager to decrypt the private logs in the initializeTransferCommitment function
    const commitmentRecipientAccountManager = await wallet.createAccount();
    const commitment_1 = await initializeTransferCommitment(
      tokenContract,
      alice,
      commitmentRecipientAccountManager,
      owner,
    );
    const commitment_2 = await initializeTransferCommitment(
      tokenContract,
      alice,
      commitmentRecipientAccountManager,
      owner,
    );

    const commitments = [commitment_1, commitment_2];

    return { store, wallet, deployer, accounts, tokenContract, commitments };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: TokenBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { tokenContract, accounts, wallet, commitments } = context;
    const [alice, bob] = accounts;
    const owner = alice;

    const methods: ContractFunctionInteractionCallIntent[] = [
      // Mint methods
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.mint_to_private(owner, amt(100)),
      },
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.mint_to_public(owner, amt(100)),
      },
      // Transfer methods
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.transfer_private_to_public(owner, bob, amt(10), 0),
      },
      {
        caller: alice,
        action: tokenContract
          .withWallet(wallet)
          .methods.transfer_private_to_public_with_commitment(owner, bob, amt(10), 0),
      },
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.transfer_private_to_private(owner, bob, amt(10), 0),
      },
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.transfer_public_to_private(owner, bob, amt(10), 0),
      },
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.transfer_public_to_public(owner, bob, amt(10), 0),
      },

      // Burn methods
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.burn_private(owner, amt(10), 0),
      },
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.burn_public(owner, amt(10), 0),
      },

      // Partial notes methods
      {
        caller: alice,
        action: tokenContract.withWallet(wallet).methods.initialize_transfer_commitment(bob, owner),
      },
      {
        caller: alice,
        action: tokenContract
          .withWallet(wallet)
          .methods.transfer_private_to_commitment(owner, commitments[0], amt(10), 0),
      },
      {
        caller: alice,
        action: tokenContract
          .withWallet(wallet)
          .methods.transfer_public_to_commitment(owner, commitments[1], amt(10), 0),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: TokenBenchmarkContext): Promise<void> {
    await context.store.delete();
  }
}
