import { ClawbackEscrowContract } from '../src/artifacts/ClawbackEscrow.js';
import { createLogger, Fr, PXE, waitForPXE, createPXEClient, Logger } from '@aztec/aztec.js';
import { getSchnorrAccount } from '@aztec/accounts/schnorr';
import { deriveSigningKey } from '@aztec/circuits.js';

const setupSandbox = async () => {
  const { PXE_URL = 'http://localhost:8080' } = process.env;
  const pxe = await createPXEClient(PXE_URL);
  await waitForPXE(pxe);
  return pxe;
};

async function main() {
  let pxe: PXE;
  let logger: Logger;

  logger = createLogger('aztec:aztec-starter');

  pxe = await setupSandbox();

  let secretKey = Fr.random();
  let salt = Fr.random();

  let schnorrAccount = await getSchnorrAccount(pxe, secretKey, deriveSigningKey(secretKey), salt);
  let tx = await schnorrAccount.deploy().wait();
  let wallet = await schnorrAccount.getWallet();

  const escrowContract = await ClawbackEscrowContract.deploy(wallet).send().deployed();

  logger.info(`Escrow Contract deployed at: ${escrowContract.address}`);
}

main();
