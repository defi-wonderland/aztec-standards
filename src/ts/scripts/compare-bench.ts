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

const formatDiff = (oldVal: number, newVal: number): string => {
  if (oldVal === 0) return formatNumber(newVal);
  const diff = newVal - oldVal;
  const percent = ((diff / oldVal) * 100).toFixed(1);
  const sign = diff >= 0 ? '+' : '';
  return `${formatNumber(newVal)} (${sign}${percent}%)`;
};

const getPublicOverhead = (data: CircuitData[]): number =>
  data.find((v) => v.gateCounts.length === 4)?.totalGateCount || 0;

const createComparisonTable = (oldData: GateCounts, newData: GateCounts): void => {
  const oldOverhead = getPublicOverhead(oldData.results);
  const newOverhead = getPublicOverhead(newData.results);

  const output = [
    '<!-- benchmark-diff -->\n',
    '# Gate Count Comparison (U253 vs U128)\n',
    '| Function | Gates | DA Gas | L2 Gas |',
    '|-----------|--------|---------|---------|',
  ]
    .concat(
      [...new Set([...Object.keys(oldData.summary), ...Object.keys(newData.summary)])].map((funcName) => {
        const old = oldData.results.find((r) => r.name === funcName);
        const new_ = newData.results.find((r) => r.name === funcName);

        if (!old || !new_) return `| ${funcName} | INVALID | INVALID | INVALID |`;

        const oldGates = old.gateCounts.length === 4 ? 0 : old.totalGateCount - oldOverhead;
        const newGates = new_.gateCounts.length === 4 ? 0 : new_.totalGateCount - newOverhead;

        return (
          `| ${funcName} ` +
          `| ${formatDiff(oldGates, newGates)} ` +
          `| ${formatDiff(old.gas.gasLimits.daGas, new_.gas.gasLimits.daGas)} ` +
          `| ${formatDiff(old.gas.gasLimits.l2Gas, new_.gas.gasLimits.l2Gas)} |`
        );
      }),
    )
    .join('\n');

  writeFileSync('bench_diff.md', output);
};

if (process.argv.length !== 4) {
  console.error('Usage: tsx compare-bench.ts <old-json-file> <new-json-file>');
  process.exit(1);
}

Promise.resolve()
  .then(() => {
    const oldData = JSON.parse(readFileSync(resolve(process.argv[2]), 'utf8'));
    const newData = JSON.parse(readFileSync(resolve(process.argv[3]), 'utf8'));
    createComparisonTable(oldData, newData);
  })
  .catch(console.error);
