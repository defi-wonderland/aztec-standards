import {
  type AccountWallet,
  type ContractFunctionInteraction,
  type PXE,
  createPXEClient,
} from '@aztec/aztec.js';
import { getInitialTestAccountsWallets } from '@aztec/accounts/testing';
import { parseUnits } from 'viem';

import { TokenContract } from '../artifacts/Token.js';
import { deployTokenWithMinter } from '../ts/test/utils.js';
import { type BenchmarkConfig } from '../../scripts/common.benchmark.js';

// Token-specific context extending the generic BenchmarkRunContext
interface TokenBenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  tokenContract: TokenContract;
}

// --- Helper Functions ---

function amt(x: bigint | number | string) {
  // Using 18 decimals as standard for Token examples
  return parseUnits(x.toString(), 18);
}

export const benchmarkConfig: BenchmarkConfig = {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  setup: async (): Promise<TokenBenchmarkContext> => {
    const pxe = createPXEClient('http://localhost:8080');
    const accounts = await getInitialTestAccountsWallets(pxe);
    const deployer = accounts[0]!;
    const deployedBaseContract = await deployTokenWithMinter(deployer);
    const tokenContract = await TokenContract.at(deployedBaseContract.address, deployer);
    return { pxe, deployer, accounts, tokenContract };
  },

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods: (context): ContractFunctionInteraction[] => {
    const { tokenContract, deployer, accounts } = context as TokenBenchmarkContext;
    const alice = deployer;
    const bob = accounts[1];
    const owner = alice.getAddress();

    const methods: ContractFunctionInteraction[] = [
      // Mint methods
      tokenContract.withWallet(alice).methods.mint_to_private(owner, owner, amt(100)),
      tokenContract.withWallet(alice).methods.mint_to_public(owner, amt(100)),

      // Transfer methods
      tokenContract.withWallet(alice).methods.transfer_private_to_public(owner, bob.getAddress(), amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_private_to_public_with_commitment(owner, bob.getAddress(), amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_private_to_private(owner, bob.getAddress(), amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_public_to_private(owner, bob.getAddress(), amt(10), 0),
      tokenContract.withWallet(alice).methods.transfer_public_to_public(owner, bob.getAddress(), amt(10), 0),

      // Burn methods
      tokenContract.withWallet(alice).methods.burn_private(owner, amt(10), 0),
      tokenContract.withWallet(alice).methods.burn_public(owner, amt(10), 0),
    ];

    return methods.filter(Boolean);
  },
};
