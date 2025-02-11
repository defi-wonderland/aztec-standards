import { EscrowContract } from '../src/artifacts/Escrow.js';
import { createLogger, Fr, PXE, waitForPXE, createPXEClient, Logger } from '@aztec/aztec.js';
import { getSchnorrAccount } from '@aztec/accounts/schnorr';
import { AztecAddress, computePartialAddress, deriveKeys, deriveSigningKey } from '@aztec/circuits.js';

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

  console.log({ secretKey, salt });

  let schnorrAccount = await getSchnorrAccount(pxe, secretKey, deriveSigningKey(secretKey), salt);
  let tx = await schnorrAccount.deploy().wait();
  let wallet = await schnorrAccount.getWallet();

  // NOTE: previously generated address (added to pxe)
  const owner_address = AztecAddress.fromString('0x0806a6d55a80adc660f67d190f4e53b63795d128432eea63aeb1f914ff59ae3f');

  const escrowSecretKey = Fr.random();
  console.log({ escrowSecretKey });
  const escrowPublicKeys = (await deriveKeys(escrowSecretKey)).publicKeys;

  const escrowDeployment = EscrowContract.deployWithPublicKeys(escrowPublicKeys, wallet, owner_address);
  const escrowInstance = await escrowDeployment.getInstance();
  pxe.registerAccount(escrowSecretKey, await computePartialAddress(escrowInstance));

  const escrowContract = await escrowDeployment.send().deployed();
  logger.info(`Escrow Contract deployed at: ${escrowContract.address}`);
}

main();
