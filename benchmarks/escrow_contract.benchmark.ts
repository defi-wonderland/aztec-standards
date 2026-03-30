// Import Aztec dependencies
import { Fr } from '@aztec/aztec.js/fields';
import { deriveKeys } from '@aztec/stdlib/keys';
import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';
import type { NamedBenchmarkedInteraction } from '@defi-wonderland/aztec-benchmark/dist/types.js';

// Import artifacts
import { TokenContract } from '../src/artifacts/Token.js';
import { EscrowContract, EscrowContractArtifact } from '../src/artifacts/Escrow.js';
import { NFTContract } from '../src/artifacts/NFT.js';

// Import test utilities
import { setupTestSuite, deployEscrow, deployTokenWithMinter, deployNFTWithMinter } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface EscrowBenchmarkContext extends BenchmarkContext {
  cleanup: () => Promise<void>;
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
    const { cleanup, wallet, accounts } = await setupTestSuite(true);
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
      .send({ from: deployer });
    const tokenId = 1;
    await nftContract
      .withWallet(wallet)
      .methods.mint_to_private(escrowContract.address, tokenId)
      .send({ from: deployer });

    return {
      cleanup,
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

    // The escrow contract holds private notes. The profiler needs the escrow
    // address in scope so the PXE can find its private token/NFT notes.
    const escrowScopes = [escrowContract.address];

    const methods: Array<NamedBenchmarkedInteraction | ContractFunctionInteractionCallIntent> = [
      // Partial token withdrawal (with change)
      {
        interaction: {
          caller: logicMock,
          action: escrowContract.withWallet(wallet).methods.withdraw(tokenContract.address, halfAmount, recipient),
        },
        name: '(partial) withdraw',
        additionalScopes: escrowScopes,
      },
      // Full token withdrawal
      {
        interaction: {
          caller: logicMock,
          action: escrowContract.withWallet(wallet).methods.withdraw(tokenContract.address, halfAmount, recipient),
        },
        name: 'withdraw',
        additionalScopes: escrowScopes,
      },
      // NFT withdrawal
      {
        interaction: {
          caller: logicMock,
          action: escrowContract.withWallet(wallet).methods.withdraw_nft(nftContract.address, tokenId, recipient),
        },
        name: 'withdraw_nft',
        additionalScopes: escrowScopes,
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: EscrowBenchmarkContext): Promise<void> {
    await context.cleanup();
  }
}
