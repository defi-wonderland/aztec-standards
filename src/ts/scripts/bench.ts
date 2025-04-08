import { getInitialTestAccountsWallets } from '@aztec/accounts/testing';
import { AztecAddress, createPXEClient, type ContractFunctionInteraction } from '@aztec/aztec.js';
import { GasDimensions } from '@aztec/stdlib/gas';
import fs from 'node:fs';
import { parseUnits } from 'viem';
import { TokenContract } from '../../artifacts/Token.js';
import { deployTokenWithMinter } from '../test/utils.js';

let owner: AztecAddress;

async function main(outputFilename: string) {
  const pxe = createPXEClient('http://localhost:8080');

  const accounts = await getInitialTestAccountsWallets(pxe);
  const alice = accounts[0]!;
  owner = alice.getAddress();
  const bob = accounts[1]!;
  const token = (await deployTokenWithMinter(alice)) as TokenContract;

  const profiler = new Profiler(outputFilename);
  await profiler.profile([
    token.withWallet(alice).methods.mint_to_private(alice.getAddress(), alice.getAddress(), amt(100)),
    token.withWallet(alice).methods.mint_to_public(alice.getAddress(), amt(100)),
    token.withWallet(alice).methods.mint_to_commitment(amt(100), { commitment: 0 }),
  ]);

  await profiler.profile([
    token.withWallet(alice).methods.transfer_private_to_public(alice.getAddress(), bob.getAddress(), amt(10), 0),
    // this returns a commitment
    token
      .withWallet(alice)
      .methods.transfer_private_to_public_with_commitment(alice.getAddress(), bob.getAddress(), amt(10), 0),
    token.withWallet(alice).methods.transfer_private_to_private(alice.getAddress(), bob.getAddress(), amt(10), 0),
    // requires a initialized commitment
    // token.withWallet(alice).methods.transfer_private_to_commitment(alice.getAddress(), amt(10), {commitment: 0}, 0),
    token.methods.transfer_public_to_private(alice.getAddress(), bob.getAddress(), amt(10), 0),
    token.methods.transfer_public_to_public(alice.getAddress(), bob.getAddress(), amt(10), 0),
    // token.methods.transfer_public_to_commitment(alice.getAddress(), amt(10), {commitment: 0}, 0),
  ]);

  await profiler.profile([
    token.withWallet(alice).methods.initialize_transfer_commitment(bob.getAddress(), alice.getAddress()),
  ]);

  await profiler.profile([
    token.methods.burn_private(alice.getAddress(), amt(10), 0),
    token.methods.burn_public(alice.getAddress(), amt(10), 0),
  ]);

  await profiler.saveResults();
}

function amt(x: bigint | number | string) {
  return parseUnits(x.toString(), 18);
}

function castArray<T>(value: T | T[]): T[] {
  return Array.isArray(value) ? value : [value];
}

function sumArray(arr: number[]): number {
  return arr.reduce((a, b) => a + b, 0);
}

class Profiler {
  #results: ProfileResult[] = [];
  constructor(readonly filename: string) {}

  async profile(fs: ContractFunctionInteraction | ContractFunctionInteraction[]) {
    let results: ProfileResult[] = [];
    for (const f of castArray(fs)) {
      results.push(await this.#profileOne(f));
    }
    return results;
  }

  async saveResults() {
    const summary = this.#results.reduce(
      (acc, result) => ({
        ...acc,
        [result.name]: result.totalGateCount,
      }),
      {} as Record<string, number>,
    );
    function sumGas(gas: Gas) {
      return GasDimensions.reduce((acc, dim) => acc + gas[`${dim}Gas`], 0);
    }
    const gasSummary = this.#results.reduce(
      (acc, result) => ({
        ...acc,
        [result.name]: sumGas(result.gas.gasLimits) + sumGas(result.gas.teardownGasLimits),
      }),
      {} as Record<string, number>,
    );
    const report: ProfileReport = {
      summary,
      results: this.#results,
      gasSummary,
    };
    console.log('saving results in', this.filename);
    fs.writeFileSync(this.filename, JSON.stringify(report, null, 2));
  }

  async #profileOne(f: ContractFunctionInteraction) {
    const name = (await f.request()).calls[0]?.name;
    console.log(`profiling ${name}...`);
    const profilingResults = await f.profile({ profileMode: 'full' });
    const profileResults = profilingResults;
    const gas = await f.estimateGas();
    await f.send().wait();
    const result: ProfileResult = {
      name,
      totalGateCount: sumArray(
        profileResults.executionSteps
          .map((step) => step.gateCount)
          .filter((count): count is number => count !== undefined),
      ),
      gateCounts: profileResults.executionSteps.map((step) => ({
        circuitName: step.functionName,
        // if gateCount is undefined, it means the function is public
        gateCount: step.gateCount || 0,
      })),
      gas,
    };
    console.log(result);
    if (this.#results.find((r) => r.name === result.name)) {
      throw new Error(`already profiled "${result.name}"`);
    }
    this.#results.push(result);
    console.log(`profiled ${result.name}`);
    return result;
  }
}

export type ProfileReport = {
  readonly summary: Record<string, number>;
  readonly results: readonly ProfileResult[];
  readonly gasSummary: Record<string, number>;
};

type ProfileResult = {
  readonly name: string;
  readonly totalGateCount: number;
  readonly gateCounts: readonly {
    readonly circuitName: string;
    readonly gateCount: number;
  }[];
  readonly gas: Record<'gasLimits' | 'teardownGasLimits', Gas>;
};

type Gas = Record<`${GasDimensions}Gas`, number>;

// TODO: we should use commander or something to handle these scripts
const outputFilename = process.argv[2] || 'bench.json';
console.log(`outputting to ${outputFilename}`);
main(outputFilename);
