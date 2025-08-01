import { ContractFunctionInteraction, AccountWalletWithSecretKey } from '@aztec/aztec.js';
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

describe('Tokenized Vault', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;
  let wallets: AccountWalletWithSecretKey[];
  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let carl: AccountWalletWithSecretKey;
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

  async function callVaultWithPublicAuthWit(
    action: ContractFunctionInteraction,
    from: AccountWalletWithSecretKey,
    amount: number,
    nonce: number = 0,
  ) {
    const transfer = asset.methods.transfer_public_to_public(from.getAddress(), vault.address, amount, nonce);
    await setPublicAuthWit(vault.address, transfer, from);
    await action.send().wait();
  }

  async function callVaultWithPrivateAuthWit(
    action: ContractFunctionInteraction,
    from: AccountWalletWithSecretKey,
    amount: number,
    nonce: number = 0,
  ) {
    const transfer = asset.methods.transfer_private_to_public(from.getAddress(), vault.address, amount, nonce);
    const transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, from);
    await action
      .with({ authWitnesses: [transferAuthWitness] })
      .send()
      .wait();
  }

  async function mintAndDepositInPrivate(
    account: AccountWalletWithSecretKey,
    mint: number,
    assets: number,
    shares: number,
  ) {
    // Mint some assets to Alice
    await asset.methods.mint_to_private(account.getAddress(), account.getAddress(), mint).send().wait();

    // Alice deposits private assets, receives private shares
    await callVaultWithPrivateAuthWit(
      vault
        .withWallet(account)
        .methods.deposit_private_to_private(account.getAddress(), account.getAddress(), assets, shares, 0),
      account,
      assets,
    );
  }

  async function mintAndDepositInPublic(account: AccountWalletWithSecretKey, mint: number, assets: number) {
    // Mint some assets to Alice
    await asset.methods.mint_to_public(account.getAddress(), mint).send().wait();

    // Alice deposits public assets, receives public shares
    await callVaultWithPublicAuthWit(
      vault.withWallet(account).methods.deposit_public_to_public(account.getAddress(), account.getAddress(), assets, 0),
      account,
      assets,
    );
  }

  beforeAll(async () => {
    ({ pxe, wallets, store } = await setupTestSuite());
    [alice, bob, carl] = wallets;
  });

  beforeEach(async () => {
    [vault, asset] = (await deployVaultAndAssetWithMinter(alice)) as [TokenContract, TokenContract];
    // Alice is the minter of the asset contract and the only one interacting with it to mint tokens.
    asset = asset.withWallet(alice);
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('Successful interactions, no authwits.', () => {
    it('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits public assets, receives public shares
      vault = vault.withWallet(alice);
      await callVaultWithPublicAuthWit(
        vault.methods.deposit_public_to_public(alice.getAddress(), alice.getAddress(), assetsAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      vault = vault.withWallet(bob);
      await callVaultWithPublicAuthWit(
        vault.methods.issue_public_to_public(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = assetsAlice + aliceEarnings;
      vault = vault.withWallet(alice);
      await vault.methods
        .withdraw_public_to_public(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
        .send()
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      vault = vault.withWallet(bob);
      await vault.methods.redeem_public_to_public(bob.getAddress(), bob.getAddress(), sharesBob, 0).send().wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);

    it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_private(alice.getAddress(), bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives public shares
      vault = vault.withWallet(alice);
      await callVaultWithPrivateAuthWit(
        vault.methods.deposit_private_to_public(alice.getAddress(), alice.getAddress(), assetsAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      vault = vault.withWallet(bob);
      await callVaultWithPrivateAuthWit(
        vault.methods.issue_private_to_public_exact(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
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
      // await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      // await expectTokenBalances(asset, bob, 0, initialAmount);
      // await expectTokenBalances(asset, vault.address, dust, 0);
      // // Check shares balances
      // await expectTokenBalances(vault, alice, 0, 0);
      // await expectTokenBalances(vault, bob, 0, 0);
      // expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);

    it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits public assets, receives public shares
      vault = vault.withWallet(alice);
      await callVaultWithPublicAuthWit(
        vault.methods.deposit_public_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      vault = vault.withWallet(bob);
      await callVaultWithPublicAuthWit(
        vault.methods.issue_public_to_private(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = assetsAlice + aliceEarnings;
      vault = vault.withWallet(alice);
      await vault.methods
        .withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, sharesAlice, 0)
        .send()
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      vault = vault.withWallet(bob);
      await vault.methods.redeem_private_to_public(bob.getAddress(), bob.getAddress(), sharesBob, 0).send().wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);

    it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_private(alice.getAddress(), bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives private shares
      vault = vault.withWallet(alice);
      await callVaultWithPrivateAuthWit(
        vault.methods.deposit_private_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues private shares for private assets
      vault = vault.withWallet(bob);
      await callVaultWithPrivateAuthWit(
        vault.methods.issue_private_to_private_exact(bob.getAddress(), bob.getAddress(), sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
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
      // await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      // await expectTokenBalances(asset, bob, 0, initialAmount);
      // await expectTokenBalances(asset, vault.address, dust, 0);
      // // Check shares balances
      // await expectTokenBalances(vault, alice, 0, 0);
      // await expectTokenBalances(vault, bob, 0, 0);
      // expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);

    it('Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives public shares
      vault = vault.withWallet(alice);
      await callVaultWithPrivateAuthWit(
        vault.methods.deposit_private_to_private_exact(
          alice.getAddress(),
          alice.getAddress(),
          assetsAlice,
          sharesAlice,
          0,
        ),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      vault = vault.withWallet(bob);
      await callVaultWithPublicAuthWit(
        vault.methods.deposit_public_to_private_exact(bob.getAddress(), bob.getAddress(), assetsBob, sharesBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
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
      // await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      // await expectTokenBalances(asset, bob, initialAmount, 0);
      // await expectTokenBalances(asset, vault.address, dust, 0);
      // // Check shares balances
      // await expectTokenBalances(vault, alice, 0, 0);
      // await expectTokenBalances(vault, bob, 0, 0);
      // expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);
  });

  describe('Successful interactions with authwits.', () => {
    beforeEach(async () => {
      vault = vault.withWallet(carl); // Only Carl interacts with the vault
    });

    it('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits public assets, receives public shares
      const depositAction = vault.methods.deposit_public_to_public(
        alice.getAddress(),
        alice.getAddress(),
        assetsAlice,
        0,
      );
      await setPublicAuthWit(carl, depositAction, alice);
      await callVaultWithPublicAuthWit(depositAction, alice, assetsAlice);

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_public_to_public(
        bob.getAddress(),
        bob.getAddress(),
        sharesBob,
        assetsBob,
        0,
      );
      await setPublicAuthWit(carl, issueAction, bob);
      await callVaultWithPublicAuthWit(issueAction, bob, assetsBob);

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      const withdrawAction = vault.methods.withdraw_public_to_public(
        alice.getAddress(),
        alice.getAddress(),
        maxWithdraw,
        0,
      );
      await setPublicAuthWit(carl, withdrawAction, alice);
      await withdrawAction.send().wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const redeemAction = vault.methods.redeem_public_to_public(bob.getAddress(), bob.getAddress(), sharesBob, 0);
      await setPublicAuthWit(carl, redeemAction, bob);
      await redeemAction.send().wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);

    it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_private(alice.getAddress(), bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives public shares
      const depositAction = vault.methods.deposit_private_to_public(
        alice.getAddress(),
        alice.getAddress(),
        assetsAlice,
        0,
      );
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice);
      await callVaultWithPrivateAuthWit(
        depositAction.with({ authWitnesses: [depositAuthWitness] }),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_private_to_public_exact(
        bob.getAddress(),
        bob.getAddress(),
        sharesBob,
        assetsBob,
        0,
      );
      const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob);
      await callVaultWithPrivateAuthWit(issueAction.with({ authWitnesses: [issueAuthWitness] }), bob, assetsBob);

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws private assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // await vault
      //   .methods.withdraw_public_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
      //   .send()
      //   .wait();

      // // Bob redeems private shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // const minAssets = 15;
      // await vault
      //   .methods.redeem_public_to_private_exact(bob.getAddress(), bob.getAddress(), sharesBob, minAssets, 0)
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      // await expectTokenBalances(asset, bob, 0, initialAmount);
      // await expectTokenBalances(asset, vault.address, dust, 0);
      // await expectTokenBalances(asset, carl, 0, 0);
      // // Check shares balances
      // await expectTokenBalances(vault, alice, 0, 0);
      // await expectTokenBalances(vault, bob, 0, 0);
      // expect(await vault.methods.total_supply().simulate()).toBe(0n);
      // await expectTokenBalances(vault, carl, 0, 0);
    }, 300_000);

    it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits public assets, receives public shares
      const depositAction = vault.methods.deposit_public_to_private(
        alice.getAddress(),
        alice.getAddress(),
        assetsAlice,
        sharesAlice,
        0,
      );
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice);
      await callVaultWithPublicAuthWit(depositAction.with({ authWitnesses: [depositAuthWitness] }), alice, assetsAlice);

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_public_to_private(
        bob.getAddress(),
        bob.getAddress(),
        sharesBob,
        assetsBob,
        0,
      );
      const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob);
      await callVaultWithPublicAuthWit(issueAction.with({ authWitnesses: [issueAuthWitness] }), bob, assetsBob);

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      const withdrawAction = vault.methods.withdraw_private_to_public_exact(
        alice.getAddress(),
        alice.getAddress(),
        maxWithdraw,
        sharesAlice,
        0,
      );
      const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice);
      await withdrawAction
        .with({ authWitnesses: [withdrawAuthWitness] })
        .send()
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const redeemAction = vault.methods.redeem_private_to_public(bob.getAddress(), bob.getAddress(), sharesBob, 0);
      const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob);
      await redeemAction
        .with({ authWitnesses: [redeemAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);

    it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_private(alice.getAddress(), bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives public shares
      const depositAction = vault.methods.deposit_private_to_private(
        alice.getAddress(),
        alice.getAddress(),
        assetsAlice,
        sharesAlice,
        0,
      );
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice);
      await callVaultWithPrivateAuthWit(
        depositAction.with({ authWitnesses: [depositAuthWitness] }),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_private_to_private_exact(
        bob.getAddress(),
        bob.getAddress(),
        sharesBob,
        assetsBob,
        0,
      );
      const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob);
      await callVaultWithPrivateAuthWit(issueAction.with({ authWitnesses: [issueAuthWitness] }), bob, assetsBob);

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws public assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // const withdrawAction = vault.methods.withdraw_private_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0);
      // const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice);
      // await vault
      //   .methods.withdraw_private_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
      //   .with({ authWitnesses: [withdrawAuthWitness] })
      //   .send()
      //   .wait();

      // // Bob redeems public shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // const redeemAction = vault.methods.redeem_private_to_private_exact(bob.getAddress(), bob.getAddress(), sharesBob, 15, 0);
      // const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob);
      // await vault
      //   .methods.redeem_private_to_private_exact(bob.getAddress(), bob.getAddress(), sharesBob, 15, 0)
      //   .with({ authWitnesses: [redeemAuthWitness] })
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      // await expectTokenBalances(asset, bob, 0, initialAmount);
      // await expectTokenBalances(asset, vault.address, dust, 0);
      // await expectTokenBalances(asset, carl, 0, 0);
      // // Check shares balances
      // await expectTokenBalances(vault, alice, 0, 0);
      // await expectTokenBalances(vault, bob, 0, 0);
      // await expectTokenBalances(vault, carl, 0, 0);
      // expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);

    it('Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();
      await asset.methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives public shares
      const depositAction = vault.methods.deposit_private_to_private_exact(
        alice.getAddress(),
        alice.getAddress(),
        assetsAlice,
        sharesAlice,
        0,
      );
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice);
      await callVaultWithPrivateAuthWit(
        depositAction.with({ authWitnesses: [depositAuthWitness] }),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send().wait();

      // Bob issues public shares for public assets
      const publicDepositAction = vault.methods.deposit_public_to_private_exact(
        bob.getAddress(),
        bob.getAddress(),
        assetsBob,
        sharesBob,
        0,
      );
      const publicDepositAuthWitness = await setPrivateAuthWit(carl, publicDepositAction, bob);
      await callVaultWithPublicAuthWit(
        publicDepositAction.with({ authWitnesses: [publicDepositAuthWitness] }),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(sharesBob + sharesAlice));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws public assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // const withdrawAction = vault.methods.withdraw_private_to_private_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0);
      // const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice);
      // await vault
      //   .methods.withdraw_private_to_private_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
      //   .with({ authWitnesses: [withdrawAuthWitness] })
      //   .send()
      //   .wait();

      // // Bob redeems public shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // const publicWithdrawAction = vault.methods.withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), 15, sharesBob, 0);
      // const publicWithdrawAuthWitness = await setPrivateAuthWit(carl, publicWithdrawAction, alice);
      // await vault
      //   .methods.withdraw_private_to_public_exact(bob.getAddress(), bob.getAddress(), 15, sharesBob, 0)
      //   .with({ authWitnesses: [publicWithdrawAuthWitness] })
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      // await expectTokenBalances(asset, bob, initialAmount, 0);
      // await expectTokenBalances(asset, vault.address, dust, 0);
      // await expectTokenBalances(asset, carl, 0, 0);
      // // Check shares balances
      // await expectTokenBalances(vault, alice, 0, 0);
      // await expectTokenBalances(vault, bob, 0, 0);
      // await expectTokenBalances(vault, carl, 0, 0);
      // expect(await vault.methods.total_supply().simulate()).toBe(0n);
    }, 300_000);
  });

  describe('Deposit failures: incorrect amounts', () => {
    beforeEach(async () => {
      vault = vault.withWallet(alice); // Only Alice interacts with the vault
    });

    it('deposit_public_to_public', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, initialAmount + 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_public_to_public(alice.getAddress(), alice.getAddress(), initialAmount + 1, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, assetsAlice - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods.deposit_public_to_public(alice.getAddress(), alice.getAddress(), assetsAlice, 0).send().wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('deposit_public_to_private', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, initialAmount + 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_public_to_private(alice.getAddress(), alice.getAddress(), initialAmount + 1, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, assetsAlice - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_public_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_public_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Too many shares requested
    }, 300_000);

    it('deposit_private_to_public', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, initialAmount + 1, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_public(alice.getAddress(), alice.getAddress(), initialAmount + 1, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, assetsAlice - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_public(alice.getAddress(), alice.getAddress(), assetsAlice, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);
    }, 300_000);

    it('deposit_private_to_private', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, initialAmount + 1, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_private(alice.getAddress(), alice.getAddress(), initialAmount + 1, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, assetsAlice - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Too many shares requested
    }, 300_000);

    it('deposit_public_to_private_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, initialAmount + 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_public_to_private_exact(
            alice.getAddress(),
            alice.getAddress(),
            initialAmount + 1,
            sharesRequested,
            0,
          )
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, assetsAlice - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_public_to_private_exact(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_public_to_private_exact(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('deposit_private_to_private_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, initialAmount + 1, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_private_exact(
            alice.getAddress(),
            alice.getAddress(),
            initialAmount + 1,
            sharesRequested,
            0,
          )
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, assetsAlice - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_private_exact(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, assetsAlice, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .deposit_private_to_private_exact(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);
  });

  describe('Issue failures: incorrect amounts', () => {
    beforeEach(async () => {
      vault = vault.withWallet(alice); // Only Alice interacts with the vault
    });

    it('issue_public_to_public', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, maxAssets, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_public_to_public(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, maxAssets - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_public_to_public(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('issue_public_to_private', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, maxAssets, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_public_to_private(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, maxAssets - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_public_to_private(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, maxAssets, 0);
      await setPublicAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_public_to_private(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('issue_private_to_public_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, maxAssets, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_private_to_public_exact(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, maxAssets - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_private_to_public_exact(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, maxAssets, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_private_to_public_exact(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('issue_private_to_private_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount).send().wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, maxAssets, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_private_to_private_exact(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, maxAssets - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_private_to_private_exact(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, maxAssets, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice);
      await expect(
        vault.methods
          .issue_private_to_private_exact(alice.getAddress(), alice.getAddress(), sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);
  });

  describe('Withdraw failures: incorrect amounts', () => {
    beforeEach(async () => {
      vault = vault.withWallet(alice); // Only Alice interacts with the vault
    });

    it('withdraw_public_to_public', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt withdrawing more assets than allowed
      await expect(
        vault.methods
          .withdraw_public_to_public(alice.getAddress(), alice.getAddress(), assetsAlice + 1, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('withdraw_public_to_private', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt withdrawing more assets than allowed
      // TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
      await expect(
        vault.methods
          .withdraw_public_to_private(alice.getAddress(), alice.getAddress(), assetsAlice + 1, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/No public key registered for address/); // /app_logic_reverted/
    }, 300_000);

    it('withdraw_private_to_private', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt withdrawing more assets than allowed
      // TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
      let sharesRequested = assetsAlice;
      await expect(
        vault.methods
          .withdraw_private_to_private(alice.getAddress(), alice.getAddress(), assetsAlice + 1, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/No public key registered for address/); // /app_logic_reverted/ /Insufficient shares burnt/

      // Attempt burning more shares than Alice actually has
      sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods
          .withdraw_private_to_private(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);
    }, 300_000);

    it('withdraw_private_to_public_exact', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt withdrawing more assets than allowed
      let sharesRequested = assetsAlice;
      await expect(
        vault.methods
          .withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), assetsAlice + 1, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // /Underflow/

      // Attempt burning more shares than Alice actually has
      sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods
          .withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);
    }, 300_000);

    it('withdraw_private_to_private_exact', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt withdrawing more assets than allowed
      // TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
      let sharesRequested = assetsAlice;
      await expect(
        vault.methods
          .withdraw_private_to_private_exact(
            alice.getAddress(),
            alice.getAddress(),
            assetsAlice + 1,
            sharesRequested,
            0,
          )
          .send()
          .wait(),
      ).rejects.toThrow(/No public key registered for address/); // /app_logic_reverted/ /Underflow/

      // Attempt burning more shares than Alice actually has
      sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods
          .withdraw_private_to_private_exact(alice.getAddress(), alice.getAddress(), assetsAlice, sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);
    }, 300_000);
  });

  describe('Redeem failures: incorrect amounts', () => {
    beforeEach(async () => {
      vault = vault.withWallet(alice); // Only Alice interacts with the vault
    });

    it('redeem_public_to_public', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods.redeem_public_to_public(alice.getAddress(), alice.getAddress(), sharesRequested, 0).send().wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('redeem_public_to_private_exact', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      let minAssets = 0; // minAssets > 0 would cause fail with "No public key registered for address" (TODO(#15666 & #15118))
      await expect(
        vault.methods
          .redeem_public_to_private_exact(alice.getAddress(), alice.getAddress(), sharesRequested, minAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // /Underflow/

      // Attempt redeeming with an invalid rate
      // TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
      sharesRequested = assetsAlice;
      minAssets = assetsAlice + 1;
      await expect(
        vault.methods
          .redeem_public_to_private_exact(alice.getAddress(), alice.getAddress(), sharesRequested, minAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/No public key registered for address/); // /app_logic_reverted/ /Underflow/
    }, 300_000);

    it('redeem_private_to_public', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods
          .redeem_private_to_public(alice.getAddress(), alice.getAddress(), sharesRequested, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);
    }, 300_000);

    it('redeem_private_to_private_exact', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      let minAssets = 0; // minAssets > 0 would cause fail with "No public key registered for address" (TODO(#15666 & #15118))
      await expect(
        vault.methods
          .redeem_private_to_private_exact(alice.getAddress(), alice.getAddress(), sharesRequested, minAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attempt redeeming with an invalid rate
      // TODO(#15666 & #15118): this test fails because the ivsk is currently needed for emitting a note, but the vault contract doesn't have one.
      sharesRequested = assetsAlice;
      minAssets = assetsAlice + 1;
      await expect(
        vault.methods
          .redeem_private_to_private_exact(alice.getAddress(), alice.getAddress(), sharesRequested, minAssets, 0)
          .send()
          .wait(),
      ).rejects.toThrow(/No public key registered for address/); // /app_logic_reverted/ /Underflow/
    }, 300_000);
  });
});
