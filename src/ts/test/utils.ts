import { createLogger, Fr, waitForPXE, AztecAddress, UniqueNote, AccountWallet } from '@aztec/aztec.js';
import { createPXEClient } from '@aztec/aztec.js';
import { TokenContract } from '../../artifacts/Token.js';

export const logger = createLogger('aztec:aztec-standards');

export const createPXE = async (id: number = 0) => {
  const { BASE_PXE_URL = `http://localhost` } = process.env;
  const url = `${BASE_PXE_URL}:${8080 + id}`;
  const pxe = createPXEClient(url);
  logger.info(`Waiting for PXE to be ready at ${url}`);
  await waitForPXE(pxe);
  return pxe;
};

export const setupSandbox = async () => {
  return createPXE();
};

export const expectUintNote = (note: UniqueNote, amount: bigint, owner: AztecAddress) => {
  // 3th element of items is randomness, so we slice the first 2
  expect(note.note.items.slice(0, 2)).toStrictEqual([new Fr(amount), new Fr(owner.toBigInt())]);
};

export const expectAddressNote = (note: UniqueNote, address: AztecAddress, owner: AztecAddress) => {
  logger.info('checking address note {} {}', [address, owner]);
  expect(note.note.items[0]).toEqual(new Fr(address.toBigInt()));
  expect(note.note.items[1]).toEqual(new Fr(owner.toBigInt()));
};

export const expectTokenBalances = async (
  token: TokenContract,
  address: AztecAddress,
  publicBalance: bigint,
  privateBalance: bigint,
  caller?: AccountWallet,
) => {
  logger.info('checking balances for', address.toString());
  const t = caller ? token.withWallet(caller) : token;
  expect(await t.methods.balance_of_public(address).simulate()).toBe(publicBalance);
  expect(await t.methods.balance_of_private(address).simulate()).toBe(privateBalance);
};

export const AMOUNT = 1000n;
export const wad = (n: number = 1) => AMOUNT * BigInt(n);
