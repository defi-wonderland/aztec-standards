// Import Aztec dependencies
import { Fr } from '@aztec/aztec.js/fields';
import { deriveKeys } from '@aztec/stdlib/keys';
import type { Wallet } from '@aztec/aztec.js/wallet';
import { type AztecNode } from '@aztec/aztec.js/node';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import type { AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';
import type { NamedBenchmarkedInteraction } from '@defi-wonderland/aztec-benchmark/dist/types.js';

// Import artifacts
import { TokenContract } from '../artifacts/Token.js';
import { EscrowContract, EscrowContractArtifact } from '../artifacts/Escrow.js';
import { NFTContract } from '../artifacts/NFT.js';

// Import test utilities
import { setupTestSuite, deployEscrow, deployTokenWithMinter, deployNFTWithMinter } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface EscrowBenchmarkContext extends BenchmarkContext {
  store: AztecLMDBStoreV2;
  node: AztecNode;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  tokenContract: TokenContract;
  nftContract: NFTContract;
  escrowContract: EscrowContract;
  tokenAmount: number;
  tokenId: number;
}

// Use export default class extending Benchmark
export default class EscrowContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates wallet, gets accounts, and deploys the contract.
   */
  async setup(): Promise<EscrowBenchmarkContext> {
    const { store, node, wallet, accounts } = await setupTestSuite('bench-escrow');
    const [deployer, logicMock] = accounts;

    // Setup escrow
    const escrowSk = Fr.random();
    const escrowKeys = await deriveKeys(escrowSk);
    const escrowSalt = new Fr(logicMock.toBigInt());
    const { contract: escrowContract, instance: escrowInstance } = await deployEscrow(
      escrowKeys.publicKeys,
      wallet,
      deployer,
      escrowSalt,
    );

    if (escrowInstance) {
      await wallet.registerContract(escrowInstance, EscrowContractArtifact, escrowSk);
    }

    // Deploy token and NFT contracts
    const deployedTokenContract = await deployTokenWithMinter(wallet, deployer);
    const tokenContract = TokenContract.at(deployedTokenContract.address, wallet);
    const deployedNFTContract = await deployNFTWithMinter(wallet, deployer);
    const nftContract = NFTContract.at(deployedNFTContract.address, wallet);

    // Mint tokens and NFT to the escrow contract
    const tokenAmount = 100;
    await tokenContract
      .withWallet(wallet)
      .methods.mint_to_private(escrowContract.address, tokenAmount)
      .send({ from: deployer })
      .wait();
    const tokenId = 1;
    await nftContract
      .withWallet(wallet)
      .methods.mint_to_private(escrowContract.address, tokenId)
      .send({ from: deployer })
      .wait();

    return {
      store,
      node,
      wallet,
      deployer,
      accounts,
      tokenContract,
      nftContract,
      escrowContract,
      tokenAmount,
      tokenId,
    };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(
    context: EscrowBenchmarkContext,
  ): Array<NamedBenchmarkedInteraction | ContractFunctionInteractionCallIntent> {
    const { accounts, tokenContract, nftContract, escrowContract, tokenId, wallet } = context;
    const logicMock = accounts[1];
    const recipient = accounts[2];
    const halfAmount = 50;

    const methods: Array<NamedBenchmarkedInteraction | ContractFunctionInteractionCallIntent> = [
      // Partial token withdrawal (with change)
      {
        interaction: {
          caller: logicMock,
          action: escrowContract.withWallet(wallet).methods.withdraw(tokenContract.address, halfAmount, recipient),
        },
        name: '(partial) withdraw',
      },
      // Full token withdrawal
      {
        caller: logicMock,
        action: escrowContract.withWallet(wallet).methods.withdraw(tokenContract.address, halfAmount, recipient),
      },
      // NFT withdrawal
      {
        caller: logicMock,
        action: escrowContract.withWallet(wallet).methods.withdraw_nft(nftContract.address, tokenId, recipient),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: EscrowBenchmarkContext): Promise<void> {
    await context.store.delete();
  }
}
