import {
  AccountWallet,
  CompleteAddress,
  ContractDeployer,
  createLogger,
  Fr,
  PXE,
  waitForPXE,
  TxStatus,
  createPXEClient,
  getContractInstanceFromDeployParams,
  Logger,
  Contract,
  AztecAddress,
  AccountWalletWithSecretKey,
  Wallet,
  UniqueNote,
} from '@aztec/aztec.js';
import { createAccount, getInitialTestAccountsWallets } from '@aztec/accounts/testing';

export const logger = createLogger('aztec:aztec-standards');

export const createPXE = async (id: number = 0) => {
  // TODO: we should probably define testing fixtures for this kind of configuration
  const { BASE_PXE_URL = `http://localhost` } = process.env;
  const url = `${BASE_PXE_URL}:${8080 + id}`;
  const pxe = createPXEClient(url);
  await waitForPXE(pxe);
  return pxe;
};

export const setupSandbox = async () => {
  return createPXE();
};
