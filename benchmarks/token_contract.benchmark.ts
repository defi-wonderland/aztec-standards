import { type AccountWallet, type ContractFunctionInteraction, type PXE } from '@aztec/aztec.js';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { parseUnits } from 'viem';
import { decodeFromAbi } from '@aztec/stdlib/abi';
import { Fr } from '@aztec/foundation/fields';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../artifacts/Token.js';
import { deployTokenWithMinter, initializeTransferCommitment, setupPXE } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface TokenBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
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
   * Creates PXE client, gets accounts, and deploys the contract.
   */

  async setup(): Promise<TokenBenchmarkContext> {
    const { pxe, store } = await setupPXE();
    const managers = await getInitialTestAccountsManagers(pxe);
    const accounts = await Promise.all(managers.map((acc) => acc.register()));
    const [deployer] = accounts;
    const deployedBaseContract = await deployTokenWithMinter(deployer);
    const tokenContract = await TokenContract.at(deployedBaseContract.address, deployer);

    // Initialize partial notes
    const [alice, bob] = accounts;
    const owner = alice.getAddress();
    const commitment_1 = await initializeTransferCommitment(tokenContract, alice, owner, bob.getAddress(), owner);
    const commitment_2 = await initializeTransferCommitment(tokenContract, alice, owner, bob.getAddress(), owner);

    const commitments = [commitment_1, commitment_2];

    return { pxe, deployer, accounts, tokenContract, commitments };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: TokenBenchmarkContext): ContractFunctionInteraction[] {
    const { tokenContract, accounts, commitments } = context;
    const [alice, bob] = accounts;
    const owner = alice.getAddress();

    const methods: ContractFunctionInteraction[] = [
      // Mint methods
      tokenContract.withWallet(alice).methods.mint_to_private(owner, owner, amt(100)),
      tokenContract.withWallet(alice).methods.mint_to_public(owner, amt(100)),
      // Transfer methods
      tokenContract.withWallet(alice).methods.transfer_private_to_public(owner, bob.getAddress(), amt(10), 0),
      tokenContract
        .withWallet(alice)
        .methods.transfer_private_to_public_with_commitment(owner, bob.getAddress(), amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_private_to_private(owner, bob.getAddress(), amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_public_to_private(owner, bob.getAddress(), amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_public_to_public(owner, bob.getAddress(), amt(10), 0),

      // Burn methods
      tokenContract.withWallet(alice).methods.burn_private(owner, amt(10), 0),
      tokenContract.withWallet(alice).methods.burn_public(owner, amt(10), 0),

      // Partial notes methods
      tokenContract.withWallet(alice).methods.initialize_transfer_commitment(owner, bob.getAddress(), owner),
      tokenContract.withWallet(alice).methods.transfer_private_to_commitment(owner, commitments[0], amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_public_to_commitment(owner, commitments[1], amt(10), 0),
    ];

    return methods.filter(Boolean);
  }
}
