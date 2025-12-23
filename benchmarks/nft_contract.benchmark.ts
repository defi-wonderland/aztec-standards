import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { NFTContract } from '../artifacts/NFT.js';
import { deployNFTWithMinter, setupTestSuite } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface NFTBenchmarkContext extends BenchmarkContext {
  store: AztecLMDBStoreV2;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  nftContract: NFTContract;
}

// Use export default class extending Benchmark
export default class NFTContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the NFTContract.
   * Creates wallet, gets accounts, and deploys the contract.
   */
  async setup(): Promise<NFTBenchmarkContext> {
    const { store, wallet, accounts } = await setupTestSuite('bench-nft', true);
    const [deployer] = accounts;
    const deployedBaseContract = await deployNFTWithMinter(wallet, deployer, {
      universalDeploy: true,
      from: deployer,
    });
    const nftContract = NFTContract.at(deployedBaseContract.address, wallet);
    return { store, wallet, deployer, accounts, nftContract };
  }

  /**
   * Returns the list of NFTContract methods to be benchmarked.
   */
  getMethods(context: NFTBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { nftContract, accounts, wallet } = context;
    const [alice] = accounts;
    const owner = alice;
    const methods: ContractFunctionInteractionCallIntent[] = [
      // Mint methods
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.mint_to_private(owner, 1),
      },
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.mint_to_public(owner, 2),
      },

      // Transfer methods
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.transfer_private_to_public(owner, owner, 1, 0),
      },
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.transfer_public_to_private(owner, owner, 1, 0),
      },
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.transfer_private_to_private(owner, owner, 1, 0),
      },
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.transfer_public_to_public(owner, owner, 2, 0),
      },

      // NOTE: don't have enough private NFT's to burn_private
      // nftContract.withWallet(alice).methods.transfer_private_to_public_with_commitment(owner, owner, 1, 0),

      // Burn methods
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.burn_private(owner, 1, 0),
      },
      {
        caller: alice,
        action: nftContract.withWallet(wallet).methods.burn_public(owner, 2, 0),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: NFTBenchmarkContext): Promise<void> {
    await context.store.delete();
  }
}
