import { type AccountWallet, type ContractFunctionInteraction, type PXE } from '@aztec/aztec.js';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { type AztecLmdbStore } from '@aztec/kv-store/lmdb';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';
import type { NamedBenchmarkedInteraction } from '@defi-wonderland/aztec-benchmark/dist/types.js';

import { NFTContract } from '../artifacts/NFT.js';
import { deployNFTWithMinter, setupPXE } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface NFTBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  store: AztecLmdbStore;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  nftContract: NFTContract;
}

// Use export default class extending Benchmark
export default class NFTContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the NFTContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<NFTBenchmarkContext> {
    const { pxe, store } = await setupPXE();
    const managers = await getInitialTestAccountsManagers(pxe);
    const accounts = await Promise.all(managers.map((acc) => acc.register()));
    const [deployer] = accounts;
    const deployedBaseContract = await deployNFTWithMinter(deployer, {
      universalDeploy: true,
      from: deployer.getAddress(),
    });
    const nftContract = await NFTContract.at(deployedBaseContract.address, deployer);
    return { pxe, store, deployer, accounts, nftContract };
  }

  /**
   * Returns the list of NFTContract methods to be benchmarked.
   */
  getMethods(context: NFTBenchmarkContext): Array<NamedBenchmarkedInteraction | ContractFunctionInteraction> {
    const { nftContract, accounts } = context;
    const [alice] = accounts;
    const owner = alice.getAddress();
    const methods: Array<NamedBenchmarkedInteraction | ContractFunctionInteraction> = [
      // Mint methods
      {
        name: 'mint_to_private',
        interaction: nftContract.withWallet(alice).methods.mint_to_private(owner, 1),
      },
      {
        name: 'mint_to_public',
        interaction: nftContract.withWallet(alice).methods.mint_to_public(owner, 2),
      },

      // Transfer methods
      {
        name: 'transfer_private_to_public',
        interaction: nftContract.withWallet(alice).methods.transfer_private_to_public(owner, owner, 1, 0),
      },
      {
        name: 'transfer_public_to_private',
        interaction: nftContract.withWallet(alice).methods.transfer_public_to_private(owner, owner, 1, 0),
      },
      {
        name: 'transfer_private_to_private',
        interaction: nftContract.withWallet(alice).methods.transfer_private_to_private(owner, owner, 1, 0),
      },
      {
        name: 'transfer_public_to_public',
        interaction: nftContract.withWallet(alice).methods.transfer_public_to_public(owner, owner, 2, 0),
      },

      // NOTE: don't have enough private NFT's to burn_private
      // nftContract.withWallet(alice).methods.transfer_private_to_public_with_commitment(owner, owner, 1, 0),

      // Burn methods
      {
        name: 'burn_private',
        interaction: nftContract.withWallet(alice).methods.burn_private(owner, 1, 0),
      },
      {
        name: 'burn_public',
        interaction: nftContract.withWallet(alice).methods.burn_public(owner, 2, 0),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: NFTBenchmarkContext): Promise<void> {
    await context.store.delete();
  }
}
