import { NFTContractArtifact, NFTContract } from '../../artifacts/NFT.js';
import {
  AccountWallet,
  CompleteAddress,
  Fr,
  PXE,
  TxStatus,
  getContractInstanceFromDeployParams,
  Contract,
  ContractDeployer,
  AccountWalletWithSecretKey,
  IntentAction,
  AztecAddress,
} from '@aztec/aztec.js';
import { getInitialTestAccountsWallets } from '@aztec/accounts/testing';
import { createPXE, setupSandbox } from './utils.js';

// Deploy NFT contract with a minter
async function deployNFTWithMinter(deployer: AccountWallet) {
  const contract = await Contract.deploy(
    deployer,
    NFTContractArtifact,
    ['TestNFT', 'TNFT', deployer.getAddress()],
    'constructor_with_minter',
  )
    .send()
    .deployed();
  return contract;
}

// Check if an address owns a specific NFT in public state
async function assertOwnsPublicNFT(
  nft: NFTContract,
  tokenId: bigint,
  expectedOwner: AztecAddress,
  caller?: AccountWallet,
) {
  console.log('checking public NFT ownership for token', tokenId.toString());
  const n = caller ? nft.withWallet(caller) : nft;
  const owner = await n.methods.public_owner_of(tokenId).simulate();
  expect(owner.equals(expectedOwner)).toBe(true);
}

// Check if an address owns a specific NFT in private state
async function assertOwnsPrivateNFT(
  nft: NFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  caller?: AccountWallet,
) {
  console.log('checking private NFT ownership for token', tokenId.toString());
  const n = caller ? nft.withWallet(caller) : nft;
  const [nfts, _] = await n.methods.get_private_nfts(owner, 0).simulate();
  const hasNFT = nfts.some((id: bigint) => id === tokenId);
  expect(hasNFT).toBe(true);
}

// Check if an NFT has been nullified (no longer owned) in private state
async function assertPrivateNFTNullified(
  nft: NFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  caller?: AccountWallet,
) {
  console.log('checking NFT nullification for token', tokenId.toString());
  const n = caller ? nft.withWallet(caller) : nft;
  const [nfts, _] = await n.methods.get_private_nfts(owner, 0).simulate();
  const hasNFT = nfts.some((id: bigint) => id === tokenId);
  expect(hasNFT).toBe(false);
}

describe('NFT - Single PXE', () => {
  let pxe: PXE;
  let wallets: AccountWalletWithSecretKey[] = [];
  let accounts: CompleteAddress[] = [];

  let alice: AccountWallet;
  let bob: AccountWallet;
  let carl: AccountWallet;

  let nft: NFTContract;

  beforeAll(async () => {
    pxe = await setupSandbox();

    wallets = await getInitialTestAccountsWallets(pxe);
    accounts = wallets.map((w) => w.getCompleteAddress());

    alice = wallets[0];
    bob = wallets[1];
    carl = wallets[2];

    console.log({
      alice: alice.getAddress(),
      bob: bob.getAddress(),
    });
  });

  beforeEach(async () => {
    nft = (await deployNFTWithMinter(alice)) as NFTContract;
  });

  it('deploys the contract with minter', async () => {
    const salt = Fr.random();
    const [deployerWallet] = wallets; // using first account as deployer

    const deploymentData = await getContractInstanceFromDeployParams(NFTContractArtifact, {
      constructorArtifact: 'constructor_with_minter',
      constructorArgs: ['TestNFT', 'TNFT', deployerWallet.getAddress()],
      salt,
      deployer: deployerWallet.getAddress(),
    });
    
    const deployer = new ContractDeployer(
      NFTContractArtifact,
      deployerWallet,
      undefined,
      'constructor_with_minter',
    );
    
    const tx = deployer
      .deploy('TestNFT', 'TNFT', deployerWallet.getAddress())
      .send({ contractAddressSalt: salt });
    
    const receipt = await tx.getReceipt();

    expect(receipt).toEqual(
      expect.objectContaining({
        status: TxStatus.PENDING,
        error: '',
      }),
    );

    const receiptAfterMined = await tx.wait({ wallet: deployerWallet });

    const contractMetadata = await pxe.getContractMetadata(deploymentData.address);
    expect(contractMetadata).toBeDefined();
    expect(contractMetadata.isContractPubliclyDeployed).toBeTruthy();
    expect(receiptAfterMined).toEqual(
      expect.objectContaining({
        status: TxStatus.SUCCESS,
      }),
    );

    expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
  }, 300_000);

  it('mints NFT to public', async () => {
    const tokenId = 1n;
    await nft.withWallet(alice).methods.mint_public(bob.getAddress(), tokenId).send().wait();
    
    // Verify bob owns the NFT publicly
    await assertOwnsPublicNFT(nft, tokenId, bob.getAddress());
  }, 300_000);

  it('mints NFT to private', async () => {
    const tokenId = 1n;
    await nft.withWallet(alice).methods.mint_private(bob.getAddress(), tokenId).send().wait();
    
    // Verify bob owns the NFT privately
    await assertOwnsPrivateNFT(nft, tokenId, bob.getAddress());
  }, 300_000);

  it('fails to mint when caller is not minter', async () => {
    const tokenId = 1n;
    
    // Bob attempts to mint when he's not the minter
    await expect(
      nft.withWallet(bob).methods.mint_public(bob.getAddress(), tokenId).send().wait()
    ).rejects.toThrow(/caller is not minter/);

    await expect(
      nft.withWallet(bob).methods.mint_private(bob.getAddress(), tokenId).send().wait()
    ).rejects.toThrow(/caller is not minter/);
  }, 300_000);

  it('fails to mint same token ID twice', async () => {
    const tokenId = 1n;
    
    // First mint succeeds
    await nft.withWallet(alice).methods.mint_public(bob.getAddress(), tokenId).send().wait();
    
    // Second mint with same token ID should fail
    await expect(
      nft.withWallet(alice).methods.mint_public(carl.getAddress(), tokenId).send().wait()
    ).rejects.toThrow(/token already exists/);
  }, 300_000);

  it('fails to mint with token ID zero', async () => {
    const tokenId = 0n;
    
    await expect(
      nft.withWallet(alice).methods.mint_public(bob.getAddress(), tokenId).send().wait()
    ).rejects.toThrow(/zero token ID not supported/);

    await expect(
      nft.withWallet(alice).methods.mint_private(bob.getAddress(), tokenId).send().wait()
    ).rejects.toThrow(/zero token ID not supported/);
  }, 300_000);

  it('can mint multiple NFTs to same owner', async () => {
    const tokenId1 = 1n;
    const tokenId2 = 2n;
    
    // Mint two NFTs to bob
    await nft.withWallet(alice).methods.mint_private(bob.getAddress(), tokenId1).send().wait();
    await nft.withWallet(alice).methods.mint_private(bob.getAddress(), tokenId2).send().wait();
    
    // Verify bob owns both NFTs
    await assertOwnsPrivateNFT(nft, tokenId1, bob.getAddress());
    await assertOwnsPrivateNFT(nft, tokenId2, bob.getAddress());
  }, 300_000);
});
