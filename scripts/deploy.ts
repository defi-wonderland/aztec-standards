#!/usr/bin/env tsx

import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

interface TokenConfig {
  name: string;
  symbol: string;
  decimals: number;
}

interface DeploymentResult {
  address: string;
  txHash: string;
  deploymentFee: string;
}

interface DeploymentsJson {
  tokens: Array<{
    name: string;
    symbol: string;
    address: string;
    decimals: number;
    minter: string;
    upgrade_authority: string;
  }>;
  dripper: {
    address: string;
  };
}

class AztecDeployer {
  private maxRetries: number;
  private retryDelay: number;
  private rpcUrl: string;
  private accountAlias: string;

  constructor() {
    this.maxRetries = 5;
    this.retryDelay = 5000; // 5 seconds
    this.rpcUrl = process.env.AZTEC_RPC_URL || 'https://api.aztec.network/aztec-connect-testnet/falafel';
    this.accountAlias = process.env.AZTEC_ACCOUNT_ALIAS || 'deployer';
  }

  private async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  private async executeWithRetry<T>(
    operation: () => Promise<T>,
    operationName: string
  ): Promise<T> {
    let lastError: Error | undefined;
    
    for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
      try {
        console.log(`📝 Attempting ${operationName} (attempt ${attempt}/${this.maxRetries})`);
        const result = await operation();
        console.log(`✅ ${operationName} succeeded on attempt ${attempt}`);
        return result;
      } catch (error) {
        lastError = error as Error;
        console.log(`❌ ${operationName} failed on attempt ${attempt}: ${lastError.message}`);
        
        if (attempt < this.maxRetries) {
          const delay = this.retryDelay * attempt; // Exponential backoff
          console.log(`⏳ Waiting ${delay/1000} seconds before retry...`);
          await this.sleep(delay);
        }
      }
    }
    
    throw new Error(`${operationName} failed after ${this.maxRetries} attempts. Last error: ${lastError?.message}`);
  }

  private async execCommand(command: string): Promise<string> {
    return new Promise((resolve, reject) => {
      try {
        const output = execSync(command, { 
          encoding: 'utf8',
          stdio: ['pipe', 'pipe', 'pipe'],
          timeout: 300000 // 5 minutes timeout
        });
        resolve(output);
      } catch (error: any) {
        reject(new Error(`Command failed: ${command}\nError: ${error.message}\nStderr: ${error.stderr}`));
      }
    });
  }

  private parseDeploymentOutput(output: string): DeploymentResult {
    const addressMatch = output.match(/Contract deployed at\s+(0x[a-fA-F0-9]+)/);
    const txHashMatch = output.match(/Deployment tx hash:\s+([a-fA-F0-9]+)/);
    const feeMatch = output.match(/Deployment fee:\s+(\d+)/);

    if (!addressMatch) {
      throw new Error('Could not parse contract address from deployment output');
    }

    return {
      address: addressMatch[1],
      txHash: txHashMatch?.[1] || 'unknown',
      deploymentFee: feeMatch?.[1] || 'unknown'
    };
  }

  private async ensureAccountExists(): Promise<void> {
    console.log('🔍 Checking if deployment account exists...');
    
    try {
      await this.execCommand(`aztec-wallet get-alias accounts:${this.accountAlias}`);
      console.log(`✅ Account '${this.accountAlias}' already exists`);
    } catch (error) {
      console.log(`📝 Creating new account '${this.accountAlias}'...`);
      
      // Create account with fee juice payment
      const command = `aztec-wallet create-account -a ${this.accountAlias} --payment method=fee_juice,feePayer=test0`;
      await this.executeWithRetry(
        () => this.execCommand(command),
        `Creating account ${this.accountAlias}`
      );
      
      console.log(`✅ Account '${this.accountAlias}' created successfully`);
    }
  }

  private async deployContract(
    contractName: string,
    args: string[],
    alias: string
  ): Promise<DeploymentResult> {
    const argsString = args.join(' ');
    const command = `aztec-wallet deploy ${contractName} --from accounts:${this.accountAlias} --args ${argsString} -a ${alias}`;
    
    const output = await this.executeWithRetry(
      () => this.execCommand(command),
      `Deploying ${contractName}`
    );
    
    return this.parseDeploymentOutput(output);
  }

  private async deployToken(tokenConfig: TokenConfig): Promise<DeploymentResult> {
    console.log(`🪙 Deploying ${tokenConfig.name} (${tokenConfig.symbol}) token...`);
    
    const args = [
      `accounts:${this.accountAlias}`, // admin
      tokenConfig.name,
      tokenConfig.symbol,
      tokenConfig.decimals.toString()
    ];
    
    const alias = `token_${tokenConfig.symbol.toLowerCase()}`;
    return await this.deployContract('TokenContractArtifact', args, alias);
  }

  private async deployDripper(): Promise<DeploymentResult> {
    console.log('💧 Deploying Dripper contract...');
    
    return await this.deployContract('DripperArtifact', [], 'dripper');
  }

  private async compilContracts(): Promise<void> {
    console.log('🔨 Compiling contracts...');
    
    await this.executeWithRetry(
      () => this.execCommand('yarn compile'),
      'Contract compilation'
    );
    
    console.log('📦 Generating artifacts...');
    await this.executeWithRetry(
      () => this.execCommand('yarn codegen'),
      'Artifact generation'
    );
  }

  private loadCurrentDeployments(): DeploymentsJson | null {
    const deploymentsPath = path.join(process.cwd(), 'src', 'deployments.json');
    
    if (!fs.existsSync(deploymentsPath)) {
      return null;
    }
    
    try {
      const content = fs.readFileSync(deploymentsPath, 'utf8');
      return JSON.parse(content);
    } catch (error) {
      console.log(`⚠️ Could not parse existing deployments.json: ${error}`);
      return null;
    }
  }

  private saveDeployments(deployments: DeploymentsJson): void {
    const deploymentsPath = path.join(process.cwd(), 'src', 'deployments.json');
    const backupPath = path.join(process.cwd(), 'src', `deployments.backup.${Date.now()}.json`);
    
    // Create backup if file exists
    if (fs.existsSync(deploymentsPath)) {
      fs.copyFileSync(deploymentsPath, backupPath);
      console.log(`📋 Created backup at ${backupPath}`);
    }
    
    fs.writeFileSync(deploymentsPath, JSON.stringify(deployments, null, 4));
    console.log(`💾 Saved deployments to ${deploymentsPath}`);
  }

  async deploy(): Promise<void> {
    console.log('🚀 Starting Aztec deployment process...\n');
    
    const startTime = Date.now();
    
    try {
      // Compile contracts first
      await this.compilContracts();
      
      // Ensure deployment account exists
      await this.ensureAccountExists();
      
      // Deploy Dripper first
      console.log('\n📋 Deploying Dripper contract...');
      const dripperResult = await this.deployDripper();
      console.log(`✅ Dripper deployed at: ${dripperResult.address}`);
      
      // Deploy tokens
      const tokens: TokenConfig[] = [
        { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
        { name: 'USD Coin', symbol: 'USDC', decimals: 6 },
        { name: 'Dai Stablecoin', symbol: 'DAI', decimals: 18 }
      ];
      
      console.log('\n📋 Deploying token contracts...');
      const tokenResults: Array<{ config: TokenConfig; result: DeploymentResult }> = [];
      
      for (const tokenConfig of tokens) {
        const result = await this.deployToken(tokenConfig);
        tokenResults.push({ config: tokenConfig, result });
        console.log(`✅ ${tokenConfig.name} deployed at: ${result.address}`);
      }
      
      // Prepare deployments.json
      const deployments: DeploymentsJson = {
        tokens: tokenResults.map(({ config, result }) => ({
          name: config.name,
          symbol: config.symbol,
          address: result.address,
          decimals: config.decimals,
          minter: 'contracts:dripper',
          upgrade_authority: `accounts:${this.accountAlias}`
        })),
        dripper: {
          address: dripperResult.address
        }
      };
      
      // Save deployments
      this.saveDeployments(deployments);
      
      const endTime = Date.now();
      const duration = Math.round((endTime - startTime) / 1000);
      
      console.log('\n🎉 Deployment completed successfully!');
      console.log(`⏱️  Total time: ${duration} seconds`);
      console.log('\n📊 Deployment Summary:');
      console.log(`├─ Dripper: ${dripperResult.address}`);
      
      tokenResults.forEach(({ config, result }, index) => {
        const isLast = index === tokenResults.length - 1;
        const prefix = isLast ? '└─' : '├─';
        console.log(`${prefix} ${config.name} (${config.symbol}): ${result.address}`);
      });
      
    } catch (error) {
      console.error('\n💥 Deployment failed:', error);
      process.exit(1);
    }
  }
}

// Main execution
async function main() {
  const deployer = new AztecDeployer();
  await deployer.deploy();
}

if (require.main === module) {
  main().catch(error => {
    console.error('Deployment script failed:', error);
    process.exit(1);
  });
}

export { AztecDeployer };