import { Contract, AccountWalletWithSecretKey, Wallet, AccountManager, Fr } from '@aztec/aztec.js';
import {
  AMOUNT,
  expectTokenBalances,
  setupPXE,
  wad,
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
} from './utils.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { getInitialTestAccounts } from '@aztec/accounts/testing';
import { SchnorrAccountContract } from '@aztec/accounts/schnorr';
import { deriveSigningKey } from '@aztec/stdlib/keys';

const setupTestSuite = async () => {
  const pxe = await setupPXE();
  const managers = await Promise.all(
    (await getInitialTestAccounts()).map(async (acc) => {
      return await AccountManager.create(
        pxe,
        acc.secret,
        new SchnorrAccountContract(deriveSigningKey(acc.secret)),
        acc.salt,
      );
    }),
  );
  const wallets = await Promise.all(managers.map((acc) => acc.register()));
  return { pxe, wallets };
};

describe('Tokenized Vault - Asset/Share Combinations', () => {
  let pxe: PXE;
  let wallets: AccountWalletWithSecretKey[];
  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let vault: Contract;
  let asset: Contract;

  beforeAll(async () => {
    ({ pxe, wallets } = await setupTestSuite());
    [alice, bob] = wallets;
  });

  beforeEach(async () => {
    [vault, asset] = await deployVaultAndAssetWithMinter(alice);

    // PXE knows bob
    // await pxe.registerAccount(bob.getSecretKey(), bob.getCompleteAddress().partialAddress);
    // await pxe.registerSender(bob.getAddress());

    // // PXE knows alice
    // await pxe.registerAccount(alice.getSecretKey(), alice.getCompleteAddress().partialAddress);
    // await pxe.registerSender(alice.getAddress());

    // // PXE
    // await pxe.registerContract(vault);
    // await pxe.registerContract(asset);
  });

  it.only('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    // Mint some assets to Alice and Bob for deposit/issue
    const initialAmount = 100;
    await asset.withWallet(alice).methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
    await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

    // Alice deposits public assets, receives public shares
    const depositAction = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, 9, 0);
    await setPublicAuthWit(vault.address, depositAction, alice);
    await vault
      .withWallet(alice)
      .methods.deposit_public_to_public(alice.getAddress(), alice.getAddress(), 9, 0)
      .send()
      .wait();

    // Simulate yield: mint assets to vault
    await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

    // Bob issues public shares for public assets
    const issuanceAction = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, 15, 0);
    await setPublicAuthWit(vault.address, issuanceAction, bob);
    await vault
      .withWallet(bob)
      .methods.issue_public_to_public(bob.getAddress(), bob.getAddress(), 10, 15, 0)
      .send()
      .wait();

    // Check asset balances
    let aliceAssets = await asset.methods.balance_of_public(alice.getAddress()).simulate();
    let bobAssets = await asset.methods.balance_of_public(bob.getAddress()).simulate();
    let vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    expect(aliceAssets).toBe(BigInt(initialAmount - 9)); // Got yield
    expect(bobAssets).toBe(BigInt(initialAmount - 15)); // Didn't get yield
    expect(vaultAssets).toBe(BigInt(29)); // 1 token left in vault due to rounding
    // Check shares balances
    let aliceShares = await vault.methods.balance_of_public(alice.getAddress()).simulate();
    let bobShares = await vault.methods.balance_of_public(bob.getAddress()).simulate();
    let totalSupply = await vault.methods.total_supply().simulate();
    expect(aliceShares).toBe(BigInt(9));
    expect(bobShares).toBe(BigInt(10));
    expect(totalSupply).toBe(BigInt(19));

    // Alice withdraws public assets by burning public shares
    // TODO: call preview max withdraw function
    // Cannot withdraw 14 due to rounding.
    const maxWithdraw = 13;
    await vault
      .withWallet(alice)
      .methods.withdraw_public_to_public(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
      .send()
      .wait();

    // Bob redeems public shares for public assets
    // Bob should get 15 asset tokens back, 1 token remains in the vault
    await vault
      .withWallet(bob)
      .methods.redeem_public_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0)
      .send()
      .wait();

    // Check asset balances
    aliceAssets = await asset.methods.balance_of_public(alice.getAddress()).simulate();
    bobAssets = await asset.methods.balance_of_public(bob.getAddress()).simulate();
    vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    expect(aliceAssets).toBe(BigInt(initialAmount + 4)); // Got yield
    expect(bobAssets).toBe(BigInt(initialAmount)); // Didn't get yield
    expect(vaultAssets).toBe(BigInt(1)); // 1 token left in vault due to rounding
    // Check shares balances
    aliceShares = await vault.methods.balance_of_public(alice.getAddress()).simulate();
    bobShares = await vault.methods.balance_of_public(bob.getAddress()).simulate();
    totalSupply = await vault.methods.total_supply().simulate();
    expect(aliceShares).toBe(BigInt(0));
    expect(bobShares).toBe(BigInt(0));
    expect(totalSupply).toBe(BigInt(0));
  }, 300_000);

  it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    await asset.withWallet(alice).methods.sync_private_state().simulate({});
    await asset.withWallet(bob).methods.sync_private_state().simulate({});

    // Mint some assets to Alice and Bob for deposit/issue
    const initialAmount = 100;
    await asset
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount)
      .send()
      .wait();
    await asset
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), bob.getAddress(), initialAmount)
      .send()
      .wait();

    // Alice deposits private assets, receives public shares
    const nonce = 1234;
    const depositAction = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, 9, nonce);
    const depositAuthWitness = await setPrivateAuthWit(vault.address, depositAction, alice);
    await vault
      .withWallet(alice)
      .methods.deposit_private_to_public(alice.getAddress(), alice.getAddress(), 9, 0)
      .with({ authWitnesses: [depositAuthWitness] })
      .send()
      .wait();

    // Simulate yield: mint assets to vault
    await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

    // Bob issues public shares for public assets
    const issuanceAction = asset.methods.transfer_private_to_public(bob.getAddress(), vault.address, 15, 0);
    const issuanceAuthWitness = await setPrivateAuthWit(vault.address, issuanceAction, bob);
    await vault
      .withWallet(bob)
      .methods.issue_private_to_public(bob.getAddress(), bob.getAddress(), 10, 15, 0)
      .with({ authWitnesses: [issuanceAuthWitness] })
      .send()
      .wait();

    // Check asset balances
    let aliceAssets = await asset.methods.balance_of_private(alice.getAddress()).simulate();
    let bobAssets = await asset.methods.balance_of_private(bob.getAddress()).simulate();
    let vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    expect(aliceAssets).toBe(BigInt(initialAmount - 9)); // Got yield
    expect(bobAssets).toBe(BigInt(initialAmount - 15)); // Didn't get yield
    expect(vaultAssets).toBe(BigInt(29)); // 1 token left in vault due to rounding
    // Check shares balances
    let aliceShares = await vault.methods.balance_of_public(alice.getAddress()).simulate();
    let bobShares = await vault.methods.balance_of_public(bob.getAddress()).simulate();
    let totalSupply = await vault.methods.total_supply().simulate();
    expect(aliceShares).toBe(BigInt(9));
    expect(bobShares).toBe(BigInt(10));
    expect(totalSupply).toBe(BigInt(19));

    // Alice withdraws private assets by burning public shares
    // TODO: call preview max withdraw function
    // Cannot withdraw 14 due to rounding.
    const maxWithdraw = 13;
    await vault
      .withWallet(alice)
      .methods.withdraw_public_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
      .send()
      .wait();

    // Bob redeems private shares for public assets
    // Bob should get 15 asset tokens back, 1 token remains in the vault
    const minAssets = 15;
    await vault
      .withWallet(bob)
      .methods.redeem_public_to_private_exact(bob.getAddress(), bob.getAddress(), bobShares, minAssets, 0)
      .send()
      .wait();

    // Check asset balances
    aliceAssets = await asset.methods.balance_of_private(alice.getAddress()).simulate();
    bobAssets = await asset.methods.balance_of_private(bob.getAddress()).simulate();
    vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    expect(aliceAssets).toBe(BigInt(initialAmount + 4)); // Got yield
    expect(bobAssets).toBe(BigInt(initialAmount)); // Didn't get yield
    expect(vaultAssets).toBe(BigInt(1)); // 1 token left in vault due to rounding
    // Check shares balances
    aliceShares = await vault.methods.balance_of_public(alice.getAddress()).simulate();
    bobShares = await vault.methods.balance_of_public(bob.getAddress()).simulate();
    totalSupply = await vault.methods.total_supply().simulate();
    expect(aliceShares).toBe(BigInt(0));
    expect(bobShares).toBe(BigInt(0));
    expect(totalSupply).toBe(BigInt(0));
  }, 300_000);

  it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    // Alice deposits public assets, receives private shares
    await asset.withWallet(alice).methods.approve_public(vault.address, wad(10)).send().wait();
    await vault.withWallet(alice).methods.deposit_public_for_private_shares(wad(10), alice.getAddress()).send().wait();

    // Simulate yield: vault mints extra assets to itself
    await asset.withWallet(alice).methods.mint_to_public(vault.address, wad(5)).send().wait();

    // Bob issues private shares for public assets
    await asset.withWallet(bob).methods.approve_public(vault.address, wad(20)).send().wait();
    await vault.withWallet(bob).methods.issue_public_for_private_shares(wad(20), bob.getAddress()).send().wait();

    // Alice withdraws public assets by burning private shares
    const aliceShares = await vault.methods.balance_of_private(alice.getAddress()).simulate();
    await vault
      .withWallet(alice)
      .methods.withdraw_private_shares_for_public_assets(aliceShares, alice.getAddress(), alice.getAddress())
      .send()
      .wait();

    // Bob redeems private shares for public assets
    const bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
    await vault
      .withWallet(bob)
      .methods.redeem_private_shares_for_public_assets(bobShares, bob.getAddress(), bob.getAddress())
      .send()
      .wait();

    // Check balances
    const aliceAsset = await asset.methods.balance_of_public(alice.getAddress()).simulate();
    const bobAsset = await asset.methods.balance_of_public(bob.getAddress()).simulate();
    expect(aliceAsset + bobAsset).toBe(wad(100 + 100 + 5)); // initial + yield
  }, 300_000);

  it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    // Alice shields assets to private
    await asset
      .withWallet(alice)
      .methods.transfer_public_to_private(alice.getAddress(), alice.getAddress(), wad(10), 0)
      .send()
      .wait();
    await asset.withWallet(alice).methods.sync_private_state().simulate({});

    // Alice deposits private assets, receives private shares
    await asset.withWallet(alice).methods.approve_private(vault.address, wad(10)).send().wait();
    await vault.withWallet(alice).methods.deposit_private_for_private_shares(wad(10), alice.getAddress()).send().wait();

    // Simulate yield: vault mints extra assets to itself (private for realism)
    await asset
      .withWallet(alice)
      .methods.transfer_public_to_private(alice.getAddress(), vault.address, wad(5), 0)
      .send()
      .wait();

    // Bob shields assets to private and issues private shares
    await asset
      .withWallet(bob)
      .methods.transfer_public_to_private(bob.getAddress(), bob.getAddress(), wad(20), 0)
      .send()
      .wait();
    await asset.withWallet(bob).methods.sync_private_state().simulate({});
    await asset.withWallet(bob).methods.approve_private(vault.address, wad(20)).send().wait();
    await vault.withWallet(bob).methods.issue_private_for_private_shares(wad(20), bob.getAddress()).send().wait();

    // Alice withdraws private assets by burning private shares
    const aliceShares = await vault.methods.balance_of_private(alice.getAddress()).simulate();
    await vault
      .withWallet(alice)
      .methods.withdraw_private_shares_for_private_assets(aliceShares, alice.getAddress(), alice.getAddress())
      .send()
      .wait();

    // Bob redeems private shares for private assets
    const bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
    await vault
      .withWallet(bob)
      .methods.redeem_private_shares_for_private_assets(bobShares, bob.getAddress(), bob.getAddress())
      .send()
      .wait();

    // Check balances
    const aliceAsset = await asset.methods.balance_of_private(alice.getAddress()).simulate();
    const bobAsset = await asset.methods.balance_of_private(bob.getAddress()).simulate();
    expect(aliceAsset + bobAsset).toBe(wad(10 + 20)); // Alice withdrew private, Bob private
  }, 300_000);
});
