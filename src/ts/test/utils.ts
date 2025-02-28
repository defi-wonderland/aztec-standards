import {
  createLogger,
  Fr,
  waitForPXE,
  AztecAddress,
  UniqueNote,
  AccountWallet,
  PXE,
  Wallet,
  createPXEClient,
  AccountWalletWithSecretKey,
} from '@aztec/aztec.js';
import { computePartialAddress, deriveKeys } from '@aztec/circuits.js';
import { TokenContract } from '../../artifacts/Token.js';
import { EscrowContract } from '../../artifacts/Escrow.js';
import { ClawbackEscrowContract } from '../../artifacts/ClawbackEscrow.js';

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

export async function deployEscrow(pxes: PXE[], deployerWallet: Wallet, owner: AztecAddress): Promise<EscrowContract> {
  const escrowSecretKey = Fr.random();
  const escrowPublicKeys = (await deriveKeys(escrowSecretKey)).publicKeys;
  const escrowDeployment = EscrowContract.deployWithPublicKeys(escrowPublicKeys, deployerWallet, owner);
  const escrowInstance = await escrowDeployment.getInstance();

  await pxes[0].registerAccount(escrowSecretKey, await computePartialAddress(escrowInstance));
  // TODO: instead of register it here for Bob, we should use the Escrow::PrivacyKeys event (or something else!)
  await pxes[1].registerAccount(escrowSecretKey, await computePartialAddress(escrowInstance));

  const escrowContract = await escrowDeployment.send().deployed();

  const contractMetadata = await pxes[0].getContractMetadata(escrowInstance.address);
  expect(contractMetadata.isContractPubliclyDeployed).toBeTruthy();

  logger.info('escrow deployed', escrowContract.address);
  return escrowContract;
}

export async function deployClawbackEscrow(pxes: PXE[], deployerWallet: AccountWalletWithSecretKey) {
  // TODO: clawback doesn't need a secret key, but I can't make it without it
  // const clawbackDeployment = ClawbackEscrowContract.deploy(deployerWallet);
  // const clawbackContract = await clawbackDeployment.send({}).deployed();
  // await Promise.all(pxes.map(async (pxe) => pxe.registerContract(clawbackContract)));

  const clawbackSecretKey = Fr.random();
  const clawbackPublicKeys = (await deriveKeys(clawbackSecretKey)).publicKeys;
  const clawbackDeployment = ClawbackEscrowContract.deployWithPublicKeys(clawbackPublicKeys, deployerWallet);
  const clawbackInstance = await clawbackDeployment.getInstance();
  const tx = await clawbackDeployment.send().wait();
  const clawbackContract = await ClawbackEscrowContract.at(clawbackInstance.address, deployerWallet);

  await pxes[0].registerAccount(clawbackSecretKey, await computePartialAddress(clawbackInstance));
  await pxes[1].registerAccount(clawbackSecretKey, await computePartialAddress(clawbackInstance));

  logger.info(`clawback address: ${clawbackContract.address}`);
  return clawbackContract;
}
