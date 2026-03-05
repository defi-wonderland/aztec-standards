import { AztecAddress } from '@aztec/stdlib/aztec-address';

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
    pxeVersion: number;
    dataDirectory: string;
  };
  contracts: {
    tokens: {
      weth: TokenConfig;
      dai: TokenConfig;
      usdc: TokenConfig;
    };
    dripper: DripperConfig;
    upgradeAuthority?: string;
  };
  deployment: {
    deployDelay: number;
  };
}

// TODO: add mainnet-alpha
export type Network = 'devnet-2' | 'testnet' | 'sandbox';

export function getConfig(network: Network): DeploymentConfig {
  const nodeUrl = process.env.AZTEC_NODE_URL;

  const baseConfig = {
    contracts: {
      tokens: {
        weth: { name: 'WETH', symbol: 'WETH', decimals: 18, salt: 1337 },
        dai: { name: 'DAI', symbol: 'DAI', decimals: 9, salt: 1337 },
        usdc: { name: 'USDC', symbol: 'USDC', decimals: 6, salt: 1337 },
      },
      dripper: { salt: 1337 } as DripperConfig,
      upgradeAuthority: process.env.UPGRADE_AUTHORITY,
    },
    deployment: {
      deployDelay: 24000,
    },
  };

  switch (network) {
    case 'devnet-2':
      return {
        ...baseConfig,
        network: {
          nodeUrl: nodeUrl || 'https://v4-devnet-2.aztec-labs.com',
          name: 'devnet',
        },
        deployer: {
          pxeVersion: 2,
          dataDirectory: 'devnet-store/',
        },
      };
    case 'testnet':
      return {
        ...baseConfig,
        network: {
          nodeUrl: nodeUrl || 'https://testnet.aztec-labs.com',
          name: 'testnet',
        },
        deployer: {
          pxeVersion: 2,
          dataDirectory: 'testnet-store/',
        },
      };
    case 'sandbox':
      return {
        ...baseConfig,
        network: {
          nodeUrl: nodeUrl || 'http://localhost:8080',
          name: 'sandbox',
        },
        deployer: {
          pxeVersion: 2,
          dataDirectory: 'sandbox-store/',
        },
        deployment: {
          ...baseConfig.deployment,
          deployDelay: 1000,
        },
      };
  }
}
