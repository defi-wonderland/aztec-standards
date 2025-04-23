import {
  type ContractFunctionInteraction,
} from '@aztec/aztec.js';

// Import shared types
import {
  type Gas,
  type ProfileResult,
  type ProfileReport,
  type BenchmarkRunContext,
  type BenchmarkConfig,
} from './common.benchmark.js';

import { Command } from 'commander';
import * as TOML from 'toml';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// --- Profiler Class (Adapted from original bench.ts) ---

function sumArray(arr: number[]): number {
  return arr.reduce((a, b) => a + b, 0);
}

function sumGas(gas: Gas): number {
  return (gas?.daGas ?? 0) + (gas?.l2Gas ?? 0);
}

class Profiler {
  async profile(fsToProfile: ContractFunctionInteraction[]): Promise<ProfileResult[]> {
    const results: ProfileResult[] = [];
    for (const f of fsToProfile) {
      // Assuming f (ContractFunctionInteraction) is already correctly configured with a wallet
      // by the time it's passed from the individual benchmark's getMethods function.
      results.push(await this.#profileOne(f));
    }
    return results;
  }

  async saveResults(results: ProfileResult[], filename: string) {
    if (!results.length) {
      console.log(`No results to save for ${filename}.`);
      // Write empty results structure
      fs.writeFileSync(filename, JSON.stringify({ summary: {}, results: [], gasSummary: {} } as ProfileReport, null, 2));
      return;
    }

    const summary = results.reduce(
      (acc, result) => ({
        ...acc,
        [result.name]: result.totalGateCount,
      }),
      {} as Record<string, number>,
    );

    const gasSummary = results.reduce(
      (acc, result) => ({
        ...acc,
        [result.name]: sumGas(result.gas.gasLimits) + sumGas(result.gas.teardownGasLimits),
      }),
      {} as Record<string, number>,
    );

    const report: ProfileReport = {
      summary,
      results: results,
      gasSummary,
    };

    console.log(`Saving results for ${results.length} methods in ${filename}`);
    fs.writeFileSync(filename, JSON.stringify(report, null, 2));
  }

  async #profileOne(f: ContractFunctionInteraction): Promise<ProfileResult> {
    const request = await f.request();
    const call = request.calls[0];

    // Extract the name from the method
    let name = call?.name; // Use let so we can modify it

    // Explicitly handle cases where the name might be missing
    if (!name) {
      const selector = call?.selector.toString() ?? 'no_selector';
      console.warn(`Warning: Function name is undefined for selector ${selector}. Using placeholder.`);
      // Use a placeholder that is clearly not a real name or selector
      name = `unknown_function_${selector}`;
    }

    console.log(`Profiling ${name}...`);

    let profileResults;
    let gas: Record<'gasLimits' | 'teardownGasLimits', Gas>;

    try {
      // Estimate gas first
      gas = await f.estimateGas();

      // Profile execution
      profileResults = await f.profile({ profileMode: 'full' });

      // Ensure the transaction is mined (even though we profiled, send+wait confirms state change)
      // Note: This might incur gas costs not fully captured by estimate/profile if state changes affect subsequent calls.
      await f.send().wait();

      const result: ProfileResult = {
        name, // Now guaranteed to be a string
        totalGateCount: sumArray(
          profileResults.executionSteps
            .map(step => step.gateCount)
            .filter((count): count is number => count !== undefined),
        ),
        gateCounts: profileResults.executionSteps.map(step => ({
          circuitName: step.functionName,
          // if gateCount is undefined, it means the function is public
          gateCount: step.gateCount || 0,
        })),
        gas,
      };
      console.log(` -> ${name}: ${result.totalGateCount} gates`);
      return result;
    } catch (error: any) {
        console.error(`Error profiling ${name}:`, error.message); // name is guaranteed string here
        // Return a partial result indicating failure
        return {
            name: `${name} (FAILED)`, // name is guaranteed string here
            totalGateCount: 0,
            gateCounts: [],
            gas: { gasLimits: {} as Gas, teardownGasLimits: {} as Gas }, // Provide default empty gas
        };
    }
  }
}

// --- Runner Logic ---

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '../'); // Adjust if script moves

async function findBenchmarkableContracts(): Promise<{ name: string; path: string }[]> {
  const rootNargoTomlPath = path.join(projectRoot, 'Nargo.toml');
  const benchmarkableContracts: { name: string; path: string }[] = [];

  try {
    const tomlContent = fs.readFileSync(rootNargoTomlPath, 'utf-8');
    const parsedToml = TOML.parse(tomlContent);

    if (parsedToml.workspace && Array.isArray(parsedToml.workspace.members)) {
      for (const memberPath of parsedToml.workspace.members) {
        const contractPath = path.join(projectRoot, memberPath);
        // Use a convention for the benchmark file name, e.g., contract_name.benchmark.ts
        // Assuming the dir name is the contract name for now
        const contractName = path.basename(contractPath);
        const benchmarkFilePath = path.join(contractPath, `${contractName}.benchmark.ts`);

        if (fs.existsSync(benchmarkFilePath)) {
          benchmarkableContracts.push({ name: contractName, path: contractPath });
          console.log(`Discovered benchmarkable contract: ${contractName} at ${memberPath}`);
        } else {
          console.warn(`Workspace member ${memberPath} does not have a ${contractName}.benchmark.ts file. Skipping.`);
        }
      }
    } else {
      console.warn(`Root Nargo.toml does not contain a [workspace].members array.`);
    }
  } catch (error) {
    console.error(`Error reading or parsing root Nargo.toml at ${rootNargoTomlPath}:`, error);
  }

  return benchmarkableContracts;
}

async function runBenchmarks() {
  const program = new Command();
  program
    .option('-c, --contracts <names>', 'Comma-separated list of contract names to benchmark (e.g., token_contract,other). Defaults to all discovered.', 'all')
    .parse(process.argv);

  const options = program.opts();
  const requestedContracts = options.contracts === 'all' ? null : options.contracts.split(',');

  console.log(`Starting benchmark run...`);

  const allContracts = await findBenchmarkableContracts();

  let contractsToRun = allContracts;

  if (requestedContracts) {
    contractsToRun = allContracts.filter(c => requestedContracts.includes(c.name));
    console.log(`Filtering run to contracts: ${contractsToRun.map(c => c.name).join(', ')}`);
  }

  if (!contractsToRun.length) {
    console.log("No contracts found or selected to benchmark.");
    return;
  }

  const profiler = new Profiler();

  for (const contractInfo of contractsToRun) {
    console.log(`\n--- Benchmarking Contract: ${contractInfo.name} ---`);
    const benchmarkFilePath = path.join(contractInfo.path, `${contractInfo.name}.benchmark.ts`);
    
    const outputJsonPath = path.join(
      contractInfo.path, 
      `${contractInfo.name}.benchmark_latest.json`
    );

    try {
      const fileUrl = `file://${benchmarkFilePath.replace(/\\/g, '/')}`;
      const module = await import(fileUrl);
      const config: BenchmarkConfig = module.benchmarkConfig;

      if (!config || typeof config.getMethods !== 'function') {
        console.error(`Error: ${benchmarkFilePath} does not export a valid benchmarkConfig object with a getMethods function.`);
        continue;
      }

      let runContext: BenchmarkRunContext = {}; // Initialize runContext as empty object by default

      if (typeof config.setup === 'function') {
        console.log(`Running setup for ${contractInfo.name}...`);
        runContext = await config.setup(); 
        console.log(`Setup complete for ${contractInfo.name}.`);
      }

      // Pass the context returned by setup (or the initial empty object) to getMethods
      const methodsToBenchmark = config.getMethods(runContext);
      if (!Array.isArray(methodsToBenchmark) || methodsToBenchmark.length === 0) {
          console.warn(`No benchmark methods returned by getMethods for ${contractInfo.name}. Skipping profiling.`);
          await profiler.saveResults([], outputJsonPath);
          continue;
      }

      console.log(`Profiling ${methodsToBenchmark.length} methods for ${contractInfo.name}...`);
      const results = await profiler.profile(methodsToBenchmark);

      await profiler.saveResults(results, outputJsonPath);

    } catch (error) {
      console.error(`Failed to benchmark contract ${contractInfo.name} from ${benchmarkFilePath}:`, error);
      const errorReport: ProfileReport = {
        summary: { error: 0 },
        results: [{ name: 'BENCHMARK_RUNNER_ERROR', totalGateCount: 0, gateCounts: [], gas: {} as any }],
        gasSummary: { error: 0 },
      };
      fs.writeFileSync(outputJsonPath, JSON.stringify(errorReport, null, 2));
    }
    console.log(`--- Finished Contract: ${contractInfo.name} ---`);
  }

  console.log("\nBenchmark run complete.");
}

runBenchmarks().catch(error => {
  console.error("Benchmark runner failed:", error);
  process.exit(1);
});