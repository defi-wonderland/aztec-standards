import {
  type ContractFunctionInteraction,
  type GasLimits,
  type Gas,
} from '@aztec/aztec.js';
import { Command } from 'commander';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// --- Types (Moved from common.benchmark.ts) ---

/** Benchmark specific setup/teardown context */
// eslint-disable-next-line @typescript-eslint/no-empty-interface
export interface BenchmarkRunContext {
  // Can be extended by specific benchmark files e.g.,
  // interface TokenBenchmarkContext extends BenchmarkRunContext { tokenContract: TokenContract; }
}

/** Structure of the config object exported by each *.benchmark.ts file */
export interface BenchmarkConfig {
  /** Optional setup function run before benchmarks */
  setup?: () => Promise<BenchmarkRunContext>;
  /** Function returning the methods to benchmark */
  getMethods: (context: BenchmarkRunContext) => ContractFunctionInteraction[];
  /** Optional teardown function run after benchmarks */
  teardown?: (context: BenchmarkRunContext) => Promise<void>;
}

/** Gate counts for a specific circuit */
interface GateCount {
  circuitName: string;
  gateCount: number;
}

/** Result of profiling a single function */
export interface ProfileResult {
  name: string;
  totalGateCount: number;
  gateCounts: GateCount[];
  gas: {
    gasLimits: GasLimits;
    teardownGasLimits: GasLimits;
  };
}

/** Structure of the output JSON report */
export interface ProfileReport {
  /** Total gate counts keyed by function name */
  summary: Record<string, number>;
  /** Detailed results for each function */
  results: ProfileResult[];
  /** Gas summary (total L2 + DA) keyed by function name */
  gasSummary: Record<string, number>;
}

// --- Profiler Class (Adapted from old run.benchmark.ts) ---

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
      // Assuming f is already configured with a wallet via getMethods
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
    const name = call?.name ?? `unknown_function_${call?.selector.toString() ?? 'no_selector'}`;

    console.log(`Profiling ${name}...`);

    try {
      // Estimate gas first
      const gas = await f.estimateGas();
      // Profile execution
      const profileResults = await f.profile({ profileMode: 'full' });
      // Ensure the transaction is mined
      await f.send().wait();

      const result: ProfileResult = {
        name,
        totalGateCount: sumArray(
          profileResults.executionSteps
            .map(step => step.gateCount)
            .filter((count): count is number => count !== undefined),
        ),
        gateCounts: profileResults.executionSteps.map(step => ({
          circuitName: step.functionName,
          gateCount: step.gateCount || 0, // Assume 0 if undefined (public function)
        })),
        gas,
      };
      console.log(` -> ${name}: ${result.totalGateCount} gates`);
      return result;
    } catch (error: any) {
      console.error(`Error profiling ${name}:`, error.message);
      return {
        name: `${name} (FAILED)`,
        totalGateCount: 0,
        gateCounts: [],
        gas: { gasLimits: {} as Gas, teardownGasLimits: {} as Gas },
      };
    }
  }
}

// --- Runner Logic ---

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// Assume script is in scripts/ and benchmarks are in benchmarks/ relative to project root
const projectRoot = path.resolve(__dirname, '../');
const benchmarksDir = path.join(projectRoot, 'benchmarks');

async function runBenchmark(prefix: string) {
  console.log(`Running benchmark for prefix: ${prefix}`);

  const benchmarkDefinitionFile = `${prefix}.benchmark.ts`;
  const benchmarkFilePath = path.join(benchmarksDir, benchmarkDefinitionFile);
  const outputJsonPath = path.join(benchmarksDir, `${prefix}.benchmark.json`);

  if (!fs.existsSync(benchmarkFilePath)) {
    console.error(`Error: Benchmark definition file not found at ${benchmarkFilePath}`);
    process.exit(1);
  }

  console.log(`Loading benchmark config from: ${benchmarkFilePath}`);
  console.log(`Output will be saved to: ${outputJsonPath}`);

  const profiler = new Profiler();

  try {
    // Dynamically import the benchmark config using file URL
    const fileUrl = `file://${benchmarkFilePath.replace(/\\/g, '/')}`;
    const module = await import(fileUrl);
    const config: BenchmarkConfig = module.benchmarkConfig;

    if (!config || typeof config.getMethods !== 'function') {
      console.error(`Error: ${benchmarkFilePath} does not export a valid benchmarkConfig object with a getMethods function.`);
      process.exit(1);
    }

    let runContext: BenchmarkRunContext = {}; // Initialize empty context

    if (typeof config.setup === 'function') {
      console.log(`Running setup for ${prefix}...`);
      runContext = await config.setup();
      console.log(`Setup complete for ${prefix}.`);
    }

    console.log(`Getting methods to benchmark for ${prefix}...`);
    const methodsToBenchmark = config.getMethods(runContext);

    if (!Array.isArray(methodsToBenchmark) || methodsToBenchmark.length === 0) {
      console.warn(`No benchmark methods returned by getMethods for ${prefix}. Saving empty report.`);
      await profiler.saveResults([], outputJsonPath);
    } else {
      console.log(`Profiling ${methodsToBenchmark.length} methods for ${prefix}...`);
      const results = await profiler.profile(methodsToBenchmark);
      await profiler.saveResults(results, outputJsonPath);
    }

    if (typeof config.teardown === 'function') {
      console.log(`Running teardown for ${prefix}...`);
      await config.teardown(runContext);
      console.log(`Teardown complete for ${prefix}.`);
    }

    console.log(`--- Benchmark finished for ${prefix} ---`);
  } catch (error) {
    console.error(`Failed to run benchmark for ${prefix} from ${benchmarkFilePath}:`, error);
    // Attempt to save an error report
    const errorReport: ProfileReport = {
      summary: { error: 1 }, // Indicate error in summary
      results: [{ name: 'BENCHMARK_RUNNER_ERROR', totalGateCount: 0, gateCounts: [], gas: {} as any }],
      gasSummary: { error: 1 },
    };
    try {
      fs.writeFileSync(outputJsonPath, JSON.stringify(errorReport, null, 2));
      console.error(`Saved error report to ${outputJsonPath}`);
    } catch (writeError) {
      console.error(`Failed to write error report to ${outputJsonPath}:`, writeError);
    }
    process.exit(1); // Exit with error code
  }
}

// --- Main Execution ---

const program = new Command();
program
  .name('benchmark')
  .description('Runs a specific benchmark and saves the JSON report.')
  .argument('<prefix>', 'Prefix of the benchmark file to run (e.g., token_contract)')
  .action(runBenchmark)
  .parse(process.argv);

// Handle case where no arguments are provided
if (!process.argv.slice(2).length) {
  program.outputHelp();
} 