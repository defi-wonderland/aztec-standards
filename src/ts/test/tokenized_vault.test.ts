import {
  setupTestSuite,
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  expectTokenBalances,
  MAX_U128_VALUE,
} from './utils.js';

import { type PXE } from '@aztec/pxe/server';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
import { type AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import { type ContractFunctionInteraction } from '@aztec/aztec.js/contracts';

import { TokenContract } from '../../../artifacts/Token.js';

describe('Tokenized Vault', () => {
  let pxe: PXE;
  let store: AztecLMDBStoreV2;
  let wallet: TestWallet;
  let accounts: AztecAddress[];
  let deployer: AztecAddress;
  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;
  let vault: TokenContract;
  let asset: TokenContract;

  const initialAmount = 100;
  const assetsAlice = 9; // Assets Alice wants to deposit
  const sharesAlice = assetsAlice; // The first deposit receives 1 share for each asset.
  const yieldAmount = 5;
  const sharesBob = 10; // Shares Bob wants to get issued
  const assetsBob = 15; // Bob needs to provide assets = sharesBob * (assetsAlice + yieldAmount + 1) / (sharesAlice + 1);
  const aliceEarnings = 4; // Due to rounding, alice doesn't get the 5 assets received as yield by the vault, just 4.
  const dust = 1; // 1 asset is left in the vault

  async function callVaultWithPublicAuthWit(
    action: ContractFunctionInteraction,
    from: AztecAddress,
    amount: number,
    options: { nonce?: number; caller?: AztecAddress } = {},
  ) {
    const { nonce = 0, caller = from } = options;
    const transfer = asset.methods.transfer_public_to_public(from, vault.address, amount, nonce);
    await setPublicAuthWit(vault.address, transfer, from, wallet);
    await action.send({ from: caller }).wait();
  }

  async function callVaultWithPrivateAuthWit(
    action: ContractFunctionInteraction,
    from: AztecAddress,
    amount: number,
    options: { nonce?: number; caller?: AztecAddress } = {},
  ) {
    const { nonce = 0, caller = from } = options;
    const transfer = asset.methods.transfer_private_to_public(from, vault.address, amount, nonce);
    const transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, from, wallet);
    await action
      .with({ authWitnesses: [transferAuthWitness] })
      .send({ from: caller })
      .wait();
  }

  async function mintAndDepositInPrivate(account: AztecAddress, mint: number, assets: number, shares: number) {
    // Mint some assets to Alice
    await asset.methods.mint_to_private(account, mint).send({ from: alice }).wait();

    // Alice deposits private assets, receives private shares
    await callVaultWithPrivateAuthWit(
      vault.methods.deposit_private_to_private(account, account, assets, shares, 0),
      account,
      assets,
    );
  }

  async function mintAndDepositInPublic(account: AztecAddress, mint: number, assets: number) {
    // Mint some assets to Alice
    await asset.methods.mint_to_public(account, mint).send({ from: alice }).wait();

    // Alice deposits public assets, receives public shares
    await callVaultWithPublicAuthWit(
      vault.methods.deposit_public_to_public(account, account, assets, 0),
      account,
      assets,
    );
  }

  beforeAll(async () => {
    ({ pxe, store, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    [vault, asset] = (await deployVaultAndAssetWithMinter(wallet, alice)) as [TokenContract, TokenContract];
    // Alice is the minter of the asset contract and the one interacting with it to mint tokens.
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('Successful interactions, no authwits.', () => {
    it('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits public assets, receives public shares
      await callVaultWithPublicAuthWit(
        vault.methods.deposit_public_to_public(alice, alice, assetsAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      await callVaultWithPublicAuthWit(
        vault.methods.issue_public_to_public(bob, bob, sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = assetsAlice + aliceEarnings;
      await vault.methods.withdraw_public_to_public(alice, alice, maxWithdraw, 0).send({ from: alice }).wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      await vault.methods.redeem_public_to_public(bob, bob, sharesBob, 0).send({ from: bob }).wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
    }, 300_000);

    it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits private assets, receives public shares
      await callVaultWithPrivateAuthWit(
        vault.methods.deposit_private_to_public(alice, alice, assetsAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      await callVaultWithPrivateAuthWit(
        vault.methods.issue_private_to_public_exact(bob, bob, sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws private assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = assetsAlice + aliceEarnings;
      await vault.methods.withdraw_public_to_private(alice, alice, maxWithdraw, 0).send({ from: alice }).wait();

      // Bob redeems private shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const minAssets = assetsBob;
      await vault.methods.redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0).send({ from: bob }).wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      await expectTokenBalances(asset, bob, 0, initialAmount);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
    }, 300_000);

    it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits public assets, receives public shares
      await callVaultWithPublicAuthWit(
        vault.methods.deposit_public_to_private(alice, alice, assetsAlice, sharesAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      await callVaultWithPublicAuthWit(
        vault.methods.issue_public_to_private(bob, bob, sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = assetsAlice + aliceEarnings;
      await vault.methods
        .withdraw_private_to_public_exact(alice, alice, maxWithdraw, sharesAlice, 0)
        .send({ from: alice })
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      await vault.methods.redeem_private_to_public(bob, bob, sharesBob, 0).send({ from: bob }).wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
    }, 300_000);

    it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits private assets, receives private shares
      await callVaultWithPrivateAuthWit(
        vault.methods.deposit_private_to_private(alice, alice, assetsAlice, sharesAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues private shares for private assets
      await callVaultWithPrivateAuthWit(
        vault.methods.issue_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = assetsAlice + aliceEarnings;
      await vault.methods
        .withdraw_private_to_private(alice, alice, maxWithdraw, sharesAlice, 0)
        .send({ from: alice })
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      await vault.methods.redeem_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0).send({ from: bob }).wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      await expectTokenBalances(asset, bob, 0, initialAmount);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
    }, 300_000);

    it('Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits private assets, receives public shares
      await callVaultWithPrivateAuthWit(
        vault.methods.deposit_private_to_private_exact(alice, alice, assetsAlice, sharesAlice, 0),
        alice,
        assetsAlice,
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      await callVaultWithPublicAuthWit(
        vault.methods.deposit_public_to_private_exact(bob, bob, assetsBob, sharesBob, 0),
        bob,
        assetsBob,
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = assetsAlice + aliceEarnings;
      await vault.methods
        .withdraw_private_to_private_exact(alice, alice, maxWithdraw, sharesAlice, 0)
        .send({ from: alice })
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      await vault.methods
        .withdraw_private_to_public_exact(bob, bob, assetsBob, sharesBob, 0)
        .send({ from: bob })
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
    }, 300_000);
  });

  describe('Successful interactions with authwits.', () => {
    // Carl exclusively interacts with the vault in this tests

    it('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits public assets, receives public shares
      const depositAction = vault.methods.deposit_public_to_public(alice, alice, assetsAlice, 0);
      await setPublicAuthWit(carl, depositAction, alice, wallet);
      await callVaultWithPublicAuthWit(depositAction, alice, assetsAlice, { caller: carl });

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_public_to_public(bob, bob, sharesBob, assetsBob, 0);
      await setPublicAuthWit(carl, issueAction, bob, wallet);
      await callVaultWithPublicAuthWit(issueAction, bob, assetsBob, { caller: carl });

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      const withdrawAction = vault.methods.withdraw_public_to_public(alice, alice, maxWithdraw, 0);
      await setPublicAuthWit(carl, withdrawAction, alice, wallet);
      await withdrawAction.send({ from: carl }).wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const redeemAction = vault.methods.redeem_public_to_public(bob, bob, sharesBob, 0);
      await setPublicAuthWit(carl, redeemAction, bob, wallet);
      await redeemAction.send({ from: carl }).wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(0n);
    }, 300_000);

    it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits private assets, receives public shares
      const depositAction = vault.methods.deposit_private_to_public(alice, alice, assetsAlice, 0);
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice, wallet);
      await callVaultWithPrivateAuthWit(
        depositAction.with({ authWitnesses: [depositAuthWitness] }),
        alice,
        assetsAlice,
        { caller: carl },
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_private_to_public_exact(bob, bob, sharesBob, assetsBob, 0);
      const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob, wallet);
      await callVaultWithPrivateAuthWit(issueAction.with({ authWitnesses: [issueAuthWitness] }), bob, assetsBob, {
        caller: carl,
      });

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, sharesAlice, 0);
      await expectTokenBalances(vault, bob, sharesBob, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws private assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      await vault.methods.withdraw_public_to_private(alice, alice, maxWithdraw, 0).send({ from: alice }).wait();

      // Bob redeems private shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const minAssets = 15;
      await vault.methods.redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0).send({ from: bob }).wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      await expectTokenBalances(asset, bob, 0, initialAmount);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(0n);
      await expectTokenBalances(vault, carl, 0, 0);
    }, 300_000);

    it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits public assets, receives public shares
      const depositAction = vault.methods.deposit_public_to_private(alice, alice, assetsAlice, sharesAlice, 0);
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice, wallet);
      await callVaultWithPublicAuthWit(
        depositAction.with({ authWitnesses: [depositAuthWitness] }),
        alice,
        assetsAlice,
        { caller: carl },
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_public_to_private(bob, bob, sharesBob, assetsBob, 0);
      const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob, wallet);
      await callVaultWithPublicAuthWit(issueAction.with({ authWitnesses: [issueAuthWitness] }), bob, assetsBob, {
        caller: carl,
      });

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      const withdrawAction = vault.methods.withdraw_private_to_public_exact(alice, alice, maxWithdraw, sharesAlice, 0);
      const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
      await withdrawAction
        .with({ authWitnesses: [withdrawAuthWitness] })
        .send({ from: carl })
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const redeemAction = vault.methods.redeem_private_to_public(bob, bob, sharesBob, 0);
      const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
      await redeemAction
        .with({ authWitnesses: [redeemAuthWitness] })
        .send({ from: carl })
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(0n);
    }, 300_000);

    it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits private assets, receives public shares
      const depositAction = vault.methods.deposit_private_to_private(alice, alice, assetsAlice, sharesAlice, 0);
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice, wallet);
      await callVaultWithPrivateAuthWit(
        depositAction.with({ authWitnesses: [depositAuthWitness] }),
        alice,
        assetsAlice,
        { caller: carl },
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      const issueAction = vault.methods.issue_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0);
      const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob, wallet);
      await callVaultWithPrivateAuthWit(issueAction.with({ authWitnesses: [issueAuthWitness] }), bob, assetsBob, {
        caller: carl,
      });

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      const withdrawAction = vault.methods.withdraw_private_to_private(alice, alice, maxWithdraw, 9, 0);
      const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
      await withdrawAction
        .with({ authWitnesses: [withdrawAuthWitness] })
        .send({ from: carl })
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const redeemAction = vault.methods.redeem_private_to_private_exact(bob, bob, sharesBob, 15, 0);
      const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
      await redeemAction
        .with({ authWitnesses: [redeemAuthWitness] })
        .send({ from: carl })
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      await expectTokenBalances(asset, bob, 0, initialAmount);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(0n);
    }, 300_000);

    it('Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();
      await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice }).wait();

      // Alice deposits private assets, receives public shares
      const depositAction = vault.methods.deposit_private_to_private_exact(alice, alice, assetsAlice, sharesAlice, 0);
      const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice, wallet);
      await callVaultWithPrivateAuthWit(
        depositAction.with({ authWitnesses: [depositAuthWitness] }),
        alice,
        assetsAlice,
        { caller: carl },
      );

      // Simulate yield: mint assets to vault
      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

      // Bob issues public shares for public assets
      const publicDepositAction = vault.methods.deposit_public_to_private_exact(bob, bob, assetsBob, sharesBob, 0);
      const publicDepositAuthWitness = await setPrivateAuthWit(carl, publicDepositAction, bob, wallet);
      await callVaultWithPublicAuthWit(
        publicDepositAction.with({ authWitnesses: [publicDepositAuthWitness] }),
        bob,
        assetsBob,
        { caller: carl },
      );

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, sharesAlice);
      await expectTokenBalances(vault, bob, 0, sharesBob);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(BigInt(sharesBob + sharesAlice));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      const withdrawAction = vault.methods.withdraw_private_to_private_exact(alice, alice, maxWithdraw, 9, 0);
      const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
      await withdrawAction
        .with({ authWitnesses: [withdrawAuthWitness] })
        .send({ from: carl })
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      const publicWithdrawAction = vault.methods.withdraw_private_to_public_exact(bob, bob, 15, sharesBob, 0);
      const publicWithdrawAuthWitness = await setPrivateAuthWit(carl, publicWithdrawAction, bob, wallet);
      await publicWithdrawAction
        .with({ authWitnesses: [publicWithdrawAuthWitness] })
        .send({ from: carl })
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
      await expectTokenBalances(asset, bob, initialAmount, 0);
      await expectTokenBalances(asset, vault.address, dust, 0, alice);
      await expectTokenBalances(asset, carl, 0, 0);
      // Check shares balances
      await expectTokenBalances(vault, alice, 0, 0);
      await expectTokenBalances(vault, bob, 0, 0);
      await expectTokenBalances(vault, carl, 0, 0);
      expect(await vault.methods.total_supply().simulate({ from: carl })).toBe(0n);
    }, 300_000);
  });

  describe('Deposit failures: incorrect amounts', () => {
    // Alice exclusively interacts with the vault in this tests

    it('deposit_public_to_public', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let transfer = asset.methods.transfer_public_to_public(alice, vault.address, initialAmount + 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_public_to_public(alice, alice, initialAmount + 1, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, assetsAlice - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods.deposit_public_to_public(alice, alice, assetsAlice, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('deposit_public_to_private', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice, vault.address, initialAmount + 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_public_to_private(alice, alice, initialAmount + 1, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, assetsAlice - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_public_to_private(alice, alice, assetsAlice, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, assetsAlice, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_public_to_private(alice, alice, assetsAlice, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Too many shares requested
    }, 300_000);

    it('deposit_private_to_public', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let transfer = asset.methods.transfer_private_to_public(alice, vault.address, initialAmount + 1, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_public(alice, alice, initialAmount + 1, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, assetsAlice - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_public(alice, alice, assetsAlice, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);
    }, 300_000);

    it('deposit_private_to_private', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice, vault.address, initialAmount + 1, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_private(alice, alice, initialAmount + 1, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, assetsAlice - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_private(alice, alice, assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, assetsAlice, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_private(alice, alice, assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Too many shares requested
    }, 300_000);

    it('deposit_public_to_private_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice, vault.address, initialAmount + 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_public_to_private_exact(alice, alice, initialAmount + 1, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, assetsAlice - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_public_to_private_exact(alice, alice, assetsAlice, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, assetsAlice, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_public_to_private_exact(alice, alice, assetsAlice, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('deposit_private_to_private_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice, vault.address, initialAmount + 1, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_private_exact(alice, alice, initialAmount + 1, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, assetsAlice - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_private_exact(alice, alice, assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, assetsAlice, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .deposit_private_to_private_exact(alice, alice, assetsAlice, sharesRequested, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);
  });

  describe('Issue failures: incorrect amounts', () => {
    // Alice exclusively interacts with the vault in this tests

    it('issue_public_to_public', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice, vault.address, maxAssets, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods.issue_public_to_public(alice, alice, sharesRequested, maxAssets, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, maxAssets - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods.issue_public_to_public(alice, alice, sharesRequested, maxAssets, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('issue_public_to_private', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_public_to_public(alice, vault.address, maxAssets, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods.issue_public_to_private(alice, alice, sharesRequested, maxAssets, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, maxAssets - 1, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods.issue_public_to_private(alice, alice, sharesRequested, maxAssets, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_public_to_public(alice, vault.address, maxAssets, 0);
      await setPublicAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods.issue_public_to_private(alice, alice, sharesRequested, maxAssets, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('issue_private_to_public_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice, vault.address, maxAssets, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .issue_private_to_public_exact(alice, alice, sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, maxAssets - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .issue_private_to_public_exact(alice, alice, sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, maxAssets, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .issue_private_to_public_exact(alice, alice, sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('issue_private_to_private_exact', async () => {
      // Mint some assets to Alice
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice }).wait();

      // Attempt depositing more assets than Alice actually has
      let sharesRequested = initialAmount + 1;
      let maxAssets = initialAmount + 1;
      let transfer = asset.methods.transfer_private_to_public(alice, vault.address, maxAssets, 0);
      let transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .issue_private_to_private_exact(alice, alice, sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attemp to deposit with an incorrect allowance
      sharesRequested = assetsAlice;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, maxAssets - 1, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .issue_private_to_private_exact(alice, alice, sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Unknown auth witness for message hash /);

      // Attemp to request more shares than allowed for the given deposit
      sharesRequested = assetsAlice + 1;
      maxAssets = assetsAlice;
      transfer = asset.methods.transfer_private_to_public(alice, vault.address, maxAssets, 0);
      transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, alice, wallet);
      await expect(
        vault.methods
          .issue_private_to_private_exact(alice, alice, sharesRequested, maxAssets, 0)
          .with({ authWitnesses: [transferAuthWitness] })
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);
  });

  describe('Withdraw failures: incorrect amounts', () => {
    // Alice exclusively interacts with the vault in this tests

    it('withdraw_public_to_public', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt withdrawing more assets than allowed
      await expect(
        vault.methods
          .withdraw_public_to_public(alice, alice, assetsAlice + 1, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('withdraw_public_to_private', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt withdrawing more assets than allowed
      await expect(
        vault.methods
          .withdraw_public_to_private(alice, alice, assetsAlice + 1, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('withdraw_private_to_private', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt withdrawing more assets than allowed
      let sharesRequested = assetsAlice;
      await expect(
        vault.methods
          .withdraw_private_to_private(alice, alice, assetsAlice + 1, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attempt burning more shares than Alice actually has
      sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods
          .withdraw_private_to_private(alice, alice, assetsAlice, sharesRequested, 0)
          .send({ from: alice })
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
          .withdraw_private_to_public_exact(alice, alice, assetsAlice + 1, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // /Underflow/

      // Attempt burning more shares than Alice actually has
      sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods
          .withdraw_private_to_public_exact(alice, alice, assetsAlice, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);
    }, 300_000);

    it('withdraw_private_to_private_exact', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt withdrawing more assets than allowed
      let sharesRequested = assetsAlice;
      await expect(
        vault.methods
          .withdraw_private_to_private_exact(alice, alice, assetsAlice + 1, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);

      // Attempt burning more shares than Alice actually has
      sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods
          .withdraw_private_to_private_exact(alice, alice, assetsAlice, sharesRequested, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);
    }, 300_000);
  });

  describe('Redeem failures: incorrect amounts', () => {
    // Alice exclusively interacts with the vault in this tests

    it('redeem_public_to_public', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods.redeem_public_to_public(alice, alice, sharesRequested, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/app_logic_reverted/); // Underflow
    }, 300_000);

    it('redeem_public_to_private_exact', async () => {
      // Mint some assets to Alice in public and deposit to public shares.
      await mintAndDepositInPublic(alice, initialAmount, assetsAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      let minAssets = 1;
      await expect(
        vault.methods
          .redeem_public_to_private_exact(alice, alice, sharesRequested, minAssets, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/); // /Underflow/

      // Attempt redeeming with an invalid rate
      sharesRequested = assetsAlice;
      minAssets = assetsAlice + 1;
      await expect(
        vault.methods
          .redeem_public_to_private_exact(alice, alice, sharesRequested, minAssets, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('redeem_private_to_public', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      await expect(
        vault.methods.redeem_private_to_public(alice, alice, sharesRequested, 0).send({ from: alice }).wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);
    }, 300_000);

    it('redeem_private_to_private_exact', async () => {
      // Mint some assets to Alice in private and deposit to private shares.
      await mintAndDepositInPrivate(alice, initialAmount, assetsAlice, sharesAlice);

      // Attempt redeeming more shares than Alice actually has
      let sharesRequested = assetsAlice + 1;
      let minAssets = 1;
      await expect(
        vault.methods
          .redeem_private_to_private_exact(alice, alice, sharesRequested, minAssets, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/Assertion failed: Balance too low 'subtracted > 0'/);

      // Attempt redeeming with an invalid rate
      sharesRequested = assetsAlice;
      minAssets = assetsAlice + 1;
      await expect(
        vault.methods
          .redeem_private_to_private_exact(alice, alice, sharesRequested, minAssets, 0)
          .send({ from: alice })
          .wait(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);
  });

  describe('View Functions', () => {
    describe('with empty vault', () => {
      it('asset returns correct address', async () => {
        const returnedAsset = await vault.methods.asset().simulate({ from: alice });
        expect(returnedAsset.toString()).toBe(asset.address.toString());
      });

      it('totalAssets returns zero', async () => {
        const totalAssets = await vault.methods.totalAssets().simulate({ from: alice });
        expect(totalAssets).toBe(0n);
      });

      it('maxDeposit and maxIssue return MAX_U128_VALUE for any address', async () => {
        const maxDepositAlice = await vault.methods.maxDeposit(alice).simulate({ from: alice });
        expect(maxDepositAlice).toBe(MAX_U128_VALUE);

        const maxDepositBob = await vault.methods.maxDeposit(bob).simulate({ from: alice });
        expect(maxDepositBob).toBe(MAX_U128_VALUE);

        const maxIssueAlice = await vault.methods.maxIssue(alice).simulate({ from: alice });
        expect(maxIssueAlice).toBe(MAX_U128_VALUE);

        const maxIssueBob = await vault.methods.maxIssue(bob).simulate({ from: alice });
        expect(maxIssueBob).toBe(MAX_U128_VALUE);
      });

      it('maxWithdraw and maxRedeem return zero without shares', async () => {
        const maxWithdraw = await vault.methods.maxWithdraw(alice).simulate({ from: alice });
        expect(maxWithdraw).toBe(0n);

        const maxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });
        expect(maxRedeem).toBe(0n);
      });

      it('convert and preview functions handle zero amounts', async () => {
        const convertToShares = await vault.methods.convertToShares(0).simulate({ from: alice });
        expect(convertToShares).toBe(0n);

        const convertToAssets = await vault.methods.convertToAssets(0).simulate({ from: alice });
        expect(convertToAssets).toBe(0n);

        const previewDeposit = await vault.methods.previewDeposit(0).simulate({ from: alice });
        expect(previewDeposit).toBe(0n);

        const previewIssue = await vault.methods.previewIssue(0).simulate({ from: alice });
        expect(previewIssue).toBe(0n);

        const previewWithdraw = await vault.methods.previewWithdraw(0).simulate({ from: alice });
        expect(previewWithdraw).toBe(0n);

        const previewRedeem = await vault.methods.previewRedeem(0).simulate({ from: alice });
        expect(previewRedeem).toBe(0n);
      });

      it('previewIssue returns 1:1 ratio at initial state', async () => {
        const sharesToIssue = 1000;
        const previewAssets = await vault.methods.previewIssue(sharesToIssue).simulate({ from: alice });
        expect(previewAssets).toBe(BigInt(sharesToIssue));
      });
    });

    describe('with single deposit (1:1 ratio)', () => {
      const depositAmount = 1000;

      beforeEach(async () => {
        await asset.methods.mint_to_public(alice, depositAmount).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, depositAmount, 0),
          alice,
          depositAmount,
        );
      });

      it('totalAssets returns deposited amount', async () => {
        const totalAssets = await vault.methods.totalAssets().simulate({ from: alice });
        expect(totalAssets).toBe(BigInt(depositAmount));
      });

      it('conversion functions return 1:1 ratio', async () => {
        const testAmount = 500;

        const shares = await vault.methods.convertToShares(testAmount).simulate({ from: alice });
        expect(shares).toBe(BigInt(testAmount));

        const assets = await vault.methods.convertToAssets(testAmount).simulate({ from: alice });
        expect(assets).toBe(BigInt(testAmount));
      });

      it('preview functions return 1:1 ratio', async () => {
        const testAmount = depositAmount;

        const previewWithdraw = await vault.methods.previewWithdraw(testAmount).simulate({ from: alice });
        expect(previewWithdraw).toBe(BigInt(testAmount));

        const previewRedeem = await vault.methods.previewRedeem(testAmount).simulate({ from: alice });
        expect(previewRedeem).toBe(BigInt(testAmount));
      });

      it('max functions reflect public balance at 1:1', async () => {
        const maxWithdraw = await vault.methods.maxWithdraw(alice).simulate({ from: alice });
        expect(maxWithdraw).toBe(BigInt(depositAmount));

        const maxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });
        expect(maxRedeem).toBe(BigInt(depositAmount));
      });

      it('previewDeposit matches actual deposit', async () => {
        const additionalDeposit = 500;

        // Preview before deposit
        const previewShares = await vault.methods.previewDeposit(additionalDeposit).simulate({ from: alice });

        // Actually deposit more
        await asset.methods.mint_to_public(alice, additionalDeposit).send({ from: alice }).wait();
        const beforeBalance = await vault.methods.balance_of_public(alice).simulate({ from: alice });
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, additionalDeposit, 0),
          alice,
          additionalDeposit,
        );
        const afterBalance = await vault.methods.balance_of_public(alice).simulate({ from: alice });

        expect(afterBalance - beforeBalance).toBe(previewShares);
      });

      it('previewRedeem matches actual redemption', async () => {
        const sharesToRedeem = depositAmount;
        const previewAssets = await vault.methods.previewRedeem(sharesToRedeem).simulate({ from: alice });

        // Actually redeem
        await vault.methods.redeem_public_to_public(alice, bob, sharesToRedeem, 0).send({ from: alice }).wait();

        // Check bob received the previewed amount
        const bobBalance = await asset.methods.balance_of_public(bob).simulate({ from: alice });
        expect(bobBalance).toBe(previewAssets);
      });

      it('maxRedeem updates after redemption', async () => {
        const redeemAmount = 500;
        const initialMaxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });

        // Redeem half
        await vault.methods.redeem_public_to_public(alice, alice, redeemAmount, 0).send({ from: alice }).wait();

        const finalMaxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });
        expect(finalMaxRedeem).toBe(initialMaxRedeem - BigInt(redeemAmount));
      });
    });

    describe('with yield accrued', () => {
      const depositAmount = 1000;
      const yieldAmount = 1000;

      beforeEach(async () => {
        // Deposit first
        await asset.methods.mint_to_public(alice, depositAmount).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, depositAmount, 0),
          alice,
          depositAmount,
        );
        // Add yield (doubling assets)
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();
      });

      it('totalAssets includes yield', async () => {
        const totalAssets = await vault.methods.totalAssets().simulate({ from: alice });
        expect(totalAssets).toBe(BigInt(depositAmount + yieldAmount));
      });

      it('convertToShares returns fewer shares (each share worth more)', async () => {
        const assetsToConvert = 2000;
        const shares = await vault.methods.convertToShares(assetsToConvert).simulate({ from: alice });
        // After yield, each share is worth ~2 assets, so fewer shares per asset
        expect(shares).toBeLessThan(BigInt(assetsToConvert));
      });

      it('convertToAssets returns more assets (each share worth more)', async () => {
        const sharesToConvert = 1000;
        const assets = await vault.methods.convertToAssets(sharesToConvert).simulate({ from: alice });
        // After yield, each share is worth ~2 assets
        expect(assets).toBeGreaterThan(BigInt(sharesToConvert));
      });

      it('maxWithdraw increases with yield', async () => {
        // maxWithdraw should now be greater than initial deposit
        const maxWithdraw = await vault.methods.maxWithdraw(alice).simulate({ from: alice });
        expect(maxWithdraw).toBeGreaterThan(BigInt(depositAmount));
      });

      it('previewWithdraw returns fewer shares after yield', async () => {
        // Want to withdraw deposit + 1 asset of yield
        const assetsToWithdraw = depositAmount + 1;
        const previewShares = await vault.methods.previewWithdraw(assetsToWithdraw).simulate({ from: alice });
        // Should need roughly half the shares (since each share worth ~2 assets)
        expect(previewShares).toBeLessThan(BigInt(assetsToWithdraw));
      });

      it('previewRedeem returns more assets after yield', async () => {
        const sharesToRedeem = depositAmount;
        const previewAssets = await vault.methods.previewRedeem(sharesToRedeem).simulate({ from: alice });
        // Should get back more than deposit due to yield
        expect(previewAssets).toBeGreaterThan(BigInt(depositAmount));
      });
    });

    describe('with yield affecting issue rate', () => {
      it('previewDeposit accounts for yield when calculating shares', async () => {
        const depositAmount = 1000;
        const yieldAmount = 1;

        // Add yield to vault first (changes initial rate)
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

        // Preview deposit
        const previewShares = await vault.methods.previewDeposit(depositAmount).simulate({ from: alice });

        // With yield present, should get fewer shares (rate is ~1:2)
        const expectedShares = depositAmount / 2;
        expect(previewShares).toBe(BigInt(expectedShares));
      });

      it('previewIssue returns more assets after yield', async () => {
        const yieldAmount = 1;

        // Add yield to establish rate
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice }).wait();

        const sharesToIssue = 500;
        const previewAssets = await vault.methods.previewIssue(sharesToIssue).simulate({ from: alice });

        // With yield, each share costs more assets (rate is ~1:2)
        expect(previewAssets).toBe(BigInt(1000));
      });
    });

    describe('private vs public balance behavior', () => {
      it('maxWithdraw returns zero when the balance exists exclusively in private form', async () => {
        const depositAmount = assetsAlice;
        const sharesAmount = sharesAlice;

        // Deposit to private shares
        await asset.methods.mint_to_public(alice, depositAmount).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_private(alice, alice, depositAmount, sharesAmount, 0),
          alice,
          depositAmount,
        );

        // maxWithdraw considers public balance, not private
        const maxWithdraw = await vault.methods.maxWithdraw(alice).simulate({ from: alice });
        expect(maxWithdraw).toBe(0n);
      });

      it('maxRedeem returns zero when the balance exists exclusively in private form', async () => {
        const depositAmount = assetsAlice;
        const sharesAmount = sharesAlice;

        // Deposit to private shares
        await asset.methods.mint_to_public(alice, depositAmount).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_private(alice, alice, depositAmount, sharesAmount, 0),
          alice,
          depositAmount,
        );

        // maxRedeem considers public balance, not private
        const maxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });
        expect(maxRedeem).toBe(0n);
      });
    });

    describe('multi-user scenarios', () => {
      it('maxRedeem differs per owner', async () => {
        const aliceDeposit = 1000;
        const bobDeposit = 500;

        // Alice deposits
        await asset.methods.mint_to_public(alice, aliceDeposit).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, aliceDeposit, 0),
          alice,
          aliceDeposit,
        );

        // Bob deposits
        await asset.methods.mint_to_public(bob, bobDeposit).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(bob, bob, bobDeposit, 0),
          bob,
          bobDeposit,
        );

        const maxRedeemAlice = await vault.methods.maxRedeem(alice).simulate({ from: alice });
        const maxRedeemBob = await vault.methods.maxRedeem(bob).simulate({ from: alice });

        expect(maxRedeemAlice).not.toBe(maxRedeemBob);
        expect(maxRedeemAlice).toBe(BigInt(aliceDeposit));
        expect(maxRedeemBob).toBe(BigInt(bobDeposit));
      });
    });
  });

  describe('Utility View Functions', () => {
    describe('maxRedeemPrivate', () => {
      it('returns zero without shares', async () => {
        const maxRedeemPrivate = await vault.methods.maxRedeemPrivate(alice).simulate({ from: alice });
        expect(maxRedeemPrivate).toBe(0n);
      });

      it('returns zero when the shares exist exclusively in public form', async () => {
        const depositAmount = 1000;

        await asset.methods.mint_to_public(alice, depositAmount).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, depositAmount, 0),
          alice,
          depositAmount,
        );

        const maxRedeemPrivate = await vault.methods.maxRedeemPrivate(alice).simulate({ from: alice });
        const maxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });

        expect(maxRedeemPrivate).toBe(0n);
        expect(maxRedeem).toBe(BigInt(depositAmount));
      });

      it('returns private shares when private balance exists', async () => {
        const depositAmount = assetsAlice;
        const sharesAmount = sharesAlice;

        await asset.methods.mint_to_public(alice, depositAmount).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_private(alice, alice, depositAmount, sharesAmount, 0),
          alice,
          depositAmount,
        );

        const maxRedeemPrivate = await vault.methods.maxRedeemPrivate(alice).simulate({ from: alice });
        const maxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });

        expect(maxRedeemPrivate).toBe(BigInt(sharesAmount));
        expect(maxRedeem).toBe(0n);
      });

      it('returns private shares when both exist', async () => {
        const publicDeposit = 1000;
        const privateDeposit = assetsAlice;
        const privateShares = sharesAlice;

        // Deposit to public
        await asset.methods.mint_to_public(alice, publicDeposit).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, publicDeposit, 0),
          alice,
          publicDeposit,
        );

        // Deposit to private
        await asset.methods.mint_to_public(alice, privateDeposit).send({ from: alice }).wait();
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_private(alice, alice, privateDeposit, privateShares, 0),
          alice,
          privateDeposit,
        );

        const maxRedeemPrivate = await vault.methods.maxRedeemPrivate(alice).simulate({ from: alice });
        const maxRedeem = await vault.methods.maxRedeem(alice).simulate({ from: alice });

        expect(maxRedeemPrivate).toBe(BigInt(privateShares));
        expect(maxRedeem).toBe(BigInt(publicDeposit));
      });
    });
  });
});
