// Import Aztec dependencies
import { Fr } from '@aztec/aztec.js/fields';
import { deriveKeys } from '@aztec/stdlib/keys';
import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';
import {
  ContractFunctionInteraction,
  type SimulateInteractionOptions,
  type ProfileInteractionOptions,
  type SendInteractionOptions,
} from '@aztec/aztec.js/contracts';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';
import type { NamedBenchmarkedInteraction } from '@defi-wonderland/aztec-benchmark/dist/types.js';

// Import artifacts
import { TokenContract } from '../src/artifacts/Token.js';
import { EscrowContract, EscrowContractArtifact } from '../src/artifacts/Escrow.js';
import { NFTContract } from '../src/artifacts/NFT.js';

// Import test utilities
import { setupTestSuite, deployEscrow, deployTokenWithMinter, deployNFTWithMinter } from '../src/ts/test/utils.js';

/**
 * Wraps a ContractFunctionInteraction so that the profiler includes extra
 * addresses in the PXE note-lookup scopes. Without this, the PXE will only
 * look up notes belonging to the `from` address, which is the caller. The
 * escrow benchmark needs the escrow contract's own notes to be accessible
 * during simulation/profiling/sending.
 */
class ScopedInteraction {
  constructor(
    private readonly inner: ContractFunctionInteraction,
    private readonly additionalScopes: AztecAddress[],
  ) {}

  async request(...args: Parameters<ContractFunctionInteraction['request']>) {
    return this.inner.request(...args);
  }

  async simulate(options: SimulateInteractionOptions) {
    return this.inner.simulate({
      ...options,
      additionalScopes: [...(options.additionalScopes ?? []), ...this.additionalScopes],
    });
  }

  async profile(options: ProfileInteractionOptions) {
    return this.inner.profile({
      ...options,
      additionalScopes: [...(options.additionalScopes ?? []), ...this.additionalScopes],
    });
  }

  async send(options: SendInteractionOptions) {
    return this.inner.send({
      ...options,
      additionalScopes: [...(options.additionalScopes ?? []), ...this.additionalScopes],
    });
  }
}

/** Wraps an interaction with additional scopes, cast to ContractFunctionInteraction for the profiler. */
function withScopes(inner: ContractFunctionInteraction, additionalScopes: AztecAddress[]): ContractFunctionInteraction {
  return new ScopedInteraction(inner, additionalScopes) as unknown as ContractFunctionInteraction;
}

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

    // The escrow contract holds private notes. The profiler's simulate/profile/send calls
    // only include the caller (logicMock) in the PXE note-lookup scopes by default.
    // We wrap the interactions to inject the escrow address as an additional scope so the
    // PXE can find the escrow's private token/NFT notes.
    const escrowScopes = [escrowContract.address];

    const methods: Array<NamedBenchmarkedInteraction | ContractFunctionInteractionCallIntent> = [
      // Partial token withdrawal (with change)
      {
        interaction: {
          caller: logicMock,
          action: withScopes(
            escrowContract.withWallet(wallet).methods.withdraw(tokenContract.address, halfAmount, recipient),
            escrowScopes,
          ),
        },
        name: '(partial) withdraw',
      },
      // Full token withdrawal
      {
        caller: logicMock,
        action: withScopes(
          escrowContract.withWallet(wallet).methods.withdraw(tokenContract.address, halfAmount, recipient),
          escrowScopes,
        ),
      },
      // NFT withdrawal
      {
        caller: logicMock,
        action: withScopes(
          escrowContract.withWallet(wallet).methods.withdraw_nft(nftContract.address, tokenId, recipient),
          escrowScopes,
        ),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: EscrowBenchmarkContext): Promise<void> {
    await context.cleanup();
  }
}
