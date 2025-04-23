import { type ContractFunctionInteraction } from '@aztec/aztec.js';
import { GasDimensions } from '@aztec/stdlib/gas';

// Export directly without redefinition
export { GasDimensions };

// Simplified Gas type
export type Gas = {
  daGas: number;
  l2Gas: number;
};

// Shared gas utility functions
export function getDaGas(result?: { gas?: Record<string, Gas> }): number {
  if (!result?.gas) return 0;
  const limits = result.gas.gasLimits?.daGas ?? 0;
  const teardown = result.gas.teardownGasLimits?.daGas ?? 0;
  return limits + teardown;
}

export function getL2Gas(result?: { gas?: Record<string, Gas> }): number {
  if (!result?.gas) return 0;
  const limits = result.gas.gasLimits?.l2Gas ?? 0;
  const teardown = result.gas.teardownGasLimits?.l2Gas ?? 0;
  return limits + teardown;
}

// Type for the result of profiling a single function
export type ProfileResult = {
  readonly name: string;
  readonly totalGateCount: number;
  readonly gateCounts: readonly {
    readonly circuitName: string;
    readonly gateCount: number;
  }[];
  readonly gas: Record<'gasLimits' | 'teardownGasLimits', Gas>;
};

// Type for the overall benchmark report JSON
export type ProfileReport = {
  readonly summary: Record<string, number>; // function name -> total gate count
  readonly results: readonly ProfileResult[];
  readonly gasSummary: Record<string, number>; // function name -> total gas (DA + L2)
};

// Generic context passed between setup and getMethods in individual benchmark files.
// Specific benchmarks can add their own required properties (like contract instances).
export interface BenchmarkRunContext {
  [key: string]: any;
}

// Expected structure of the default export from a *.benchmark.ts file
export interface BenchmarkConfig {
  // Setup function is optional
  setup?: () => Promise<BenchmarkRunContext>;
  // getMethods function is required and receives the context from setup
  getMethods: (context: BenchmarkRunContext) => ContractFunctionInteraction[];
} 