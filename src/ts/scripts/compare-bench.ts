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

const getPublicOverhead = (data: CircuitData[]): number => {
  const overhead = data.find((v) => v.gateCounts.length === 4)?.totalGateCount || 0;
  return overhead;
};

const createComparisonTable = (mainData: GateCounts, prData: GateCounts, threshold: number): void => {
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
    const statusEmoji = getStatusEmoji(metrics, threshold);
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

const formatDiff = (main: number, pr: number): string => {
  if (!main && !pr) return '-';
  // new in PR
  if (!main) return '+100%';
  // removed in PR
  if (!pr) return '-100%';

  const diff = pr - main;
  if (diff === 0) return '0';

  const pct = ((diff / main) * 100).toFixed(1);
  return `${diff}&nbsp;(${pct}%)`;
};

const getStatusEmoji = (metrics: ComparisonResult, threshold: number) => {
  // Function exists in main, but doesn't exist in PR
  if (metrics.l2Gas.main > 0 && metrics.l2Gas.pr === 0) return '🚮';

  // Function doesn't exist in main, but exists in PR
  if (metrics.l2Gas.main === 0 && metrics.l2Gas.pr > 0) return '🆕';

  const metricsDiffs = [
    metrics.gates.diff / metrics.gates.main,
    metrics.daGas.diff / metrics.daGas.main,
    metrics.l2Gas.diff / metrics.l2Gas.main,
  ];

  // if all metrics are within the threshold, we return a moai
  if (!metricsDiffs.some((m) => Math.abs(m) > threshold)) return '🗿';
  // check if any metric is outside the threshold
  return metricsDiffs.some((m) => m > threshold) ? '🟢' : '🔴';
};

// TODO: threshold should be taken from a CI env variable
if (process.argv.length < 6) {
  console.error('Usage: tsx compare-bench.ts <main-bench-json-file> <pr-bench-json-file> <output-file> threshold');
  process.exit(1);
}

Promise.resolve()
  .then(() => {
    const mainData = JSON.parse(readFileSync(resolve(process.argv[2]), 'utf8'));
    const prData = JSON.parse(readFileSync(resolve(process.argv[3]), 'utf8'));
    createComparisonTable(mainData, prData, parseFloat(process.argv[5]));
  })
  .catch(console.error);
