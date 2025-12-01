// Import Aztec dependencies
import { Fr } from '@aztec/aztec.js/fields';
import type { PXE } from '@aztec/pxe/server';
import { deriveKeys } from '@aztec/stdlib/keys';
import type { Wallet } from '@aztec/aztec.js/wallet';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { getContractClassFromArtifact } from '@aztec/aztec.js/contracts';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

// Import artifacts
import { EscrowContract, EscrowContractArtifact } from '../artifacts/Escrow.js';
import { TestLogicContract } from '../artifacts/TestLogic.js';

// Import test utilities
import {
  setupTestSuite,
  deployLogic,
  deployEscrowWithPublicKeysAndSalt,
  grumpkinScalarToFr,
} from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface LogicBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  wallet: Wallet;
  deployer: AztecAddress;
  accounts: AztecAddress[];
  logicContract: TestLogicContract;
  escrowContract: EscrowContract;
  secretKeys: {
    nsk_m: Fr;
    ivsk_m: Fr;
    ovsk_m: Fr;
    tsk_m: Fr;
  };
}

// Use export default class extending Benchmark
export default class LogicContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<LogicBenchmarkContext> {
    const { pxe, wallet, accounts } = await setupTestSuite('bench-logic');
    const [deployer] = accounts;

    const escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

    // Deploy logic contract
    const logicContract = (await deployLogic(wallet, deployer, escrowClassId)) as TestLogicContract;

    // Setup escrow
    const escrowSk = Fr.random();
    const escrowKeys = await deriveKeys(escrowSk);
    const secretKeys = {
      nsk_m: grumpkinScalarToFr(escrowKeys.masterNullifierSecretKey),
      ivsk_m: grumpkinScalarToFr(escrowKeys.masterIncomingViewingSecretKey),
      ovsk_m: grumpkinScalarToFr(escrowKeys.masterOutgoingViewingSecretKey),
      tsk_m: grumpkinScalarToFr(escrowKeys.masterTaggingSecretKey),
    };
    const escrowSalt = new Fr(logicContract.address.toBigInt());
    const escrowContract = (await deployEscrowWithPublicKeysAndSalt(
      escrowKeys.publicKeys,
      wallet,
      deployer,
      escrowSalt,
    )) as EscrowContract;

    return {
      pxe,
      wallet,
      deployer,
      accounts,
      logicContract,
      escrowContract,
      secretKeys,
    };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: LogicBenchmarkContext): ContractFunctionInteractionCallIntent[] {
    const { accounts, escrowContract, deployer, logicContract, secretKeys, wallet } = context;
    const recipient = accounts[2];

    const methods: ContractFunctionInteractionCallIntent[] = [
      // Derive public keys from secret keys
      {
        caller: deployer,
        action: logicContract.withWallet(wallet).methods.secret_keys_to_public_keys(secretKeys),
      },
      // Check escrow correctness
      {
        caller: deployer,
        action: logicContract.withWallet(wallet).methods.check_escrow(escrowContract.address, secretKeys),
      },
      // Share escrow
      {
        caller: deployer,
        action: logicContract.withWallet(wallet).methods.share_escrow(recipient, escrowContract.address, secretKeys),
      },
    ];

    return methods.filter(Boolean);
  }
}
