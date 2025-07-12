# Aztec Testnet Deployment Guide

This repository contains automated deployment infrastructure for Aztec smart contracts with retry functionality and GitHub integration.

## 🏗️ What Gets Deployed

The deployment system automatically deploys the following contracts to Aztec testnet:

1. **Dripper Contract** - A token faucet for minting test tokens
2. **Token Contracts** - Three ERC20-like tokens:
   - ETH (Ethereum) - 18 decimals
   - USDC (USD Coin) - 6 decimals  
   - DAI (Dai Stablecoin) - 18 decimals

## 🚀 Automated Deployment

### GitHub Actions Workflow

The deployment workflow (`deploy.yml`) automatically triggers when:
- Code is merged to the `main` branch
- Manual workflow dispatch is triggered

#### Features:
- ✅ **Retry Logic**: Built-in retry mechanism with exponential backoff
- ✅ **Testnet Stability**: Handles testnet instability with robust error handling
- ✅ **Automatic PR Creation**: Creates PRs with updated deployment addresses
- ✅ **Address Validation**: Validates deployed contract addresses
- ✅ **Deployment Summaries**: Provides detailed deployment reports

### Workflow Steps:
1. **Setup Environment**: Install Node.js, Yarn, and Aztec CLI tools
2. **Compile Contracts**: Build and generate contract artifacts
3. **Deploy Contracts**: Deploy with retry logic to handle testnet issues
4. **Validate Deployment**: Verify contract addresses and accessibility
5. **Create Pull Request**: Auto-generate PR with updated `deployments.json`

## 🛠️ Manual Deployment

### Prerequisites

1. **Install Aztec CLI**:
   ```bash
   bash -i <(curl -s https://install.aztec.network)
   ```

2. **Install Dependencies**:
   ```bash
   yarn install
   ```

3. **Compile Contracts**:
   ```bash
   yarn clean && yarn compile && yarn codegen
   ```

### Run Deployment

```bash
# Deploy to testnet with retry logic
yarn deploy

# Alternative using npx
npx tsx scripts/deploy.ts
```

### Environment Variables

You can customize the deployment behavior:

```bash
export AZTEC_RPC_URL="https://aztec-testnet.aztec.network:8080"  # Testnet URL
export AZTEC_ACCOUNT_ALIAS="my-deployer"                        # Account alias
export MAX_RETRIES=5                                            # Max retry attempts
export RETRY_DELAY=5000                                         # Base retry delay (ms)
```

## 📁 Generated Files

### `src/deployments.json`

The deployment script updates this file with new contract addresses:

```json
{
    "tokens": [
        {
            "name": "Ethereum",
            "symbol": "ETH",
            "address": "0x...",
            "decimals": 18,
            "minter": "contracts:dripper",
            "upgrade_authority": "0x..."
        }
    ],
    "dripper": {
        "address": "0x..."
    }
}
```

### Backup Files

The script automatically creates backup files:
- `src/deployments.backup.{timestamp}.json`

## 🔄 Retry Mechanism

The deployment script includes robust retry logic to handle Aztec testnet instability:

### Features:
- **Exponential Backoff**: Increasing delays between retries
- **Max Retry Limit**: Configurable maximum retry attempts (default: 5)
- **Operation-Specific Retries**: Each deployment step can retry independently
- **Detailed Logging**: Clear feedback on retry attempts and failures

### Retry Flow:
```
Attempt 1 → Failed → Wait 5s
Attempt 2 → Failed → Wait 10s  
Attempt 3 → Failed → Wait 15s
Attempt 4 → Failed → Wait 20s
Attempt 5 → Success ✅
```

## 🌐 Aztec Testnet Information

### Network Details:
- **RPC URL**: `https://aztec-testnet.aztec.network:8080`
- **Chain ID**: Aztec Testnet
- **Explorer**: [Aztec Testnet Explorer](https://aztec-testnet-explorer.aztec.network/)
- **Faucet**: Available through testnet interface

### Account Setup:
The script automatically:
1. Creates a deployment account with testnet fee juice
2. Uses `test0` account for fee payments
3. Manages account aliases for easy reference

## 🐛 Troubleshooting

### Common Issues:

#### 1. **"Failed to connect to testnet"**
```bash
# Check testnet status
curl -s https://aztec-testnet.aztec.network:8080/status

# Verify Aztec CLI installation
aztec --version
aztec-wallet --help
```

#### 2. **"Account creation failed"**
```bash
# Import test accounts first
aztec-wallet import-test-accounts

# Check available accounts
aztec-wallet list-accounts
```

#### 3. **"Contract deployment timeout"**
- The script includes automatic retries
- Testnet may be experiencing high load
- Check [Aztec Discord](https://discord.gg/aztec) for testnet status

#### 4. **"Invalid contract address format"**
- Addresses should be 64-character hex strings with `0x` prefix
- Indicates parsing error from deployment output
- Check deployment logs for issues

### Debug Mode:

Enable verbose logging:
```bash
DEBUG=aztec:* yarn deploy
```

## 🔒 Security Considerations

### GitHub Actions:
- Uses `GITHUB_TOKEN` for PR creation
- No sensitive keys stored in repository
- Testnet-only deployments (no mainnet risk)

### Local Development:
- Never commit private keys or mnemonics
- Use testnet-only accounts
- Keep deployment accounts separate from personal accounts

## 📊 Monitoring

### GitHub Actions Dashboard:
- View deployment status in the Actions tab
- Check workflow run details for deployment addresses
- Monitor PR creation and merge status

### Deployment Validation:
- Automatic address format validation
- Contract accessibility verification
- Cross-reference with Aztec explorer

## 🤝 Contributing

### Adding New Contracts:

1. **Add Contract**: Place contract in `src/` directory
2. **Update Deployment Script**: Add to `scripts/deploy.ts`
3. **Update Schema**: Modify `DeploymentsJson` interface
4. **Test Locally**: Run `yarn deploy` to verify
5. **Update Documentation**: Add to this README

### Modifying Retry Logic:

The retry mechanism can be customized in `AztecDeployer.executeWithRetry()`:
- Adjust `maxRetries` for more/fewer attempts
- Modify `retryDelay` calculation for different backoff strategies
- Add operation-specific retry logic

## 📚 Additional Resources

- [Aztec Documentation](https://docs.aztec.network/)
- [Aztec CLI Reference](https://docs.aztec.network/dev_docs/cli)
- [Aztec Discord Community](https://discord.gg/aztec)
- [Aztec GitHub Repository](https://github.com/AztecProtocol/aztec-packages)

## 🆘 Support

If you encounter issues:

1. **Check this documentation** for common solutions
2. **Review GitHub Actions logs** for detailed error information
3. **Join Aztec Discord** for community support
4. **Open an issue** in this repository for persistent problems

---

*Last updated: 2025-01-27*