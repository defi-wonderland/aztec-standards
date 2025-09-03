import { Fr, type AccountWallet, type ContractFunctionInteraction, type PXE } from '@aztec/aztec.js';
import { deriveKeys } from '@aztec/stdlib/keys';
import { parseUnits } from 'viem';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../artifacts/Token.js';
import { EscrowContract } from '../artifacts/Escrow.js';
import { NFTContract } from '../artifacts/NFT.js';
import { deployEscrow, deployTokenWithMinter, deployNFTWithMinter, setupPXE } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface TokenBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  tokenContract: TokenContract;
  nftContract: NFTContract;
  escrowContract: EscrowContract;
  tokenAmount: number;
  tokenId: number;
}

// Use export default class extending Benchmark
export default class TokenContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<TokenBenchmarkContext> {
    const { pxe } = await setupPXE();
    const managers = await getInitialTestAccountsManagers(pxe);
    const accounts = await Promise.all(managers.map((acc) => acc.register()));
    const [deployer] = accounts;
    const logicMock = accounts[1];

    // Setup escrow
    const escrowSk = Fr.random();
    const escrowKeys = await deriveKeys(escrowSk);
    const escrowSalt = new Fr(logicMock.getAddress().toBigInt());
    const escrowContract = (await deployEscrow(escrowKeys.publicKeys, deployer, escrowSalt)) as EscrowContract;
    const partialAddressEscrow = await escrowContract.partialAddress;
    await pxe.registerAccount(escrowSk, partialAddressEscrow);

    // Deploy token and NFT contracts
    const deployedTokenContract = await deployTokenWithMinter(deployer);
    const tokenContract = await TokenContract.at(deployedTokenContract.address, deployer);
    const deployedNFTContract = await deployNFTWithMinter(deployer);
    const nftContract = await NFTContract.at(deployedNFTContract.address, deployer);

    // Mint tokens and NFT to the escrow contract
    const tokenAmount = 100;
    await tokenContract
      .withWallet(deployer)
      .methods.mint_to_private(deployer.getAddress(), escrowContract.address, tokenAmount)
      .send()
      .wait();
    const tokenId = 1;
    await nftContract.withWallet(deployer).methods.mint_to_private(escrowContract.address, tokenId).send().wait();

    return { pxe, deployer, accounts, tokenContract, nftContract, escrowContract, tokenAmount, tokenId };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: TokenBenchmarkContext): ContractFunctionInteraction[] {
    const { accounts, tokenContract, nftContract, escrowContract, tokenAmount, tokenId } = context;
    const logicMock = accounts[1];
    const recipient = accounts[2].getAddress();

    const methods: ContractFunctionInteraction[] = [
      // TODO: it is not possible to benchmark the same method multiple times with different setups.
      // Partial token withdrawal (with change)
      // escrowContract.withWallet(logicMock).methods.withdraw(tokenContract.address, amt(50), recipient),
      // Full token withdrawal
      escrowContract.withWallet(logicMock).methods.withdraw(tokenContract.address, tokenAmount, recipient),
      // NFT withdrawal
      escrowContract.withWallet(logicMock).methods.withdraw_nft(nftContract.address, tokenId, recipient),
    ];

    return methods.filter(Boolean);
  }
}
