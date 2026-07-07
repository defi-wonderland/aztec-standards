import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { MultiTokenContract } from '../src/artifacts/MultiToken.js';
import {
  deployMultiTokenWithMinter,
  initializeMultiTokenTransferCommitment,
  setupTestSuite,
  ID_A,
} from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface MultiTokenBenchmarkContext extends BenchmarkContext {
  cleanup: () => Promise<void>;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  multiTokenContract: MultiTokenContract;
  commitments: bigint[];
}

// --- Helper Functions ---

function amt(x: bigint | number) {
  // MultiToken carries NO decimals (its constructor takes only name/symbol/minter/auth_contract, unlike the
  // Token contract's `decimals` arg), so amounts are raw u128 values. We keep the sibling token benchmark's
  // magnitudes (mint 100, move 10) without the 10**18 scaling that `parseUnits` would apply.
  return BigInt(x);
}

// Use export default class extending Benchmark
export default class MultiTokenContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the MultiTokenContract.
   * Creates wallet, gets accounts, and deploys the contract.
   */
  async setup(): Promise<MultiTokenBenchmarkContext> {
    const { cleanup, wallet, accounts } = await setupTestSuite(true);
    const [deployer] = accounts;
    // minter = deployer, auth_contract = ZERO (ARC-403 hook disabled) — mirrors the default JS suite deploy.
    const multiTokenContract = await deployMultiTokenWithMinter(wallet, deployer, deployer, AztecAddress.ZERO);

    // Pre-initialize the partial notes consumed by transfer_private_to_commitment / transfer_public_to_commitment.
    // The commitment is id-agnostic (the completer binds the id at completion); the payer (alice) must be the
    // completer, and the note must come from a PRIOR settled tx (the helper settles each one).
    const [alice, bob] = accounts;
    const commitment_1 = await initializeMultiTokenTransferCommitment(multiTokenContract, alice, bob, alice);
    const commitment_2 = await initializeMultiTokenTransferCommitment(multiTokenContract, alice, bob, alice);

    const commitments = [commitment_1, commitment_2];

    return { cleanup, wallet, deployer, accounts, multiTokenContract, commitments };
  }

  /**
   * Returns the list of MultiTokenContract methods to be benchmarked.
   * Ordering matters: the mints seed the balances that the following transfers/burns/commitments spend.
   * Every op is an `alice` self-spend of token id `ID_A` (nonce = 0, so no authwit is needed).
   */
  getMethods(context: MultiTokenBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { multiTokenContract, accounts, wallet, commitments } = context;
    const [alice, bob] = accounts;
    const owner = alice;
    const id = ID_A;

    const methods: ContractFunctionInteractionCallIntent[] = [
      // Mint methods
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.mint_to_private(owner, id, amt(100)),
      },
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.mint_to_public(owner, id, amt(100)),
      },

      // Transfer methods
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.transfer_private_to_public(owner, bob, id, amt(10), 0),
      },
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.transfer_private_to_private(owner, bob, id, amt(10), 0),
      },
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.transfer_public_to_private(owner, bob, id, amt(10), 0),
      },
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.transfer_public_to_public(owner, bob, id, amt(10), 0),
      },

      // Burn methods
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.burn_private(owner, id, amt(10), 0),
      },
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.burn_public(owner, id, amt(10), 0),
      },

      // Partial notes methods
      {
        caller: alice,
        action: multiTokenContract.withWallet(wallet).methods.initialize_transfer_commitment(bob, owner),
      },
      {
        caller: alice,
        action: multiTokenContract
          .withWallet(wallet)
          .methods.transfer_private_to_commitment(owner, id, commitments[0], amt(10), 0),
      },
      {
        caller: alice,
        action: multiTokenContract
          .withWallet(wallet)
          .methods.transfer_public_to_commitment(owner, id, commitments[1], amt(10), 0),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: MultiTokenBenchmarkContext): Promise<void> {
    await context.cleanup();
  }
}
