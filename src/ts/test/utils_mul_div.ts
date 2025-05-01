import {
  createLogger,
  Fr,
  waitForPXE,
  AztecAddress,
  UniqueNote,
  AccountWallet,
  createPXEClient,
  FieldLike,
  Contract,
} from '@aztec/aztec.js';
import { MulDivContractArtifact } from '../../artifacts/MulDiv.js';

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
  expect(note.note.items[0]).toEqual(new Fr(owner.toBigInt()));
  expect(note.note.items[2]).toEqual(new Fr(amount));
};

export const expectAddressNote = (note: UniqueNote, address: AztecAddress, owner: AztecAddress) => {
  logger.info('checking address note {} {}', [address, owner]);
  expect(note.note.items[0]).toEqual(new Fr(address.toBigInt()));
  expect(note.note.items[1]).toEqual(new Fr(owner.toBigInt()));
};

export const expectAccountNote = (note: UniqueNote, owner: AztecAddress, secret?: FieldLike) => {
  logger.info('checking address note {} {}', [owner, secret]);
  expect(note.note.items[0]).toEqual(new Fr(owner.toBigInt()));
  if (secret !== undefined) {
    expect(note.note.items[1]).toEqual(secret);
  }
};

/**
 * Deploys the Token contract with a specified minter.
 * @param deployer - The wallet to deploy the contract with.
 * @returns A deployed contract instance.
 */
export async function deployDivMul(deployer: AccountWallet) {
  const contract = await Contract.deploy(
    deployer,
    MulDivContractArtifact,
    [],
    'constructor',
  )
    .send()
    .deployed();
  return contract;
}
