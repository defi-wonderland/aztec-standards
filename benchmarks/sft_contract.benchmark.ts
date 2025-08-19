import { type AccountWallet, type ContractFunctionInteraction, type PXE } from '@aztec/aztec.js';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { SFTContract } from '../artifacts/SFT.js';
import { deploySFTWithMinter, setupPXE } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface SFTBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  sftContract: SFTContract;
}

// Use export default class extending Benchmark
export default class SFTContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the SFTContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<SFTBenchmarkContext> {
    const { pxe } = await setupPXE();
    const managers = await getInitialTestAccountsManagers(pxe);
    const accounts = await Promise.all(managers.map((acc) => acc.register()));
    const [deployer] = accounts;
    const deployedBaseContract = await deploySFTWithMinter(deployer, { universalDeploy: true });
    const sftContract = await SFTContract.at(deployedBaseContract.address, deployer);
    return { pxe, deployer, accounts, sftContract };
  }

  /**
   * Returns the list of SFTContract methods to be benchmarked.
   */
  getMethods(context: SFTBenchmarkContext): ContractFunctionInteraction[] {
    const { sftContract, accounts } = context;
    const [alice] = accounts;
    const owner = alice.getAddress();
    const tokenId = 1n;

    const methods: ContractFunctionInteraction[] = [
      // Token type creation
      sftContract.withWallet(alice).methods.create_token_type(tokenId),

      // Mint methods
      sftContract.withWallet(alice).methods.mint_to_private(owner, tokenId),
      sftContract.withWallet(alice).methods.mint_to_public(owner, tokenId),

      // Transfer methods
      sftContract.withWallet(alice).methods.transfer_private_to_public(owner, owner, tokenId, 0),
      sftContract.withWallet(alice).methods.transfer_public_to_private(owner, owner, tokenId, 0),
      sftContract.withWallet(alice).methods.transfer_private_to_private(owner, owner, tokenId, 0),
      sftContract.withWallet(alice).methods.transfer_public_to_public(owner, owner, tokenId, 0),

      // NOTE: Commitment-based transfers are skipped due to state synchronization issues
      // sftContract.withWallet(alice).methods.transfer_private_to_public_with_commitment(owner, owner, tokenId, 0),

      // Burn methods
      sftContract.withWallet(alice).methods.burn_private(owner, tokenId, 0),
      sftContract.withWallet(alice).methods.burn_public(owner, tokenId, 0),
    ];

    return methods.filter(Boolean);
  }
}
