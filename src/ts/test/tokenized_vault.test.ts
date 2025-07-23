import { Contract, AccountWalletWithSecretKey } from '@aztec/aztec.js';
import {
  setupPXE,
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  expectTokenBalances,
} from './utils.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';
import { TokenContract } from '../../artifacts/Token.js';

const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const managers = await getInitialTestAccountsManagers(pxe);
  const wallets = await Promise.all(managers.map((acc) => acc.register()));
  return { pxe, wallets, store };
};

describe('Tokenized Vault - Asset/Share Combinations', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;
  let wallets: AccountWalletWithSecretKey[];
  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let vault: TokenContract;
  let asset: TokenContract;

  const initialAmount = 100;
  const assetsAlice = 9; // Assets Alice wants to deposit
  const sharesAlice = assetsAlice; // The first deposit receives 1 share for each asset.
  const yieldAmount = 5;
  const sharesBob = 10; // Shares Bob wants to get issued
  const assetsBob = 15; // Bob needs to provide assets = sharesBob * (assetsAlice + yieldAmount + 1) / (sharesAlice + 1);
  const aliceEarnings = 4; // Due to rounding, alice doesn't get the 5 assets received as yield by the vault, only 4.
  const dust = 1; // 1 asset is left in the vault

  beforeAll(async () => {
    ({ pxe, wallets, store } = await setupTestSuite());
    [alice, bob] = wallets;
  });

  beforeEach(async () => {
    [vault, asset] = (await deployVaultAndAssetWithMinter(alice)) as [TokenContract, TokenContract];
  });

  afterAll(async () => {
    await store.delete();
  });

  it('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    // Mint some assets to Alice and Bob for deposit/issue
    await asset.withWallet(alice).methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
    await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

    // Alice deposits public assets, receives public shares
    const depositAction = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
    await setPublicAuthWit(vault.address, depositAction, alice);
    await vault
      .withWallet(alice)
      .methods.deposit_public_to_public(alice.getAddress(), alice.getAddress(), assetsAlice, 0)
      .send()
      .wait();

    // Simulate yield: mint assets to vault
    await asset.withWallet(alice).methods.mint_to_public(vault.address, yieldAmount).send().wait();

    // Bob issues public shares for public assets
    const issuanceAction = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, assetsBob, 0);
    await setPublicAuthWit(vault.address, issuanceAction, bob);
    await vault
      .withWallet(bob)
      .methods.issue_public_to_public(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0)
      .send()
      .wait();

    // Check asset balances
    await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount - assetsAlice), BigInt(0));
    await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - assetsBob), BigInt(0));
    await expectTokenBalances(asset, vault.address, BigInt(assetsAlice + assetsBob + yieldAmount), BigInt(0));
    // Check shares balances
    await expectTokenBalances(vault, alice.getAddress(), BigInt(sharesAlice), BigInt(0));
    await expectTokenBalances(vault, bob.getAddress(), BigInt(sharesBob), BigInt(0));
    expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

    // Alice withdraws public assets by burning public shares
    // TODO: call preview max withdraw function
    // Cannot withdraw 14 due to rounding.
    const maxWithdraw = assetsAlice + aliceEarnings;
    await vault
      .withWallet(alice)
      .methods.withdraw_public_to_public(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
      .send()
      .wait();

    // Bob redeems public shares for public assets
    // Bob should get 15 asset tokens back, 1 token remains in the vault
    await vault
      .withWallet(bob)
      .methods.redeem_public_to_public(bob.getAddress(), bob.getAddress(), sharesBob, 0)
      .send()
      .wait();

    // Check asset balances
    await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount + aliceEarnings), BigInt(0));
    await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
    await expectTokenBalances(asset, vault.address, BigInt(dust), BigInt(0));
    // Check shares balances
    await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
    await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
    expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
  }, 300_000);

  it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    // Mint some assets to Alice and Bob for deposit/issue
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
    const depositAction = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
    const depositAuthWitness = await setPrivateAuthWit(vault.address, depositAction, alice);
    await vault
      .withWallet(alice)
      .methods.deposit_private_to_public(alice.getAddress(), alice.getAddress(), assetsAlice, 0)
      .with({ authWitnesses: [depositAuthWitness] })
      .send()
      .wait();

    // Simulate yield: mint assets to vault
    await asset.withWallet(alice).methods.mint_to_public(vault.address, yieldAmount).send().wait();

    // Bob issues public shares for public assets
    const issuanceAction = asset.methods.transfer_private_to_public(bob.getAddress(), vault.address, assetsBob, 0);
    const issuanceAuthWitness = await setPrivateAuthWit(vault.address, issuanceAction, bob);
    await vault
      .withWallet(bob)
      .methods.issue_private_to_public_exact(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0)
      .with({ authWitnesses: [issuanceAuthWitness] })
      .send()
      .wait();

    // Check asset balances
    await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - assetsAlice));
    await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount - assetsBob));
    await expectTokenBalances(asset, vault.address, BigInt(assetsAlice + assetsBob + yieldAmount), BigInt(0));
    // Check shares balances
    await expectTokenBalances(vault, alice.getAddress(), BigInt(sharesAlice), BigInt(0));
    await expectTokenBalances(vault, bob.getAddress(), BigInt(sharesBob), BigInt(0));
    expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

    // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
    // // Alice withdraws private assets by burning public shares
    // // TODO: call preview max withdraw function
    // // Cannot withdraw 14 due to rounding.
    // const maxWithdraw = assetsAlice + aliceEarnings;
    // await vault
    //   .withWallet(alice)
    //   .methods.withdraw_public_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
    //   .send()
    //   .wait();

    // // Bob redeems private shares for public assets
    // // Bob should get 15 asset tokens back, 1 token remains in the vault
    // const minAssets = assetsBob;
    // await vault
    //   .withWallet(bob)
    //   .methods.redeem_public_to_private_exact(bob.getAddress(), bob.getAddress(), sharesBob, minAssets, 0)
    //   .send()
    //   .wait();

    // // Check asset balances
    // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + aliceEarnings));
    // await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount));
    // await expectTokenBalances(asset, vault.address, BigInt(dust), BigInt(0));
    // // Check shares balances
    // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
    // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
    // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
  }, 300_000);

  it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    // Mint some assets to Alice and Bob for deposit/issue
    await asset.withWallet(alice).methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
    await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

    // Alice deposits public assets, receives public shares
    const depositAction = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
    await setPublicAuthWit(vault.address, depositAction, alice);
    await vault
      .withWallet(alice)
      .methods.deposit_public_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesAlice, 0)
      .send()
      .wait();

    // Simulate yield: mint assets to vault
    await asset.withWallet(alice).methods.mint_to_public(vault.address, yieldAmount).send().wait();

    // Bob issues public shares for public assets
    const issuanceAction = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, assetsBob, 0);
    await setPublicAuthWit(vault.address, issuanceAction, bob);
    await vault
      .withWallet(bob)
      .methods.issue_public_to_private(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0)
      .send()
      .wait();

    // Check asset balances
    await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount - assetsAlice), BigInt(0));
    await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - assetsBob), BigInt(0));
    await expectTokenBalances(asset, vault.address, BigInt(assetsAlice + assetsBob + yieldAmount), BigInt(0));
    // Check shares balances
    await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(sharesAlice));
    await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(sharesBob));
    expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

    // Alice withdraws public assets by burning public shares
    // TODO: call preview max withdraw function
    // Cannot withdraw 14 due to rounding.
    const maxWithdraw = assetsAlice + aliceEarnings;
    await vault
      .withWallet(alice)
      .methods.withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, sharesAlice, 0)
      .send()
      .wait();

    // Bob redeems public shares for public assets
    // Bob should get 15 asset tokens back, 1 token remains in the vault
    await vault
      .withWallet(bob)
      .methods.redeem_private_to_public(bob.getAddress(), bob.getAddress(), sharesBob, 0)
      .send()
      .wait();

    // Check asset balances
    await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount + aliceEarnings), BigInt(0));
    await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
    await expectTokenBalances(asset, vault.address, BigInt(dust), BigInt(0));
    // Check shares balances
    await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
    await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
    expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
  }, 300_000);

  it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
    // Mint some assets to Alice and Bob for deposit/issue
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
    const depositAction = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
    const depositAuthWitness = await setPrivateAuthWit(vault.address, depositAction, alice);
    await vault
      .withWallet(alice)
      .methods.deposit_private_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesAlice, 0)
      .with({ authWitnesses: [depositAuthWitness] })
      .send()
      .wait();

    // Simulate yield: mint assets to vault
    await asset.withWallet(alice).methods.mint_to_public(vault.address, yieldAmount).send().wait();

    // Bob issues public shares for public assets
    const issuanceAction = asset.methods.transfer_private_to_public(bob.getAddress(), vault.address, assetsBob, 0);
    const issuanceAuthWitness = await setPrivateAuthWit(vault.address, issuanceAction, bob);
    await vault
      .withWallet(bob)
      .methods.issue_private_to_private_exact(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0)
      .with({ authWitnesses: [issuanceAuthWitness] })
      .send()
      .wait();

    // Check asset balances
    await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - assetsAlice));
    await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount - assetsBob));
    await expectTokenBalances(asset, vault.address, BigInt(assetsAlice + assetsBob + yieldAmount), BigInt(0));
    // Check shares balances
    await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(sharesAlice));
    await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(sharesBob));
    expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

    // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
    // // Alice withdraws public assets by burning public shares
    // // TODO: call preview max withdraw function
    // // Cannot withdraw 14 due to rounding.
    // const maxWithdraw = assetsAlice + aliceEarnings;
    // await vault
    //   .withWallet(alice)
    //   .methods.withdraw_private_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, sharesAlice, 0)
    //   .send()
    //   .wait();

    // // Bob redeems public shares for public assets
    // // Bob should get 15 asset tokens back, 1 token remains in the vault
    // await vault
    //   .withWallet(bob)
    //   .methods.redeem_private_to_private_exact(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0)
    //   .send()
    //   .wait();

    // // Check asset balances
    // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + aliceEarnings));
    // await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount));
    // await expectTokenBalances(asset, vault.address, BigInt(dust), BigInt(0));
    // // Check shares balances
    // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
    // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
    // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
  }, 300_000);

  it('Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws', async () => {
    // Mint some assets to Alice and Bob for deposit/issue
    await asset
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount)
      .send()
      .wait();
    await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

    // Alice deposits private assets, receives public shares
    const privateDepositAction = asset.methods.transfer_private_to_public(
      alice.getAddress(),
      vault.address,
      assetsAlice,
      0,
    );
    const depositAuthWitness = await setPrivateAuthWit(vault.address, privateDepositAction, alice);
    await vault
      .withWallet(alice)
      .methods.deposit_private_to_private_exact(alice.getAddress(), alice.getAddress(), assetsAlice, sharesAlice, 0)
      .with({ authWitnesses: [depositAuthWitness] })
      .send()
      .wait();

    // Simulate yield: mint assets to vault
    await asset.withWallet(alice).methods.mint_to_public(vault.address, yieldAmount).send().wait();

    // Bob issues public shares for public assets
    const publicDepositAction = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, assetsBob, 0);
    await setPublicAuthWit(vault.address, publicDepositAction, bob);
    await vault
      .withWallet(bob)
      .methods.deposit_public_to_private_exact(bob.getAddress(), bob.getAddress(), assetsBob, sharesBob, 0)
      .send()
      .wait();

    // Check asset balances
    await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - assetsAlice));
    await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - assetsBob), BigInt(0));
    await expectTokenBalances(asset, vault.address, BigInt(assetsAlice + assetsBob + yieldAmount), BigInt(0));
    // Check shares balances
    await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(sharesAlice));
    await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(sharesBob));
    expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

    // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
    // // Alice withdraws public assets by burning public shares
    // // TODO: call preview max withdraw function
    // // Cannot withdraw 14 due to rounding.
    // const maxWithdraw = assetsAlice + aliceEarnings;
    // await vault
    //   .withWallet(alice)
    //   .methods.withdraw_private_to_private_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, sharesAlice, 0)
    //   .send()
    //   .wait();

    // // Bob redeems public shares for public assets
    // // Bob should get 15 asset tokens back, 1 token remains in the vault
    // await vault
    //   .withWallet(bob)
    //   .methods.withdraw_private_to_public_exact(bob.getAddress(), bob.getAddress(), assetsBob, sharesBob, 0)
    //   .send()
    //   .wait();

    // // Check asset balances
    // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + aliceEarnings));
    // await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
    // await expectTokenBalances(asset, vault.address, BigInt(dust), BigInt(0));
    // // Check shares balances
    // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
    // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
    // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
  }, 300_000);
});
