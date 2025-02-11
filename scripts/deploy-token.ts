import { TokenContract } from '../src/artifacts/Token.js';
import { createLogger, Fr, PXE, waitForPXE, createPXEClient, Logger } from '@aztec/aztec.js';
import { getSchnorrAccount } from '@aztec/accounts/schnorr';
import { AztecAddress, deriveSigningKey } from '@aztec/circuits.js';

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
  const { address, publicKeys, partialAddress } = await schnorrAccount.getCompleteAddress();
  let tx = await schnorrAccount.deploy().wait();
  let wallet = await schnorrAccount.getWallet();

  const tokenContract = await TokenContract.deploy(wallet, address, 'Wonderland', 'WND', 18).send().deployed();
  logger.info(`Token Contract deployed at: ${tokenContract.address}`);
}

async function mintToken() {
  let pxe: PXE;
  let logger: Logger;

  logger = createLogger('aztec:aztec-starter');

  pxe = await setupSandbox();

  // NOTE: previously generated secret keys and deployed token address
  let secretKey = Fr.fromHexString('0x13004a45309b86e0116c222df1c9e67c6ec222a3e3cc56cb58229f7916fa75c3');
  let salt = Fr.fromHexString('0x008ba3a7881ecba0996396298975620a1b4ecff7369af2925b8943e29a551327');
  let tokenAddress = AztecAddress.fromString('0x0092b73ffeea8df730acba5fbf4b177af117ce35cba989aae7618eed2d668a75');

  let schnorrAccount = await getSchnorrAccount(pxe, secretKey, deriveSigningKey(secretKey), salt);
  const { address, publicKeys, partialAddress } = await schnorrAccount.getCompleteAddress();
  let wallet = await schnorrAccount.getWallet();

  let mint_tx = await (await TokenContract.at(tokenAddress, wallet)).methods
    .mint_to_private(address, address, 1000000000000000000n)
    .send()
    .wait({ debug: true });
  console.log(mint_tx);
}

main();
// mintToken();
