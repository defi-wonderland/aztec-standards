import { AztecAddress } from '@aztec/stdlib/aztec-address';
import { DEFAULT_SALT, NETWORK_URLS } from './constants.js';

export interface TokenConfig {
  name: string;
  symbol: string;
  decimals: number;
  salt: number;
}

export interface DripperConfig {
  salt: number;
  existingAddress?: AztecAddress;
}

export interface NetworkConfig {
  nodeUrl: string;
  name: string;
}

export interface DeploymentConfig {
  network: NetworkConfig;
  deployer: {
    dataDirectory: string;
  };
  contracts: {
    tokens: Record<string, TokenConfig>;
    dripper: DripperConfig;
    upgradeAuthority?: string;
  };
}

// TODO: add mainnet-alpha
export type Network = 'devnet-2' | 'testnet' | 'sandbox';

const TOKENS: Record<string, TokenConfig> = {
  weth: { name: 'WETH', symbol: 'WETH', decimals: 18, salt: DEFAULT_SALT },
  dai: { name: 'DAI', symbol: 'DAI', decimals: 9, salt: DEFAULT_SALT },
  usdc: { name: 'USDC', symbol: 'USDC', decimals: 6, salt: DEFAULT_SALT },
};

export function getConfig(network: Network): DeploymentConfig {
  const nodeUrl = process.env.AZTEC_NODE_URL || NETWORK_URLS[network];

  return {
    network: {
      nodeUrl,
      name: network === 'devnet-2' ? 'devnet' : network,
    },
    deployer: {
      dataDirectory: `${network === 'devnet-2' ? 'devnet' : network}-store/`,
    },
    contracts: {
      tokens: TOKENS,
      dripper: { salt: DEFAULT_SALT },
      upgradeAuthority: process.env.UPGRADE_AUTHORITY,
    },
  };
}
