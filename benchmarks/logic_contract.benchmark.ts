// Import Aztec dependencies
import { Fr } from '@aztec/aztec.js/fields';
import { deriveKeys } from '@aztec/stdlib/keys';
import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { getContractClassFromArtifact } from '@aztec/aztec.js/contracts';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

// Import artifacts
import { EscrowContract, EscrowContractArtifact } from '../src/artifacts/Escrow.js';
import { TestLogicContract } from '../src/artifacts/TestLogic.js';

// Import test utilities
import { setupTestSuite, deployLogic, deployEscrowWithPublicKeysAndSalt } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface LogicBenchmarkContext extends BenchmarkContext {
  cleanup: () => Promise<void>;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  logicContract: TestLogicContract;
  escrowContract: EscrowContract;
  escrowSk: Fr;
}

// Use export default class extending Benchmark
export default class LogicContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates wallet, gets accounts, and deploys the contract.
   */
  async setup(): Promise<LogicBenchmarkContext> {
    const { cleanup, wallet, accounts } = await setupTestSuite(true);
    const [deployer] = accounts;

    const escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

    // Deploy logic contract
    const logicContract = (await deployLogic(wallet, deployer, escrowClassId)) as TestLogicContract;

    // Setup escrow
    const escrowSk = Fr.random();
    const escrowKeys = await deriveKeys(escrowSk);
    const escrowSalt = new Fr(logicContract.address.toBigInt());
    const escrowContract = (await deployEscrowWithPublicKeysAndSalt(
      escrowKeys.publicKeys,
      wallet,
      deployer,
      escrowSalt,
    )) as EscrowContract;

    return {
      cleanup,
      wallet,
      deployer,
      accounts,
      logicContract,
      escrowContract,
      escrowSk,
    };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: LogicBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { accounts, escrowContract, deployer, logicContract, escrowSk, wallet } = context;
    const recipient = accounts[2];

    const methods: ContractFunctionInteractionCallIntent[] = [
      // Derive public keys from secret key
      {
        caller: deployer,
        action: logicContract.withWallet(wallet).methods.secret_key_to_public_keys(escrowSk),
      },
      // Check escrow correctness
      {
        caller: deployer,
        action: logicContract.withWallet(wallet).methods.get_escrow(escrowSk),
      },
      // Share escrow
      {
        caller: deployer,
        action: logicContract.withWallet(wallet).methods.share_escrow(recipient, escrowContract.address, escrowSk),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: LogicBenchmarkContext): Promise<void> {
    await context.cleanup();
  }
}
