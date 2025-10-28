import { Fr, type AccountWallet, type ContractFunctionInteraction, type PXE } from '@aztec/aztec.js';
import { deriveKeys } from '@aztec/stdlib/keys';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { type AztecLmdbStore } from '@aztec/kv-store/lmdb';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';
import type { NamedBenchmarkedInteraction } from '@defi-wonderland/aztec-benchmark/dist/types.js';

import { TokenContract } from '../artifacts/Token.js';
import { EscrowContract } from '../artifacts/Escrow.js';
import { NFTContract } from '../artifacts/NFT.js';
import { deployEscrow, deployTokenWithMinter, deployNFTWithMinter, setupPXE } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface ClawbackEscrowBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  store: AztecLmdbStore;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  tokenContract: TokenContract;
  nftContract: NFTContract;
  escrowContract: EscrowContract;
  tokenAmount: number;
  tokenId: number;
}

// Use export default class extending Benchmark
export default class ClawbackEscrowBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<ClawbackEscrowBenchmarkContext> {
    const { pxe, store } = await setupPXE('bench-escrow');
    const managers = await getInitialTestAccountsManagers(pxe);
    const accounts = await Promise.all(managers.map((acc) => acc.register()));
    const [deployer] = accounts;
    const logicMock = accounts[1];

    // Setup escrow
    const escrowSk = Fr.random();
    const escrowKeys = await deriveKeys(escrowSk);
    const escrowSalt = new Fr(logicMock.getAddress().toBigInt());
    const escrowContract = (await deployEscrow(escrowKeys.publicKeys, deployer, escrowSalt)) as EscrowContract;
    const partialAddressEscrow = await escrowContract.partialAddress;
    await pxe.registerAccount(escrowSk, partialAddressEscrow);

    // Deploy token and NFT contracts
    const deployedTokenContract = await deployTokenWithMinter(deployer);
    const tokenContract = await TokenContract.at(deployedTokenContract.address, deployer);
    const deployedNFTContract = await deployNFTWithMinter(deployer);
    const nftContract = await NFTContract.at(deployedNFTContract.address, deployer);

    // Mint tokens and NFT to the escrow contract
    const tokenAmount = 100;
    await tokenContract
      .withWallet(deployer)
      .methods.mint_to_private(escrowContract.address, tokenAmount)
      .send({ from: deployer.getAddress() })
      .wait();
    const tokenId = 1;
    await nftContract
      .withWallet(deployer)
      .methods.mint_to_private(escrowContract.address, tokenId)
      .send({ from: deployer.getAddress() })
      .wait();

    return { pxe, store, deployer, accounts, tokenContract, nftContract, escrowContract, tokenAmount, tokenId };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(
    context: ClawbackEscrowBenchmarkContext,
  ): Array<NamedBenchmarkedInteraction | ContractFunctionInteraction> {
    const { accounts, tokenContract, nftContract, escrowContract, tokenAmount, tokenId } = context;
    const logicMock = accounts[1];
    const recipient = accounts[2].getAddress();
    const halfAmount = tokenAmount / 2;

    const methods: Array<NamedBenchmarkedInteraction | ContractFunctionInteraction> = [
      // Token withdrawal
      {
        name: 'withdraw (partial)',
        interaction: escrowContract
          .withWallet(logicMock)
          .methods.withdraw(tokenContract.address, halfAmount, recipient),
      },
      {
        name: 'withdraw (full)',
        interaction: escrowContract
          .withWallet(logicMock)
          .methods.withdraw(tokenContract.address, halfAmount, recipient),
      },

      // NFT withdrawal
      {
        name: 'withdraw NFT',
        interaction: escrowContract.withWallet(logicMock).methods.withdraw_nft(nftContract.address, tokenId, recipient),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: ClawbackEscrowBenchmarkContext): Promise<void> {
    await context.store.delete();
  }
}
