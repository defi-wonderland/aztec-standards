import {
  Fr,
  type AccountWallet,
  type ContractFunctionInteraction,
  type PXE,
  getContractClassFromArtifact,
} from '@aztec/aztec.js';
import { deriveKeys } from '@aztec/stdlib/keys';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { type AztecLmdbStore } from '@aztec/kv-store/lmdb';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';
import type { NamedBenchmarkedInteraction } from '@defi-wonderland/aztec-benchmark/dist/types.js';

import { EscrowContract, EscrowContractArtifact } from '../artifacts/Escrow.js';
import { TestLogicContract } from '../artifacts/TestLogic.js';
import { deployLogic, deployEscrowWithPublicKeysAndSalt, grumpkinScalarToFr } from '../src/ts/test/utils.js';
import { setupPXE } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface LogicBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  store: AztecLmdbStore;
  deployer: AccountWallet;
  accounts: AccountWallet[];
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
    const { pxe, store } = await setupPXE('bench-logic');
    const managers = await getInitialTestAccountsManagers(pxe);
    const accounts = await Promise.all(managers.map((acc) => acc.register()));
    const [deployer] = accounts;

    const logicSk = Fr.random();
    const escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

    // Deploy logic contract
    const logicContract = (await deployLogic(deployer, escrowClassId)) as TestLogicContract;
    const partialAddressLogic = await logicContract.partialAddress;
    await pxe.registerAccount(logicSk, partialAddressLogic);

    // Setup escrow
    const escrowSk = Fr.random();
    const escrowKeys = await deriveKeys(escrowSk);
    const secretKeys = {
      nsk_m: grumpkinScalarToFr(escrowKeys.masterNullifierSecretKey),
      ivsk_m: grumpkinScalarToFr(escrowKeys.masterIncomingViewingSecretKey),
      ovsk_m: grumpkinScalarToFr(escrowKeys.masterOutgoingViewingSecretKey),
      tsk_m: grumpkinScalarToFr(escrowKeys.masterTaggingSecretKey),
    };
    const escrowSalt = new Fr(logicContract.instance.address.toBigInt());
    const escrowContract = (await deployEscrowWithPublicKeysAndSalt(
      escrowKeys.publicKeys,
      deployer,
      escrowSalt,
    )) as EscrowContract;
    const partialAddressEscrow = await escrowContract.partialAddress;
    await pxe.registerAccount(escrowSk, partialAddressEscrow);

    return {
      pxe,
      store,
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
  getMethods(context: LogicBenchmarkContext): Array<NamedBenchmarkedInteraction | ContractFunctionInteraction> {
    const { accounts, escrowContract, deployer, logicContract, secretKeys } = context;
    const recipient = accounts[2].getAddress();

    const methods: Array<NamedBenchmarkedInteraction | ContractFunctionInteraction> = [
      // Derive public keys from secret keys
      {
        name: 'secret_keys_to_public_keys',
        interaction: logicContract.withWallet(deployer).methods.secret_keys_to_public_keys(secretKeys),
      },

      // Check escrow correctness
      {
        name: 'check_escrow',
        interaction: logicContract.withWallet(deployer).methods.check_escrow(escrowContract.address, secretKeys),
      },

      // Share escrow
      {
        name: 'share_escrow',
        interaction: logicContract
          .withWallet(deployer)
          .methods.share_escrow(recipient, escrowContract.address, secretKeys),
      },
    ];

    return methods.filter(Boolean);
  }

  async teardown(context: LogicBenchmarkContext): Promise<void> {
    await context.store.delete();
  }
}
