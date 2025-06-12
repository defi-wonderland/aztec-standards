import { AccountManager, Fr } from '@aztec/aztec.js';
import { getSchnorrAccount } from '@aztec/accounts/schnorr';
import { deriveSigningKey } from '@aztec/stdlib/keys';
import { PXE } from '@aztec/stdlib/interfaces/client';

export async function deployRandomSchnorrAccount(pxe: PXE, options?: any): Promise<AccountManager> {
  let secretKey = Fr.random();
  let salt = Fr.random();

  let schnorrAccount = await getSchnorrAccount(pxe, secretKey, deriveSigningKey(secretKey), salt);
  const deployTx = await schnorrAccount.deploy({
    ...options,
  });
  await deployTx.wait();
  return schnorrAccount;
}

export async function deploySchnorrAccount(pxe: PXE, secretKey: Fr, salt: Fr, options?: any): Promise<AccountManager> {
  let schnorrAccount = await getSchnorrAccount(pxe, secretKey, deriveSigningKey(secretKey), salt);
  const deployTx = await schnorrAccount.deploy({
    ...options,
  });
  await deployTx.wait();
  return schnorrAccount;
}
