import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // aztec sandbox tests take quite some time
    hookTimeout: 200000,
    testTimeout: 200000,
    // TODO: check why tests fail when we run them in parallel
    fileParallelism: false,
  },
});
