import { createEthereumChain, createExtendedL1Client } from '@aztec/ethereum';
import { L1FeeJuicePortalManager, PXE } from '@aztec/aztec.js';
import { logger } from '../test/utils.js';

export async function setupFeeJuicePortalManager(pxe: PXE): Promise<L1FeeJuicePortalManager> {
  // create default ethereum clients
  const nodeInfo = await pxe.getNodeInfo();
  const chain = createEthereumChain(['http://localhost:8545'], nodeInfo.l1ChainId);
  const DefaultMnemonic = 'test test test test test test test test test test test junk';
  const l1Client = createExtendedL1Client(chain.rpcUrls, DefaultMnemonic, chain.chainInfo);

  const feeJuiceAddress = nodeInfo.protocolContractAddresses.feeJuice;

  // create portal manager
  const l1PortalManager = await L1FeeJuicePortalManager.new(pxe, l1Client, logger);

  return l1PortalManager;
}
