import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';
import { Fr } from '@aztec/aztec.js/fields';
import { getInitialTestAccountsData } from '@aztec/accounts/testing/lazy';
import { poseidon2Hash } from '@aztec/foundation/crypto/poseidon';
import { Capsule } from '@aztec/stdlib/tx';

import { parseUnits } from 'viem';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../src/artifacts/Token.js';
import { deployTokenWithMinter, initializeTransferCommitment, setupTestSuite } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface TokenBenchmarkContext extends BenchmarkContext {
  cleanup: () => Promise<void>;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  tokenContract: TokenContract;
  commitments: bigint[];
  privateSpendLabel: Fr;
}

// --- Helper Functions ---

const COUNTER_LABEL_SEPARATOR = 0x434f554e544552n;
const SPEND_LABELS_BASE_SLOT = 0x10000000n;

function amt(x: bigint | number | string) {
  // Using 18 decimals as standard for Token examples
  return parseUnits(x.toString(), 18);
}

async function publicOriginLabel(counter: bigint) {
  return await poseidon2Hash([new Fr(COUNTER_LABEL_SEPARATOR), new Fr(counter)]);
}

function spendLabelCapsules(tokenAddress: AztecAddress, account: AztecAddress, label: Fr) {
  return [
    new Capsule(tokenAddress, new Fr(SPEND_LABELS_BASE_SLOT), [new Fr(1)], account),
    new Capsule(tokenAddress, new Fr(SPEND_LABELS_BASE_SLOT + 1n), [label], account),
  ];
}

// Use export default class extending Benchmark
export default class TokenContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates wallet, gets accounts, and deploys the contract.
   */

  async setup(): Promise<TokenBenchmarkContext> {
    const { cleanup, wallet, accounts } = await setupTestSuite(true);
    const [deployer] = accounts;
    const deployedBaseContract = await deployTokenWithMinter(wallet, deployer);
    const tokenContract = TokenContract.at(deployedBaseContract.address, wallet);

    // Initialize partial notes
    const [alice] = accounts;
    const owner = alice;
    // We need an account manager to decrypt the private logs in the initializeTransferCommitment function
    const secret = Fr.random();
    const salt = Fr.random();
    const commitmentRecipientAccountManager = await wallet.createSchnorrAccount(secret, salt);
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

    // Private spends now require an explicit spend-label capsule. Fund Alice through a public
    // commitment so the resulting private label is deterministic: H(public label counter = 1).
    const [initialAccount] = await getInitialTestAccountsData();
    const aliceAccountManager = await wallet.createSchnorrAccount(
      initialAccount.secret,
      initialAccount.salt,
      initialAccount.signingKey,
    );
    const aliceCommitment = await initializeTransferCommitment(tokenContract, alice, aliceAccountManager, alice);
    await tokenContract.methods.mint_to_public(alice, amt(1_000)).send({ from: alice });
    await tokenContract.methods
      .transfer_public_to_commitment(alice, aliceCommitment, amt(500), 0)
      .send({ from: alice });

    const privateSpendLabel = await publicOriginLabel(1n);

    return { cleanup, wallet, deployer, accounts, tokenContract, commitments, privateSpendLabel };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: TokenBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { tokenContract, accounts, wallet, commitments, privateSpendLabel } = context;
    const [alice, bob] = accounts;
    const owner = alice;
    const spendCapsules = spendLabelCapsules(tokenContract.address, owner, privateSpendLabel);

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
        action: tokenContract
          .withWallet(wallet)
          .methods.transfer_private_to_public(owner, bob, amt(10), 0)
          .with({ capsules: spendCapsules }),
      },
      {
        caller: alice,
        action: tokenContract
          .withWallet(wallet)
          .methods.transfer_private_to_public_with_commitment(owner, bob, amt(10), 0)
          .with({ capsules: spendCapsules }),
      },
      {
        caller: alice,
        action: tokenContract
          .withWallet(wallet)
          .methods.transfer_private_to_private(owner, bob, amt(10), 0)
          .with({ capsules: spendCapsules }),
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
        action: tokenContract
          .withWallet(wallet)
          .methods.burn_private(owner, amt(10), 0)
          .with({ capsules: spendCapsules }),
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
          .methods.transfer_private_to_commitment(owner, commitments[0], amt(10), 0)
          .with({ capsules: spendCapsules }),
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
    await context.cleanup();
  }
}
