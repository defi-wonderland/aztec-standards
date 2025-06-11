import { ContractInstanceWithAddress, Fr, getContractInstanceFromDeployParams } from '@aztec/aztec.js';
import { SponsoredFPCContract } from '@aztec/noir-contracts.js/SponsoredFPC';
import { Wallet } from '@aztec/aztec.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { SponsoredFeePaymentMethod } from '@aztec/aztec.js/fee/testing';

export const SPONSORED_FPC_SALT = new Fr(0);

export async function getSponsoredFPCInstance(): Promise<ContractInstanceWithAddress> {
  return await getContractInstanceFromDeployParams(SponsoredFPCContract.artifact, {
    salt: SPONSORED_FPC_SALT,
  });
}

export async function getSponsoredFPCAddress() {
  return (await getSponsoredFPCInstance()).address;
}

export async function deploySponsoredFPC(deployer: Wallet): Promise<SponsoredFPCContract> {
  const deployed = await SponsoredFPCContract.deploy(deployer)
    .send({ contractAddressSalt: SPONSORED_FPC_SALT, universalDeploy: true })
    .deployed();
  return deployed;
}

export async function setupSponsoredFPC(pxe: PXE, deployer?: Wallet) {
  if (deployer) {
    await deploySponsoredFPC(deployer);
  }
  const instance = (
    deployer ? await deploySponsoredFPC(deployer) : await getSponsoredFPCInstance()
  ) as ContractInstanceWithAddress;
  pxe.registerContract({ instance, artifact: SponsoredFPCContract.artifact });
  return instance;
}

export async function getDeployedSponsoredFPCAddress(pxe: PXE) {
  const fpc = await getSponsoredFPCAddress();
  const contracts = await pxe.getContracts();
  if (!contracts.find((c) => c.equals(fpc))) {
    throw new Error('SponsoredFPC not deployed.');
  }
  return fpc;
}

// todo: we can initialize this once
export const getSponsoredFeePaymentMethod = async (pxe: PXE) => {
  return new SponsoredFeePaymentMethod(await getDeployedSponsoredFPCAddress(pxe));
};
