import { Command } from 'commander';
import * as TOML from 'toml';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  type ProfileReport,
  getDaGas,
  getL2Gas
} from './common.benchmark.js';

// Define interface for comparison results
interface MetricComparison {
  main: number;
  pr: number;
}

interface ComparisonResult {
  gates: MetricComparison;
  daGas: MetricComparison;
  l2Gas: MetricComparison;
}

// Simplified helper function for formatting diff
const formatDiff = (main: number, pr: number): string => {
  if (main === 0 && pr === 0) return '-';
  if (main === 0) return '+100%';
  if (pr === 0) return '-100%';

  const diff = pr - main;
  if (diff === 0) return '-';

  const pct = ((diff / main) * 100);
  const sign = diff > 0 ? '+' : '';

  if (Math.abs(pct) < 0.01) return '-';
  return `${sign}${diff} (${sign}${pct.toFixed(0)}%)`;
};

// --- Contract Discovery ---

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// Assume script is in scripts/, and project root is one level up
const projectRoot = path.resolve(__dirname, '../');

async function findBenchmarkableContracts(): Promise<{ name: string; path: string }[]> {
  const rootNargoTomlPath = path.join(projectRoot, 'Nargo.toml');
  const benchmarkableContracts: { name: string; path: string }[] = [];

  try {
    const tomlContent = fs.readFileSync(rootNargoTomlPath, 'utf-8');
    const parsedToml = TOML.parse(tomlContent);

    if (parsedToml.workspace && Array.isArray(parsedToml.workspace.members)) {
      for (const memberPath of parsedToml.workspace.members) {
        const contractPath = path.join(projectRoot, memberPath);
        // We just need the path and name to find the JSON files
        const contractName = path.basename(contractPath);
        // Check if the *directory* exists, not the benchmark.ts file specifically
        if (fs.existsSync(contractPath) && fs.lstatSync(contractPath).isDirectory()) {
          // Check if *any* benchmark JSON file exists as an indicator
          const baseJsonPath = path.join(contractPath, `${contractName}.benchmark.json`);
          const latestJsonPath = path.join(contractPath, `${contractName}.benchmark_latest.json`);
          if (fs.existsSync(baseJsonPath) || fs.existsSync(latestJsonPath)) {
            benchmarkableContracts.push({ name: contractName, path: contractPath });
            console.log(`Discovered benchmark candidate: ${contractName} at ${memberPath}`);
          } else {
            // console.log(`No benchmark JSON found for ${contractName} at ${memberPath}. Skipping.`);
          }
        } else {
          console.warn(`Workspace member path ${memberPath} not found or not a directory. Skipping.`);
        }
      }
    } else {
      console.warn(`Root Nargo.toml at ${rootNargoTomlPath} does not contain a [workspace].members array.`);
    }
  } catch (error: any) {
    if (error.code === 'ENOENT') {
      console.error(`Error: Root Nargo.toml not found at ${rootNargoTomlPath}. Cannot discover contracts.`);
    } else {
      console.error(`Error reading or parsing root Nargo.toml at ${rootNargoTomlPath}:`, error);
    }
  }

  return benchmarkableContracts;
}

// --- Comparison Logic (Adapted from compare-bench.ts) ---

const getStatusEmoji = (metrics: ComparisonResult, threshold: number): string => {
  const isRemoved = metrics.gates.pr === 0 && metrics.daGas.pr === 0 && metrics.l2Gas.pr === 0 && 
                  (metrics.gates.main > 0 || metrics.daGas.main > 0 || metrics.l2Gas.main > 0);
  const isNew = metrics.gates.main === 0 && metrics.daGas.main === 0 && metrics.l2Gas.main === 0 && 
              (metrics.gates.pr > 0 || metrics.daGas.pr > 0 || metrics.l2Gas.pr > 0);

  if (isRemoved) return '🚮';
  if (isNew) return '🆕';

  const gateDiffPct = metrics.gates.main === 0 ? (metrics.gates.pr > 0 ? Infinity : 0) : 
                    (metrics.gates.pr - metrics.gates.main) / metrics.gates.main;
  const daGasDiffPct = metrics.daGas.main === 0 ? (metrics.daGas.pr > 0 ? Infinity : 0) : 
                    (metrics.daGas.pr - metrics.daGas.main) / metrics.daGas.main;
  const l2GasDiffPct = metrics.l2Gas.main === 0 ? (metrics.l2Gas.pr > 0 ? Infinity : 0) : 
                    (metrics.l2Gas.pr - metrics.l2Gas.main) / metrics.l2Gas.main;

  const metricsDiffs = [gateDiffPct, daGasDiffPct, l2GasDiffPct].filter(m => isFinite(m));
  const hasInfiniteIncrease = [gateDiffPct, daGasDiffPct, l2GasDiffPct].some(m => m === Infinity);
  const thresholdDecimal = threshold;

  const hasRegression = hasInfiniteIncrease || metricsDiffs.some(m => m > thresholdDecimal);
  const hasImprovement = metricsDiffs.some(m => m < -thresholdDecimal);

  if (hasRegression) return '🔴';
  if (hasImprovement) return '🟢';
  return '🗿';
};


// Generates the Markdown table string for a single contract comparison
const generateContractComparisonTable = (mainData: ProfileReport, prData: ProfileReport, threshold: number): string => {
  const comparison: Record<string, ComparisonResult> = {};

  // Use results array for comparison as it contains detailed gas
  const allFunctionNames = new Set([
    ...mainData.results.map(r => r.name),
    ...prData.results.map(r => r.name)
  ]);

  for (const name of allFunctionNames) {
    if (!name || name.startsWith('unknown_function') || name.includes('(FAILED)')) {
      console.log(`Skipping comparison for malformed/failed entry: ${name}`);
      continue;
    }

    const mainResult = mainData.results.find((r) => r.name === name);
    const prResult = prData.results.find((r) => r.name === name);

    // Use helper functions to extract gas, default to 0 if result is missing
    comparison[name] = {
      gates: {
        main: mainResult?.totalGateCount ?? 0,
        pr: prResult?.totalGateCount ?? 0,
      },
      daGas: {
        main: getDaGas(mainResult),
        pr: getDaGas(prResult),
      },
      l2Gas: {
        main: getL2Gas(mainResult),
        pr: getL2Gas(prResult),
      },
    };
  }

  const output = [
    '<table>',
    '<tr>',
    '  <th></th>',
    '  <th>Function</th>',
    '  <th colspan="3">Gates</th>',
    '  <th colspan="3">DA Gas</th>',
    '  <th colspan="3">L2 Gas</th>',
    '</tr>',
    '<tr>',
    '  <th>🧪</th>',
    '  <th></th>',
    '  <th>Base</th>',
    '  <th>PR</th>',
    '  <th>Diff</th>',
    '  <th>Base</th>',
    '  <th>PR</th>',
    '  <th>Diff</th>',
    '  <th>Base</th>',
    '  <th>PR</th>',
    '  <th>Diff</th>',
    '</tr>',
  ];

  const sortedNames = Array.from(allFunctionNames).filter(name => name && comparison[name]).sort();

  for (const funcName of sortedNames) {
    const metrics = comparison[funcName];
    if (!metrics) continue; // Should not happen due to filter, but safety check

    const statusEmoji = getStatusEmoji(metrics, threshold);
    output.push(
      '<tr>',
      `  <td>${statusEmoji}</td>`,
      `  <td>${funcName}</td>`,
      // Gates
      `  <td>${metrics.gates.main}</td>`,
      `  <td>${metrics.gates.pr}</td>`,
      `  <td>${formatDiff(metrics.gates.main, metrics.gates.pr)}</td>`,
      // DA Gas
      `  <td>${metrics.daGas.main}</td>`,
      `  <td>${metrics.daGas.pr}</td>`,
      `  <td>${formatDiff(metrics.daGas.main, metrics.daGas.pr)}</td>`,
      // L2 Gas
      `  <td>${metrics.l2Gas.main}</td>`,
      `  <td>${metrics.l2Gas.pr}</td>`,
      `  <td>${formatDiff(metrics.l2Gas.main, metrics.l2Gas.pr)}</td>`,
      '</tr>',
    );
  }

  output.push('</table>');
  return output.join('\n');
};

// --- Main Execution Logic ---

async function run() {
  const program = new Command();
  program
    .option('-c, --contracts <names>', 'Comma-separated list of contract names to compare (e.g., token_contract,other). Defaults to all discoverable.')
    .option('-o, --output <file>', 'Output markdown report file', 'bench_diff.md')
    .option('-t, --threshold <number>', 'Threshold for significant change (decimal, e.g. 0.024 for 2.4%)', '0.024')
    .parse(process.argv);

  const options = program.opts();
  const requestedContracts = options.contracts ? options.contracts.split(',') : null;
  const outputFile = path.resolve(options.output); // Resolve path relative to CWD
  const threshold = parseFloat(options.threshold);

  console.log("Compare script starting...");
  console.log(`Threshold: ${threshold * 100}%`);
  console.log(`Output file: ${outputFile}`);

  const allContracts = await findBenchmarkableContracts();
  let contractsToCompare = allContracts;

  if (requestedContracts) {
    contractsToCompare = allContracts.filter(c => requestedContracts.includes(c.name));
    console.log(`Filtering comparison to contracts: ${contractsToCompare.map(c => c.name).join(', ')}`);
  }

  if (!contractsToCompare.length) {
    console.log("No contracts found or selected for comparison.");
    // Write an empty/informative report
    fs.writeFileSync(outputFile, '# Benchmark Comparison\n\nNo benchmark results found or selected to compare.\n');
    return;
  }

  let markdownOutput = ['<!-- benchmark-diff -->\n', '# Benchmark Comparison\n'];
  let contractsCompared = 0;

  for (const contractInfo of contractsToCompare) {
    const contractName = contractInfo.name;
    const contractPath = contractInfo.path;
    const baseJsonPath = path.join(contractPath, `${contractName}.benchmark.json`);
    const latestJsonPath = path.join(contractPath, `${contractName}.benchmark_latest.json`);

    console.log(`\nProcessing contract: ${contractName}...`);

    if (!fs.existsSync(baseJsonPath)) {
      console.warn(`  Skipping ${contractName}: Base benchmark file not found at ${baseJsonPath}`);
      continue;
    }
    if (!fs.existsSync(latestJsonPath)) {
      console.warn(`  Skipping ${contractName}: Latest benchmark file not found at ${latestJsonPath}`);
      continue;
    }

    try {
      const mainData: ProfileReport = JSON.parse(fs.readFileSync(baseJsonPath, 'utf-8'));
      const prData: ProfileReport = JSON.parse(fs.readFileSync(latestJsonPath, 'utf-8'));

      // Validate data structure minimally
      if (!mainData.results || !prData.results) {
        console.warn(`  Skipping ${contractName}: Invalid JSON structure (missing results array).`);
        continue;
      }

      console.log(`  Comparing ${mainData.results.length} base functions with ${prData.results.length} PR functions.`);

      const tableMarkdown = generateContractComparisonTable(mainData, prData, threshold);

      markdownOutput.push(`## Contract: ${contractName}\n`);
      markdownOutput.push(tableMarkdown);
      markdownOutput.push('\n'); // Add spacing between contract tables
      contractsCompared++;

    } catch (error: any) {
      console.error(`  Error processing benchmark files for ${contractName}:`, error.message);
      markdownOutput.push(`## Contract: ${contractName}\n`);
      markdownOutput.push(`\nError comparing benchmarks for this contract: ${error.message}\n`);
    }
  }

  if (contractsCompared === 0) {
    markdownOutput.push('\nNo contracts had valid pairs of benchmark files to compare.\n');
  }

  // Write the final combined report
  fs.writeFileSync(outputFile, markdownOutput.join('\n'));
  console.log(`\nComparison report for ${contractsCompared} contract(s) written to ${outputFile}`);

}

run().catch(error => {
  console.error("Benchmark comparison script failed:", error);
  process.exit(1);
}); 
