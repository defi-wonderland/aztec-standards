import {
  type AccountWallet,
  type ContractFunctionInteraction,
  type PXE,
  createPXEClient,
} from '@aztec/aztec.js';
import { getInitialTestAccountsWallets } from '@aztec/accounts/testing';
import { parseUnits } from 'viem';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from 'aztec-benchmark';

import { MulDivContract } from '../src/artifacts/MulDiv.js';
import { deployDivMul } from '../src/ts/test/utils_mul_div.js';

// Extend the BenchmarkContext from the new package
interface MulDivBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  mulDivContract: MulDivContract;
}

// --- Helper Functions ---

function amt(x: bigint | number | string) {
  // Using 18 decimals as standard for Token examples
  return parseUnits(x.toString(), 18);
}

// Use export default class extending Benchmark
export default class MulDivContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the MulDivContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<MulDivBenchmarkContext> {
    const pxe = createPXEClient('http://localhost:8080');
    const accounts = await getInitialTestAccountsWallets(pxe);
    const deployer = accounts[0]!;
    const deployedBaseContract = await deployDivMul(deployer);
    const mulDivContract = await MulDivContract.at(deployedBaseContract.address, deployer);
    return { pxe, deployer, accounts, mulDivContract };
  }

  /**
   * Returns the list of MulDivContract methods to be benchmarked.
   */
  getMethods(context: MulDivBenchmarkContext): ContractFunctionInteraction[] {
    const { mulDivContract, deployer, accounts } = context;
    const alice = deployer;
    const x = amt(10);
    const y = amt(5);
    const z = amt(12);

    const methods: ContractFunctionInteraction[] = [
      mulDivContract.withWallet(alice).methods.mul_div_in_private(x, y, z),
      mulDivContract.withWallet(alice).methods.mul_div_in_public(x, y, z),
    ];

    return methods.filter(Boolean);
  }
}
