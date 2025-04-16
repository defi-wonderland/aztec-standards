import { writeFileSync, readFileSync } from 'fs';
import { resolve } from 'path';

interface CircuitData {
  name: string;
  totalGateCount: number;
  gateCounts: Array<{
    circuitName: string;
    gateCount: number;
  }>;
  gas: {
    gasLimits: {
      daGas: number;
      l2Gas: number;
    };
    teardownGasLimits: {
      daGas: number;
      l2Gas: number;
    };
  };
}

interface GateCounts {
  summary: Record<string, number>;
  results: CircuitData[];
  gasSummary: Record<string, number>;
}

interface MetricComparison {
  main: number;
  pr: number;
  diff: number;
}

interface ComparisonResult {
  gates: MetricComparison;
  daGas: MetricComparison;
  l2Gas: MetricComparison;
}

const formatDiff = (mainValue: number, prValue: number): string => {
  // console.log(mainValue, prValue);
  const diff = mainValue - prValue;
  if (diff === 0) return '0';
  // when main value 0, it means that the main's impl do not have a circuit to compare it
  if (mainValue === 0) return '+100%';
  const percent = ((Math.abs(diff) / mainValue) * 100).toFixed(1);
  const sign = diff > 0 ? '+' : '-';
  return `${diff} (${sign}${percent}%)`;
};

const getPublicOverhead = (data: CircuitData[]): number => {
  const overhead = data.find((v) => v.gateCounts.length === 4)?.totalGateCount || 0;
  return overhead;
};

const createComparisonTable = (mainData: GateCounts, prData: GateCounts): void => {
  const mainOverhead = getPublicOverhead(mainData.results);
  const prOverhead = getPublicOverhead(prData.results);
  const comparison: Record<string, ComparisonResult> = {};

  // Get all unique function names from both main and PR
  const allFunctions = new Set([...mainData.results.map((r) => r.name), ...prData.results.map((r) => r.name)]);

  for (const name of allFunctions) {
    const mainResult = mainData.results.find((r) => r.name === name);
    const prResult = prData.results.find((r) => r.name === name);

    comparison[name] = {
      gates: {
        main: mainResult ? mainResult.totalGateCount - mainOverhead : 0,
        pr: prResult ? prResult.totalGateCount - prOverhead : 0,
        diff: (mainResult?.totalGateCount ?? 0) - mainOverhead - ((prResult?.totalGateCount ?? 0) - prOverhead),
      },
      daGas: {
        main: mainResult?.gas.gasLimits.daGas ?? 0,
        pr: prResult?.gas.gasLimits.daGas ?? 0,
        diff: (mainResult?.gas.gasLimits.daGas ?? 0) - (prResult?.gas.gasLimits.daGas ?? 0),
      },
      l2Gas: {
        main: mainResult?.gas.gasLimits.l2Gas ?? 0,
        pr: prResult?.gas.gasLimits.l2Gas ?? 0,
        diff: (mainResult?.gas.gasLimits.l2Gas ?? 0) - (prResult?.gas.gasLimits.l2Gas ?? 0),
      },
    };
  }

  const output = [
    '<!-- benchmark-diff -->\n',
    '# Benchmark Comparison\n',
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
    '  <th>main</th>',
    '  <th>PR</th>',
    '  <th>diff</th>',
    '  <th>main</th>',
    '  <th>PR</th>',
    '  <th>diff</th>',
    '  <th>main</th>',
    '  <th>PR</th>',
    '  <th>diff</th>',
    '</tr>',
  ];

  // For each function in the benchmark object we push one row to the table
  for (const [funcName, metrics] of Object.entries(comparison)) {
    const statusEmoji = getStatusEmoji(metrics);
    output.push(
      '<tr>',
      `  <td>${statusEmoji}</td>`,
      `  <td>${funcName}</td>`,
      `  <td>${metrics.gates.main}</td>`,
      `  <td>${metrics.gates.pr}</td>`,
      `  <td>${formatDiff(metrics.gates.main, metrics.gates.pr)}</td>`,
      `  <td>${metrics.daGas.main}</td>`,
      `  <td>${metrics.daGas.pr}</td>`,
      `  <td>${formatDiff(metrics.daGas.main, metrics.daGas.pr)}</td>`,
      `  <td>${metrics.l2Gas.main}</td>`,
      `  <td>${metrics.l2Gas.pr}</td>`,
      `  <td>${formatDiff(metrics.l2Gas.main, metrics.l2Gas.pr)}</td>`,
      '</tr>',
    );
  }

  output.push('</table>');

  writeFileSync(resolve(process.argv[4]), output.join('\n'));
};

const getStatusEmoji = (metrics: ComparisonResult) => {
  // Function exists in main, but doesn't exist in PR
  if (metrics.gates.main > 0 && metrics.gates.pr === 0) return '🚮';

  // Function doesn't exist in main, but exists in PR
  if (metrics.gates.main === 0 && metrics.gates.pr > 0) return '🆕';

  // No changes across all metrics
  if (metrics.gates.diff === 0 && metrics.daGas.diff === 0 && metrics.l2Gas.diff === 0) return '🗿';

  return metrics.gates.diff > 0 || metrics.daGas.diff > 0 || metrics.l2Gas.diff > 0 ? '❌' : '✅';
};

if (process.argv.length !== 5) {
  console.error('Usage: tsx compare-bench.ts <main-bench-json-file> <pr-bench-json-file> <output-file>');
  process.exit(1);
}

Promise.resolve()
  .then(() => {
    const mainData = JSON.parse(readFileSync(resolve(process.argv[2]), 'utf8'));
    const prData = JSON.parse(readFileSync(resolve(process.argv[3]), 'utf8'));
    createComparisonTable(mainData, prData);
  })
  .catch(console.error);
