import {
  type AccountWallet,
  type ContractFunctionInteraction,
  type PXE,
  createPXEClient,
  AztecAddress,
  AuthWitness,
} from '@aztec/aztec.js';
import { getInitialTestAccountsWallets } from '@aztec/accounts/testing';
import { parseUnits } from 'viem';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../src/artifacts/Token.js';
import { deployVaultAndAssetWithMinter, setPrivateAuthWit, setPublicAuthWit } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface TokenBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  vaultContract: TokenContract;
  assetContract: TokenContract;
  authWitnesses: AuthWitness[];
}

// --- Helper Functions ---

function amt(x: bigint | number | string) {
  // Using 18 decimals as standard for Token examples
  return parseUnits(x.toString(), 18);
}

// Use export default class extending Benchmark
export default class TokenContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<TokenBenchmarkContext> {
    const { BASE_PXE_URL = 'http://localhost' } = process.env;
    const pxe = createPXEClient(`${BASE_PXE_URL}:8080`);
    const accounts = await getInitialTestAccountsWallets(pxe);
    const deployer = accounts[0]!;
    const [deployedBaseContract, deployedAssetContract] = await deployVaultAndAssetWithMinter(deployer);
    const vaultContract = await TokenContract.at(deployedBaseContract.address, deployer);
    const assetContract = await TokenContract.at(deployedAssetContract.address, deployer);
    const assetMethods = assetContract.withWallet(deployer).methods;

    // Mint initial asset supply to the deployer
    await assetContract.withWallet(deployer).methods.mint_to_public(deployer.getAddress(), amt(100)).send().wait();
    for (let i = 0; i < 6; i++) {
      // 1 Note per benchmark test so that a single full Note is used in each.
      await assetContract
        .withWallet(deployer)
        .methods.mint_to_private(deployer.getAddress(), deployer.getAddress(), amt(1))
        .send()
        .wait();
    }

    // Initialize shares total supply by depositing 1 asset and sending 1 share to the zero address
    let action = assetMethods.transfer_public_to_public(deployer.getAddress(), vaultContract.address, amt(1), 0);
    await setPublicAuthWit(vaultContract.address, action, deployer);
    await vaultContract
      .withWallet(deployer)
      .methods.deposit_public_to_public(deployer.getAddress(), AztecAddress.ZERO, amt(1), 0)
      .send()
      .wait();

    /* ======================= PUBLIC AUTHWITS ========================== */

    // Set public authwitness for deposit_public_to_public
    action = assetMethods.transfer_public_to_public(deployer.getAddress(), vaultContract.address, amt(1), 1);
    await setPublicAuthWit(vaultContract.address, action, deployer);

    // Set public authwitness for deposit_public_to_private
    action = assetMethods.transfer_public_to_public(deployer.getAddress(), vaultContract.address, amt(1), 2);
    await setPublicAuthWit(vaultContract.address, action, deployer);

    // Set public authwitness for deposit_public_to_private_exact
    action = assetMethods.transfer_public_to_public(deployer.getAddress(), vaultContract.address, amt(1), 3);
    await setPublicAuthWit(vaultContract.address, action, deployer);

    // Set public authwitness for issue_public_to_public
    action = assetMethods.transfer_public_to_public(deployer.getAddress(), vaultContract.address, amt(1), 4);
    await setPublicAuthWit(vaultContract.address, action, deployer);

    // Set public authwitness for issue_public_to_private
    action = assetMethods.transfer_public_to_public(deployer.getAddress(), vaultContract.address, amt(1), 5);
    await setPublicAuthWit(vaultContract.address, action, deployer);

    /* ======================= PRIVATE AUTHWITS ========================= */

    // Prepare private authwitness for the `transfer_private_to_public` method on the Asset contract to be used by the
    // Tokenized Vault's following methods:
    // 1. deposit_private_to_private
    // 2. deposit_public_to_private
    // 3. deposit_public_to_private_exact
    // 4. issue_public_to_public
    // 5. issue_public_to_private
    const authWitnesses = [];
    for (let i = 0; i < 5; i++) {
      const nonce = 100 + i;
      action = assetMethods.transfer_private_to_public(deployer.getAddress(), vaultContract.address, amt(1), nonce);
      const authWitness = await setPrivateAuthWit(vaultContract.address, action, deployer);
      authWitnesses.push(authWitness);
    }

    return { pxe, deployer, accounts, vaultContract, assetContract, authWitnesses };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: TokenBenchmarkContext): ContractFunctionInteraction[] {
    const { vaultContract, deployer, accounts, authWitnesses } = context;
    const alice = deployer;
    const bob = accounts[1];
    const aliceAddress = alice.getAddress();
    const bobAddress = bob.getAddress();

    const methods: ContractFunctionInteraction[] = [
      // Deposit methods
      vaultContract.withWallet(alice).methods.deposit_public_to_public(aliceAddress, bobAddress, amt(1), 1),
      vaultContract.withWallet(alice).methods.deposit_public_to_private(aliceAddress, bobAddress, amt(1), amt(1), 2),
      vaultContract
        .withWallet(alice)
        .methods.deposit_private_to_private(aliceAddress, bobAddress, amt(1), amt(1), 100)
        .with({ authWitnesses: [authWitnesses[0]] }),
      vaultContract
        .withWallet(alice)
        .methods.deposit_private_to_public(aliceAddress, bobAddress, amt(1), 101)
        .with({ authWitnesses: [authWitnesses[1]] }),
      vaultContract
        .withWallet(alice)
        .methods.deposit_public_to_private_exact(aliceAddress, bobAddress, amt(1), amt(1), 3),
      vaultContract
        .withWallet(alice)
        .methods.deposit_private_to_private_exact(aliceAddress, bobAddress, amt(1), amt(1), 102)
        .with({ authWitnesses: [authWitnesses[2]] }),

      // Issue methods
      vaultContract.withWallet(alice).methods.issue_public_to_public(aliceAddress, bobAddress, amt(1), amt(1), 4),
      vaultContract.withWallet(alice).methods.issue_public_to_private(aliceAddress, bobAddress, amt(1), amt(1), 5),
      vaultContract
        .withWallet(alice)
        .methods.issue_private_to_public_exact(aliceAddress, bobAddress, amt(1), amt(1), 103)
        .with({ authWitnesses: [authWitnesses[3]] }),
      vaultContract
        .withWallet(alice)
        .methods.issue_private_to_private_exact(aliceAddress, bobAddress, amt(1), amt(1), 104)
        .with({ authWitnesses: [authWitnesses[4]] }),

      // Withdraw methods
      vaultContract.withWallet(bob).methods.withdraw_public_to_public(bobAddress, aliceAddress, amt(1), 0),
      vaultContract.withWallet(bob).methods.withdraw_public_to_private(bobAddress, aliceAddress, amt(1), 0),
      vaultContract.withWallet(bob).methods.withdraw_private_to_private(bobAddress, aliceAddress, amt(1), amt(1), 0),
      vaultContract
        .withWallet(bob)
        .methods.withdraw_private_to_public_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),
      vaultContract
        .withWallet(bob)
        .methods.withdraw_private_to_private_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),

      // Redeem methods
      vaultContract.withWallet(bob).methods.redeem_public_to_public(bobAddress, aliceAddress, amt(1), 0),
      vaultContract.withWallet(bob).methods.redeem_private_to_public(bobAddress, aliceAddress, amt(1), 0),
      vaultContract
        .withWallet(bob)
        .methods.redeem_private_to_private_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),
      vaultContract.withWallet(bob).methods.redeem_public_to_private_exact(bobAddress, aliceAddress, amt(1), amt(1), 0),
    ];

    return methods.filter(Boolean);
  }
}
