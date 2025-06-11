import { createAztecNodeClient, waitForPXE } from '@aztec/aztec.js';
import { getPXEServiceConfig } from '@aztec/pxe/config';
import { createPXEService } from '@aztec/pxe/server';
import { createStore } from '@aztec/kv-store/lmdb';

const { NODE_URL = 'http://localhost:8080' } = process.env;
const node = createAztecNodeClient(NODE_URL);
const l1Contracts = await node.getL1ContractAddresses();
const config = getPXEServiceConfig();
const fullConfig = { ...config, l1Contracts };
fullConfig.proverEnabled = false;

const store = await createStore('pxe', {
  dataDirectory: 'store',
  dataStoreMapSizeKB: 1e6,
});

export const setupPXE = async () => {
  const pxe = await createPXEService(node, fullConfig, { store });
  await waitForPXE(pxe);
  return pxe;
};

// export const createPXE = async (id: number = 0) => {
//   const { BASE_PXE_URL = `http://localhost` } = process.env;
//   const url = `${BASE_PXE_URL}:${8080 + id}`;
//   const pxe = createPXEClient(url);
//   logger.info(`Waiting for PXE to be ready at ${url}`);
//   await waitForPXE(pxe);
//   return pxe;
// };

// export const setupSandbox = async () => {
//   return createPXE();
// };
