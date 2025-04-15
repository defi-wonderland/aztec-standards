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

const formatNumber = (num: number): string => num.toLocaleString().padStart(8, ' ');

const formatDiff = (mainValue: number, prValue: number): string => {
  const diff = prValue - mainValue;
  if (diff === 0) return '0';
  // This case is for when the old value is 0, which means that the base's impl do not have the circuit to compare with
  if (mainValue === 0) return '0';
  const percent = ((diff / mainValue) * 100).toFixed(1);
  const sign = diff >= 0 ? '+' : '';
  return `${diff} (${sign}${percent}%)`;
};

const getPublicOverhead = (data: CircuitData[]): number => {
  const overhead = data.find((v) => v.gateCounts.length === 4)?.totalGateCount || 0;
  return overhead;
};

const createComparisonTable = (mainData: GateCounts, prData: GateCounts): void => {
  const mainOverhead = getPublicOverhead(mainData.results);
  const prOverhead = getPublicOverhead(prData.results);

  const comparison: Record<
    string,
    {
      gates: { main: number; pr: number; diff: number };
      daGas: { main: number; pr: number; diff: number };
      l2Gas: { main: number; pr: number; diff: number };
    }
  > = {};

  for (const mainResult of mainData.results) {
    const prResult = prData.results.find((r) => r.name === mainResult.name);
    if (!prResult) continue;

    comparison[mainResult.name] = {
      gates: {
        main: mainResult.totalGateCount - mainOverhead,
        pr: prResult.totalGateCount - prOverhead,
        diff: prResult.totalGateCount - prOverhead - (mainResult.totalGateCount - mainOverhead),
      },
      daGas: {
        main: mainResult.gas.gasLimits.daGas,
        pr: prResult.gas.gasLimits.daGas,
        diff: prResult.gas.gasLimits.daGas - mainResult.gas.gasLimits.daGas,
      },
      l2Gas: {
        main: mainResult.gas.gasLimits.l2Gas,
        pr: prResult.gas.gasLimits.l2Gas,
        diff: prResult.gas.gasLimits.l2Gas - mainResult.gas.gasLimits.l2Gas,
      },
    };
  }

  const output = [
    '<!-- benchmark-diff -->\n',
    '# Benchmark Comparison\n',
    '<table>',
    '<tr>',
    '  <th>🧪</th>',
    '  <th>Function</th>',
    '  <th colspan="3">Gates</th>',
    '  <th colspan="3">DA Gas</th>',
    '  <th colspan="3">L2 Gas</th>',
    '</tr>',
    '<tr>',
    '  <th></th>',
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

const getStatusEmoji = (metrics: any) => {
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
