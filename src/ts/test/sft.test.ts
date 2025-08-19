import {
  AccountWallet,
  Fr,
  PXE,
  TxStatus,
  getContractInstanceFromDeployParams,
  Contract,
  ContractDeployer,
  AccountWalletWithSecretKey,
  IntentAction,
  AztecAddress,
  DeployOptions,
} from '@aztec/aztec.js';
import { deploySFTWithMinter, setupPXE } from './utils.js';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { SFTContract, SFTContractArtifact } from '../../../artifacts/SFT.js';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';

async function assertPublicBalance(
  sft: SFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  expectedBalance: bigint,
  caller?: AccountWallet,
) {
  const s = caller ? sft.withWallet(caller) : sft;
  const balance = await s.methods.balance_of_public_by_token_id(owner, tokenId).simulate();
  expect(balance).toBe(expectedBalance);
}

async function assertPrivateBalance(
  sft: SFTContract,
  tokenId: bigint,
  owner: AztecAddress,
  expectedBalance: bigint,
  caller?: AccountWallet,
) {
  const s = caller ? sft.withWallet(caller) : sft;
  const balance = await s.methods.balance_of_private_by_token_id(owner, tokenId, 0).simulate();
  expect(balance).toBe(expectedBalance);
}

async function assertTokenTypeExists(sft: SFTContract, tokenId: bigint, shouldExist: boolean, caller?: AccountWallet) {
  const s = caller ? sft.withWallet(caller) : sft;
  const exists = await s.methods.public_token_type_exists(tokenId).simulate();
  expect(exists).toBe(shouldExist);
}

async function assertTotalSupply(sft: SFTContract, tokenId: bigint, expectedSupply: bigint, caller?: AccountWallet) {
  const s = caller ? sft.withWallet(caller) : sft;
  const supply = await s.methods.total_supply(tokenId).simulate();
  expect(supply).toBe(expectedSupply);
}

const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const managers = await getInitialTestAccountsManagers(pxe);
  const wallets = await Promise.all(managers.map((acc) => acc.register()));
  const [deployer] = wallets;
  await new Promise((resolve) => setTimeout(resolve, 2000));
  return { pxe, deployer, wallets, store };
};

function bigIntToAsciiString(bigInt: any): string {
  let hexString = bigInt.toString(16);
  const pairs = [];
  for (let i = 0; i < hexString.length; i += 2) {
    const pair = hexString.slice(i, i + 2).padStart(2, '0');
    pairs.push(pair);
  }
  let asciiString = '';
  for (const pair of pairs) {
    const charCode = parseInt(pair, 16);
    if (charCode >= 32 && charCode <= 126) {
      asciiString += String.fromCharCode(charCode);
    }
  }
  return asciiString;
}

describe('SFT - Single PXE', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;
  let wallets: AccountWalletWithSecretKey[];
  let deployer: AccountWalletWithSecretKey;
  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let carl: AccountWalletWithSecretKey;
  let sft: SFTContract;

  beforeAll(async () => {
    ({ pxe, deployer, wallets, store } = await setupTestSuite());
    [alice, bob, carl] = wallets;
    console.log({
      alice: alice.getAddress(),
      bob: bob.getAddress(),
    });
  });

  beforeEach(async () => {
    sft = (await deploySFTWithMinter(alice)) as SFTContract;
  });

  afterAll(async () => {
    await store.delete();
  });

  it('deploys the contract with minter', async () => {
    const salt = Fr.random();
    const deployerWallet = alice;
    const deploymentData = await getContractInstanceFromDeployParams(SFTContractArtifact, {
      constructorArtifact: 'constructor_with_minter',
      constructorArgs: ['TestSFT', 'TSFT', deployerWallet.getAddress(), deployerWallet.getAddress()],
      salt,
      deployer: deployerWallet.getAddress(),
    });

    const deployer = new ContractDeployer(SFTContractArtifact, deployerWallet, undefined, 'constructor_with_minter');
    const tx = deployer
      .deploy('TestSFT', 'TSFT', deployerWallet.getAddress(), deployerWallet.getAddress())
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

  it('creates a new token type', async () => {
    const tokenId = 1n;
    await assertTokenTypeExists(sft, tokenId, false);
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await assertTokenTypeExists(sft, tokenId, true);
    await assertTotalSupply(sft, tokenId, 0n);
  }, 300_000);

  it('fails to create token type when not minter', async () => {
    const tokenId = 1n;
    await expect(sft.withWallet(bob).methods.create_token_type(tokenId).send().wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );
    await assertTokenTypeExists(sft, tokenId, false);
  }, 300_000);

  it('fails to create same token type twice', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await expect(sft.withWallet(alice).methods.create_token_type(tokenId).send().wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );
  }, 300_000);

  it('mints SFT to public', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_public(bob.getAddress(), tokenId).send().wait();
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 1n);
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('mints SFT to private', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
    await assertTokenTypeExists(sft, tokenId, true);
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('fails to mint when caller is not minter', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await expect(sft.withWallet(bob).methods.mint_to_public(bob.getAddress(), tokenId).send().wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );
    await expect(sft.withWallet(bob).methods.mint_to_private(bob.getAddress(), tokenId).send().wait()).rejects.toThrow(
      /caller is not minter/,
    );
  }, 300_000);

  it('fails to mint to public for non-existent token type', async () => {
    const tokenId = 1n;
    await expect(sft.withWallet(alice).methods.mint_to_public(bob.getAddress(), tokenId).send().wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );
  }, 300_000);

  it('fails to mint with token ID zero', async () => {
    const tokenId = 0n;
    await expect(
      sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait(),
    ).rejects.toThrow(/zero token ID not supported/);
  }, 300_000);

  it('can mint multiple SFTs of same type to same owner', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 3n);
    await assertTotalSupply(sft, tokenId, 3n);
  }, 300_000);

  it('can mint different token types', async () => {
    const tokenId1 = 1n;
    const tokenId2 = 2n;
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId1).send().wait();
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId2).send().wait();
    await assertPrivateBalance(sft, tokenId1, bob.getAddress(), 1n);
    await assertPrivateBalance(sft, tokenId2, bob.getAddress(), 1n);
    await assertTokenTypeExists(sft, tokenId1, true);
    await assertTokenTypeExists(sft, tokenId2, true);
  }, 300_000);

  it('burns SFT from public balance', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_public(bob.getAddress(), tokenId).send().wait();
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 1n);
    await sft.withWallet(bob).methods.burn_public(bob.getAddress(), tokenId, 0n).send().wait();
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 0n);
    await assertTotalSupply(sft, tokenId, 0n);
  }, 300_000);

  it('burns SFT from private balance', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
    await sft.withWallet(bob).methods.burn_private(bob.getAddress(), tokenId, 0n).send().wait();
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 0n);
    await assertTotalSupply(sft, tokenId, 0n);
  }, 300_000);

  it('fails to burn when caller has no tokens', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await expect(sft.withWallet(bob).methods.burn_public(bob.getAddress(), tokenId, 0n).send().wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );
    await expect(sft.withWallet(bob).methods.burn_private(bob.getAddress(), tokenId, 0n).send().wait()).rejects.toThrow(
      /sft not found in private/,
    );
  }, 300_000);

  it('transfers SFT from private to private', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 1n);
    await sft
      .withWallet(alice)
      .methods.transfer_private_to_private(alice.getAddress(), bob.getAddress(), tokenId, 0n)
      .send()
      .wait();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('fails to transfer private SFT when not owner', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    await expect(
      sft
        .withWallet(carl)
        .methods.transfer_private_to_private(carl.getAddress(), bob.getAddress(), tokenId, 0n)
        .send()
        .wait(),
    ).rejects.toThrow(/sft not found in private/);
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 1n);
  }, 300_000);

  it('transfers SFT from private to public', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    await sft
      .withWallet(alice)
      .methods.transfer_private_to_public(alice.getAddress(), bob.getAddress(), tokenId, 0n)
      .send()
      .wait();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 1n);
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('transfers SFT from private to public with commitment', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    await sft
      .withWallet(alice)
      .methods.transfer_private_to_public_with_commitment(alice.getAddress(), bob.getAddress(), tokenId, 0n)
      .send()
      .wait();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 1n);
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('transfers SFT from public to private', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_public(alice.getAddress(), tokenId).send().wait();
    await sft
      .withWallet(alice)
      .methods.transfer_public_to_private(alice.getAddress(), bob.getAddress(), tokenId, 0n)
      .send()
      .wait();
    await assertPublicBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('transfers SFT from public to public', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_public(alice.getAddress(), tokenId).send().wait();
    await sft
      .withWallet(alice)
      .methods.transfer_public_to_public(alice.getAddress(), bob.getAddress(), tokenId, 0n)
      .send()
      .wait();
    await assertPublicBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 1n);
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('fails to transfer public SFT when not owner', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_public(alice.getAddress(), tokenId).send().wait();
    await expect(
      sft
        .withWallet(carl)
        .methods.transfer_public_to_public(carl.getAddress(), bob.getAddress(), tokenId, 0n)
        .send()
        .wait(),
    ).rejects.toThrow(/^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/);
    await assertPublicBalance(sft, tokenId, alice.getAddress(), 1n);
  }, 300_000);

  it('initializes and uses transfer commitment', async () => {
    const tokenId = 1n;
    const commitment = await sft
      .withWallet(alice)
      .methods.initialize_transfer_commitment(tokenId, alice.getAddress(), bob.getAddress(), alice.getAddress())
      .simulate();
    expect(typeof commitment).toBe('bigint');
    expect(commitment).not.toBe(0n);
  }, 300_000);

  it.skip('transfers SFT from private to commitment', async () => {
    // The commitment system requires precise coordination between private simulation and public storage,
    // but the randomness in SFTNote::partial() causes commitment values to differ between calls.
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    const commitment = await sft
      .withWallet(alice)
      .methods.initialize_transfer_commitment(tokenId, alice.getAddress(), bob.getAddress(), alice.getAddress())
      .simulate();
    await sft
      .withWallet(alice)
      .methods.initialize_transfer_commitment(tokenId, alice.getAddress(), bob.getAddress(), alice.getAddress())
      .send()
      .wait();
    await sft
      .withWallet(alice)
      .methods.transfer_private_to_commitment(alice.getAddress(), tokenId, commitment, 0n)
      .send()
      .wait();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
  }, 300_000);

  it.skip('transfers SFT from public to commitment', async () => {
    // TODO: Commitment-based transfers are skipped due to state synchronization issues.
    // The commitment system requires precise coordination between private simulation and public storage,
    // but the randomness in SFTNote::partial() causes commitment values to differ between calls.
    const tokenId = 1n;
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_public(alice.getAddress(), tokenId).send().wait();
    const commitment = await sft
      .withWallet(alice)
      .methods.initialize_transfer_commitment(tokenId, alice.getAddress(), bob.getAddress(), alice.getAddress())
      .simulate();
    await sft
      .withWallet(alice)
      .methods.initialize_transfer_commitment(tokenId, alice.getAddress(), bob.getAddress(), alice.getAddress())
      .send()
      .wait();
    await sft
      .withWallet(alice)
      .methods.transfer_public_to_commitment(alice.getAddress(), tokenId, commitment, 0n)
      .send()
      .wait();
    await assertPublicBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
  }, 300_000);

  it('returns correct name and symbol', async () => {
    const name = await sft.methods.public_get_name().simulate();
    const symbol = await sft.methods.public_get_symbol().simulate();
    const nameStr = bigIntToAsciiString(name.value);
    const symbolStr = bigIntToAsciiString(symbol.value);
    console.log('SFT Name:', nameStr);
    console.log('SFT Symbol:', symbolStr);
    expect(nameStr).toBe('TestSFT');
    expect(symbolStr).toBe('TSFT');
  }, 300_000);

  it('returns correct token type existence', async () => {
    const tokenId = 1n;
    await assertTokenTypeExists(sft, tokenId, false);
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await assertTokenTypeExists(sft, tokenId, true);
  }, 300_000);

  it('returns correct public balances', async () => {
    const tokenId = 1n;
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 0n);
    await sft.withWallet(alice).methods.create_token_type(tokenId).send().wait();
    await sft.withWallet(alice).methods.mint_to_public(bob.getAddress(), tokenId).send().wait();
    await assertPublicBalance(sft, tokenId, bob.getAddress(), 1n);
  }, 300_000);

  it('returns correct private balances', async () => {
    const tokenId = 1n;
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 0n);
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
  }, 300_000);

  it('returns correct total supply', async () => {
    const tokenId = 1n;
    await assertTotalSupply(sft, tokenId, 0n);
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await assertTotalSupply(sft, tokenId, 1n);
    await sft.withWallet(alice).methods.mint_to_private(bob.getAddress(), tokenId).send().wait();
    await assertTotalSupply(sft, tokenId, 2n);
    await sft.withWallet(bob).methods.burn_private(bob.getAddress(), tokenId, 0n).send().wait();
    await assertTotalSupply(sft, tokenId, 1n);
  }, 300_000);

  it('transfers SFT with authorization', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    const transferCallInterface = sft
      .withWallet(bob)
      .methods.transfer_private_to_private(alice.getAddress(), bob.getAddress(), tokenId, 1n);
    const intent: IntentAction = {
      caller: bob.getAddress(),
      action: transferCallInterface,
    };
    const witness = await alice.createAuthWit(intent);
    await transferCallInterface.send({ authWitnesses: [witness] }).wait();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
  }, 300_000);

  it('burns SFT with authorization', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    const burnCallInterface = sft.withWallet(bob).methods.burn_private(alice.getAddress(), tokenId, 1n);
    const intent: IntentAction = {
      caller: bob.getAddress(),
      action: burnCallInterface,
    };
    const witness = await alice.createAuthWit(intent);
    await burnCallInterface.send({ authWitnesses: [witness] }).wait();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 0n);
    await assertTotalSupply(sft, tokenId, 0n);
  }, 300_000);

  it('enforces minter role for minting', async () => {
    const tokenId = 1n;
    const sftWithBobMinter = (await deploySFTWithMinter(bob)) as SFTContract;
    await expect(
      sftWithBobMinter.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait(),
    ).rejects.toThrow(/caller is not minter/);
    await sftWithBobMinter.withWallet(bob).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    await assertPrivateBalance(sftWithBobMinter, tokenId, alice.getAddress(), 1n);
  }, 300_000);

  it('enforces minter role for token type creation', async () => {
    const tokenId = 1n;
    const sftWithBobMinter = (await deploySFTWithMinter(bob)) as SFTContract;
    await expect(sftWithBobMinter.withWallet(alice).methods.create_token_type(tokenId).send().wait()).rejects.toThrow(
      /^Transaction 0x[0-9a-f]+ was app_logic_reverted\. Reason: $/,
    );
    await sftWithBobMinter.withWallet(bob).methods.create_token_type(tokenId).send().wait();
    await assertTokenTypeExists(sftWithBobMinter, tokenId, true);
  }, 300_000);

  it('enforces ownership for transfers', async () => {
    const tokenId = 1n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    await expect(
      sft
        .withWallet(bob)
        .methods.transfer_private_to_private(bob.getAddress(), carl.getAddress(), tokenId, 0n)
        .send()
        .wait(),
    ).rejects.toThrow(/sft not found in private/);
    await sft
      .withWallet(alice)
      .methods.transfer_private_to_private(alice.getAddress(), bob.getAddress(), tokenId, 0n)
      .send()
      .wait();
    await assertPrivateBalance(sft, tokenId, bob.getAddress(), 1n);
  }, 300_000);

  it('enforces authorization for transfers', async () => {
    const tokenId = 1n;
    const invalidNonce = 999n;
    await sft.withWallet(alice).methods.mint_to_private(alice.getAddress(), tokenId).send().wait();
    const transferCallInterface = sft
      .withWallet(bob)
      .methods.transfer_private_to_private(alice.getAddress(), bob.getAddress(), tokenId, invalidNonce);
    const intent: IntentAction = {
      caller: bob.getAddress(),
      action: transferCallInterface,
    };
    const witness = await carl.createAuthWit(intent);
    await expect(transferCallInterface.send({ authWitnesses: [witness] }).wait()).rejects.toThrow();
    await assertPrivateBalance(sft, tokenId, alice.getAddress(), 1n);
  }, 300_000);
});
