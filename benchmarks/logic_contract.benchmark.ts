import {
  Fr,
  type AccountWallet,
  type ContractFunctionInteraction,
  type PXE,
  getContractClassFromArtifact,
  GrumpkinScalar,
} from '@aztec/aztec.js';
import { deriveKeys, PublicKeys } from '@aztec/stdlib/keys';
import { parseUnits } from 'viem';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';

// Import the new Benchmark base class and context
import { Benchmark, BenchmarkContext } from '@defi-wonderland/aztec-benchmark';

import { TokenContract } from '../artifacts/Token.js';
import { EscrowContract, EscrowContractArtifact } from '../artifacts/Escrow.js';
import { NFTContract } from '../artifacts/NFT.js';
import { TestLogicContract } from '../artifacts/TestLogic.js';
import {
  deployLogicWithPublicKeys,
  deployEscrowWithPublicKeysAndSalt,
  grumpkinScalarToFr,
} from '../src/ts/test/utils.js';
import { deployTokenWithMinter, deployNFTWithMinter, setupPXE } from '../src/ts/test/utils.js';

// Extend the BenchmarkContext from the new package
interface LogicBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  tokenContract: TokenContract;
  nftContract: NFTContract;
  logicContract: TestLogicContract;
  escrowContract: EscrowContract;
  tokenAmount: number;
  tokenId: number;
  escrowKeys: {
    masterNullifierSecretKey: GrumpkinScalar;
    masterIncomingViewingSecretKey: GrumpkinScalar;
    masterOutgoingViewingSecretKey: GrumpkinScalar;
    masterTaggingSecretKey: GrumpkinScalar;
    publicKeys: PublicKeys;
  };
}

// Use export default class extending Benchmark
export default class LogicContractBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the TokenContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<LogicBenchmarkContext> {
    const { pxe } = await setupPXE();
    const managers = await getInitialTestAccountsManagers(pxe);
    const accounts = await Promise.all(managers.map((acc) => acc.register()));
    const [deployer] = accounts;

    const logicSk = Fr.random();
    const logicKeys = await deriveKeys(logicSk);
    const escrowClassId = (await getContractClassFromArtifact(EscrowContractArtifact)).id;

    // Deploy logic contract
    const logicContract = (await deployLogicWithPublicKeys(
      logicKeys.publicKeys,
      deployer,
      escrowClassId,
    )) as TestLogicContract;
    const partialAddressLogic = await logicContract.partialAddress;
    await pxe.registerAccount(logicSk, partialAddressLogic);

    // Setup escrow
    const escrowSk = Fr.random();
    const escrowKeys = await deriveKeys(escrowSk);
    const escrowSalt = new Fr(logicContract.instance.address.toBigInt());
    const escrowContract = (await deployEscrowWithPublicKeysAndSalt(
      escrowKeys.publicKeys,
      deployer,
      escrowSalt,
    )) as EscrowContract;
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

    return {
      pxe,
      deployer,
      accounts,
      tokenContract,
      nftContract,
      logicContract,
      escrowContract,
      tokenAmount,
      tokenId,
      escrowKeys,
    };
  }

  /**
   * Returns the list of TokenContract methods to be benchmarked.
   */
  getMethods(context: LogicBenchmarkContext): ContractFunctionInteraction[] {
    const {
      accounts,
      tokenContract,
      nftContract,
      escrowContract,
      tokenAmount,
      tokenId,
      deployer,
      logicContract,
      escrowKeys,
    } = context;
    const recipient = accounts[2].getAddress();
    const escrowKeysFr = [
      grumpkinScalarToFr(escrowKeys.masterNullifierSecretKey),
      grumpkinScalarToFr(escrowKeys.masterIncomingViewingSecretKey),
      grumpkinScalarToFr(escrowKeys.masterOutgoingViewingSecretKey),
      grumpkinScalarToFr(escrowKeys.masterTaggingSecretKey),
    ];

    const methods: ContractFunctionInteraction[] = [
      // Derive public keys from secret keys
      logicContract
        .withWallet(deployer)
        .methods.secret_keys_to_public_keys(escrowKeysFr[0], escrowKeysFr[1], escrowKeysFr[2], escrowKeysFr[3]),
      // Check escrow correctness
      logicContract.withWallet(deployer).methods.check_escrow(escrowContract.address, escrowKeysFr),
      // Share escrow
      logicContract.withWallet(deployer).methods.share_escrow(escrowContract.address, escrowKeysFr, recipient),
      // Full token withdrawal
      logicContract
        .withWallet(deployer)
        .methods.withdraw(escrowContract.address, recipient, tokenContract.address, tokenAmount),
      // NFT withdrawal
      logicContract
        .withWallet(deployer)
        .methods.withdraw_nft(escrowContract.address, recipient, nftContract.address, tokenId),
    ];

    return methods.filter(Boolean);
  }
}
