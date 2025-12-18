import {
  setupTestSuite,
  deployVaultAndAssetWithMinter,
  deployVaultWithInitialDeposit,
  setPrivateAuthWit,
  setPublicAuthWit,
  expectTokenBalances,
  deployTokenWithMinter,
} from './utils.js';

import { type PXE } from '@aztec/pxe/server';
const { Fr } = await import('@aztec/aztec.js/fields');
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
const { Contract } = await import('@aztec/aztec.js/contracts');
import { type AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import { type ContractFunctionInteraction } from '@aztec/aztec.js/contracts';
const { TokenContractArtifact } = await import('../../../artifacts/Token.js');

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
    amount: number | bigint,
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

  async function callVaultWithPublicAuthWitFromWallet(
    vault: TokenContract,
    asset: TokenContract,
    action: ContractFunctionInteraction,
    wallet: TestWallet,
    from: AztecAddress,
    amount: number | bigint,
    options: { nonce?: number; caller?: AztecAddress } = {},
  ) {
    const { nonce = 0, caller = from } = options;
    const transfer = asset.methods.transfer_public_to_public(from, vault.address, amount, nonce);
    await setPublicAuthWit(vault.address, transfer, from, wallet);
    await action.send({ from: caller }).wait();
  }

  function publicBalance(token: TokenContract, address: AztecAddress, reader: AztecAddress): Promise<bigint> {
    return token.methods.balance_of_public(address).simulate({ from: reader });
  }

  function totalShares(vaultContract: TokenContract, reader: AztecAddress): Promise<bigint> {
    return vaultContract.methods.total_supply().simulate({ from: reader });
  }

  const scale = 1_000_000n; // 6 decimals

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

  describe('Constructor with asset and initial deposit', () => {
    let assetContract: TokenContract;
    let initialDeposit: bigint = 1000n;

    beforeEach(async () => {
      // Deploy asset contract first
      assetContract = (await deployTokenWithMinter(wallet, alice)) as TokenContract;

      // Mint assets to deployer (alice) before deploying the vault
      await assetContract.methods.mint_to_public(alice, initialDeposit).send({ from: alice }).wait();
    });

    it('deploys vault with initial deposit successfully', async () => {
      // Verify alice has the assets
      await expectTokenBalances(assetContract, alice, initialDeposit, 0);

      // Deploy vault with initial deposit - this requires authwit to be set up before deployment
      const vaultWithDeposit = await deployVaultWithInitialDeposit(wallet, alice, assetContract, initialDeposit, alice);

      // Verify assets were transferred to vault during constructor
      await expectTokenBalances(assetContract, vaultWithDeposit.address, initialDeposit, 0, alice);

      // Verify alice no longer has the assets
      await expectTokenBalances(assetContract, alice, 0, 0);

      // Verify shares are locked in the vault
      // Initial deposit at 1:1 ratio means vault gets `initialDeposit` shares
      await expectTokenBalances(vaultWithDeposit, vaultWithDeposit.address, initialDeposit, 0, alice);

      // Verify alice has no shares
      await expectTokenBalances(vaultWithDeposit, alice, 0, 0);

      // Verify total supply equals locked shares
      const totalSupply = await vaultWithDeposit.methods.total_supply().simulate({ from: alice });
      expect(totalSupply).toBe(initialDeposit);
    }, 400_000);

    it('deploys vault with initial deposit successfully with different depositor', async () => {
      // Mint assets to depositor (bob) before deploying the vault
      const initialDeposit = 1000n;
      await assetContract.methods.mint_to_public(bob, initialDeposit).send({ from: alice }).wait();

      // Verify bob has the assets
      await expectTokenBalances(assetContract, bob, initialDeposit, 0);

      // Deploy vault with initial deposit - this requires authwit to be set up before deployment
      const vaultWithDeposit = await deployVaultWithInitialDeposit(wallet, alice, assetContract, initialDeposit, bob);

      // Verify assets were transferred to vault during constructor
      await expectTokenBalances(assetContract, vaultWithDeposit.address, initialDeposit, 0, bob);

      // Verify bob no longer has the assets
      await expectTokenBalances(assetContract, bob, 0, 0);

      // Verify shares are locked in the vault
      // Initial deposit at 1:1 ratio means vault gets `initialDeposit` shares
      await expectTokenBalances(vaultWithDeposit, vaultWithDeposit.address, initialDeposit, 0, bob);

      // Verify bob has no shares
      await expectTokenBalances(vaultWithDeposit, bob, 0, 0);

      // Verify total supply equals locked shares
      const totalSupply = await vaultWithDeposit.methods.total_supply().simulate({ from: bob });
      expect(totalSupply).toBe(initialDeposit);
    }, 400_000);

    it('subsequent depositor receives proportional shares', async () => {
      // Deploy vault with initial deposit
      const vaultWithDeposit = await deployVaultWithInitialDeposit(wallet, alice, assetContract, initialDeposit, alice);

      // Now Bob wants to deposit
      const bobDeposit = 500n;
      await assetContract.methods.mint_to_public(bob, bobDeposit).send({ from: alice }).wait();

      // Authorize vault to use Bob's assets
      const transfer = assetContract.methods.transfer_public_to_public(bob, vaultWithDeposit.address, bobDeposit, 0);
      await setPublicAuthWit(vaultWithDeposit.address, transfer, bob, wallet);

      // Bob deposits
      await vaultWithDeposit.methods.deposit_public_to_public(bob, bob, bobDeposit, 0).send({ from: bob }).wait();

      // Bob should receive shares proportional to his deposit
      // Since initial deposit established 1:1 ratio, Bob should get bobDeposit shares
      await expectTokenBalances(vaultWithDeposit, bob, bobDeposit, 0);

      // Vault's locked shares remain unchanged
      await expectTokenBalances(vaultWithDeposit, vaultWithDeposit.address, initialDeposit, 0, alice);

      // Total supply = initial locked shares + Bob's shares
      const totalSupply = await vaultWithDeposit.methods.total_supply().simulate({ from: alice });
      expect(totalSupply).toBe(initialDeposit + bobDeposit);
    }, 300_000);

    it('vault with initial deposit handles yield correctly', async () => {
      // Deploy vault with initial deposit
      const vaultWithDeposit = await deployVaultWithInitialDeposit(wallet, alice, assetContract, initialDeposit, alice);

      // Bob deposits same amount
      const bobDeposit = 1000n;
      await assetContract.methods.mint_to_public(bob, bobDeposit).send({ from: alice }).wait();

      const transfer = assetContract.methods.transfer_public_to_public(bob, vaultWithDeposit.address, bobDeposit, 0);
      await setPublicAuthWit(vaultWithDeposit.address, transfer, bob, wallet);
      await vaultWithDeposit.methods.deposit_public_to_public(bob, bob, bobDeposit, 0).send({ from: bob }).wait();

      // Simulate yield by minting assets directly to vault
      const yieldAmount = 200n;
      await assetContract.methods.mint_to_public(vaultWithDeposit.address, yieldAmount).send({ from: alice }).wait();

      // Now Bob redeems his shares
      await vaultWithDeposit.methods.redeem_public_to_public(bob, bob, bobDeposit, 0).send({ from: bob }).wait();

      // Bob should have received more than he deposited due to yield
      const bobAssets = await assetContract.methods.balance_of_public(bob).simulate({ from: bob });
      expect(bobAssets).toBeGreaterThan(bobDeposit);

      // Locked shares remain unchanged
      await expectTokenBalances(vaultWithDeposit, vaultWithDeposit.address, initialDeposit, 0, alice);
    }, 300_000);

    it('fails deployment without authwit', async () => {
      const constructorArgs = [
        'VaultToken',
        'VT',
        6,
        assetContract.address,
        AztecAddress.ZERO, // AztecAddress.ZERO
        initialDeposit,
        alice,
        0,
      ];

      await expect(
        Contract.deploy(wallet, TokenContractArtifact, constructorArgs, 'constructor_with_asset_initial_deposit')
          .send({ contractAddressSalt: Fr.random(), from: alice })
          .deployed(),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    it('fails deployment with insufficient balance', async () => {
      // This is bigger than what's originally minted to alice, becoming insufficient for the deployment
      const biggerInitialDeposit = initialDeposit + 1n;

      // Try to deploy vault - should fail due to insufficient balance
      await expect(
        deployVaultWithInitialDeposit(wallet, alice, assetContract, biggerInitialDeposit, alice),
      ).rejects.toThrow(/app_logic_reverted/);
    }, 300_000);

    describe('Inflation attacks', () => {
      it('attack succeeds when vault deployed with initial deposit = 0', async () => {
        // Deploy vault with initial deposit = 0 (no protection)
        const initialDeposit = 0n;
        const vaultContract = await deployVaultWithInitialDeposit(wallet, alice, assetContract, initialDeposit, alice);

        const attacker = bob;
        const victim = carl;

        // Fund attacker and victim
        await assetContract.methods
          .mint_to_public(attacker, 20_000n * scale)
          .send({ from: alice })
          .wait();
        await assetContract.methods
          .mint_to_public(victim, 20_000n * scale)
          .send({ from: alice })
          .wait();

        const attackerStart = await publicBalance(assetContract, attacker, attacker);

        // Vault starts with 0 assets
        expect(await publicBalance(assetContract, vaultContract.address, attacker)).toBe(0n);

        // 1) Attacker: one-step donate + mint 1 share using deposit_public_to_private
        // Sends donationAmount + 1 assets but requests only 1 share (excess becomes donation)
        const donationAmount = 1000n * scale;
        const attackerAssetsToSend = donationAmount + 1n;
        const attackerDepositAction = vaultContract.withWallet(wallet).methods.deposit_public_to_private(
          attacker,
          attacker,
          attackerAssetsToSend,
          1n, // shares requested
          0,
        );

        await callVaultWithPublicAuthWitFromWallet(
          vaultContract,
          assetContract,
          attackerDepositAction,
          wallet,
          attacker,
          attackerAssetsToSend,
        );

        const supplyAfterAttacker = await totalShares(vaultContract, attacker);
        expect(supplyAfterAttacker).toBe(1n);

        const vaultAfterAttacker = await publicBalance(assetContract, vaultContract.address, attacker);
        expect(vaultAfterAttacker).toBe(attackerAssetsToSend);

        // 2) Victim deposits just below threshold to get 0 shares
        // threshold for 1 share = (totalAssets + 1) / (totalSupply + 1) = (A+1)/2
        const currentVaultAssets = await publicBalance(assetContract, vaultContract.address, attacker);
        const thresholdForOneShare = (currentVaultAssets + 1n) / 2n;
        // In this case thresholdForOneShare is 500_000_000 = (1000*scale + 2) / 2
        const victimDepositAmount = thresholdForOneShare - 1n;

        // 3) Victim deposits
        const numberOfVictims = 8;
        let totalVictimDeposits = 0n;
        const victimBeforeDeposits: bigint = await publicBalance(assetContract, victim, victim);
        for (let i = 0; i < numberOfVictims; i++) {
          const victimDepositAction = vaultContract
            .withWallet(wallet)
            .methods.deposit_public_to_public(victim, victim, victimDepositAmount, 0);
          await callVaultWithPublicAuthWitFromWallet(
            vaultContract,
            assetContract,
            victimDepositAction,
            wallet,
            victim,
            victimDepositAmount,
          );
          totalVictimDeposits += victimDepositAmount;
        }

        // Victim gets 0 shares
        const victimShares = await publicBalance(vaultContract, victim, victim);
        expect(victimShares).toBe(0n);

        const supplyAfterVictim = await totalShares(vaultContract, attacker);
        expect(supplyAfterVictim).toBe(1n); // Still only attacker's 1 share

        const victimAfterDeposits: bigint = await publicBalance(assetContract, victim, victim);
        expect(victimBeforeDeposits - victimAfterDeposits).toBe(totalVictimDeposits);

        const vaultAfterVictim = await publicBalance(assetContract, vaultContract.address, attacker);
        expect(vaultAfterVictim).toBe(attackerAssetsToSend + totalVictimDeposits);

        // 4) Attacker redeems their 1 private share
        await vaultContract.methods.redeem_private_to_public(attacker, attacker, 1n, 0).send({ from: attacker }).wait();

        const supplyAfterRedeem = await totalShares(vaultContract, attacker);
        expect(supplyAfterRedeem).toBe(0n);

        const strandedAssets = await publicBalance(assetContract, vaultContract.address, attacker);
        expect(strandedAssets).toBeGreaterThan(0n);

        const attackerFinal = await publicBalance(assetContract, attacker, attacker);
        const attackerNet = attackerFinal - attackerStart;

        // Attacker profits from victim's deposit!
        expect(attackerNet).toBeGreaterThan(0n);
      }, 400_000);

      it('attack fails when vault deployed with initial deposit > 0 (only 5 wei initial deposit)', async () => {
        // Deploy asset contract with alice as minter
        const assetContract = (await deployTokenWithMinter(wallet, alice)) as TokenContract;

        // Initial deposit creates locked shares that dilute any manipulation
        const initialDeposit = 5n;
        await assetContract.methods.mint_to_public(alice, initialDeposit).send({ from: alice }).wait();
        const vaultContract = await deployVaultWithInitialDeposit(wallet, alice, assetContract, initialDeposit, alice);

        const attacker = bob;
        const victim = carl;

        // Fund attacker and victim
        await assetContract.methods
          .mint_to_public(attacker, 20_000n * scale)
          .send({ from: alice })
          .wait();
        await assetContract.methods
          .mint_to_public(victim, 20_000n * scale)
          .send({ from: alice })
          .wait();

        const attackerStart = await publicBalance(assetContract, attacker, attacker);

        // Vault starts with initial deposit
        expect(await publicBalance(assetContract, vaultContract.address, attacker)).toBe(initialDeposit);
        expect(await totalShares(vaultContract, attacker)).toBe(initialDeposit);

        // 1) Attacker attempts the SAME donation as without protection
        const donationAmount = 1000n * scale; // Same as first test
        const attackerAssetsToSend = donationAmount + 1n;
        const attackerDepositAction = vaultContract.withWallet(wallet).methods.deposit_public_to_private(
          attacker,
          attacker,
          attackerAssetsToSend,
          1n, // shares requested
          0,
        );

        await callVaultWithPublicAuthWitFromWallet(
          vaultContract,
          assetContract,
          attackerDepositAction,
          wallet,
          attacker,
          attackerAssetsToSend,
        );

        const supplyAfterAttacker = await totalShares(vaultContract, attacker);
        // expect(supplyAfterAttacker).toBe(1n);

        const vaultAfterAttacker = await publicBalance(assetContract, vaultContract.address, attacker);
        // expect(vaultAfterAttacker).toBe(attackerAssetsToSend);

        // 2) Victim deposits just below threshold to get 0 shares
        // We keep the same deposit as before
        const victimDepositAmount = 500n * scale - 1n;

        // 3) Victim deposits
        const numberOfVictims = 8;
        let totalVictimDeposits = 0n;
        const victimBeforeDeposits: bigint = await publicBalance(assetContract, victim, victim);
        for (let i = 0; i < numberOfVictims; i++) {
          const victimDepositAction = vaultContract
            .withWallet(wallet)
            .methods.deposit_public_to_public(victim, victim, victimDepositAmount, 0);
          await callVaultWithPublicAuthWitFromWallet(
            vaultContract,
            assetContract,
            victimDepositAction,
            wallet,
            victim,
            victimDepositAmount,
          );
          totalVictimDeposits += victimDepositAmount;
        }

        // Victim gets shares (attack should fail to grief them)
        const victimShares = await publicBalance(vaultContract, victim, victim);
        expect(victimShares).toBeGreaterThan(0n);

        const supplyAfterVictim = await totalShares(vaultContract, attacker);
        expect(supplyAfterVictim).toBeGreaterThan(supplyAfterAttacker);
        expect(supplyAfterVictim - supplyAfterAttacker).toBe(victimShares);

        const victimAfterDeposits: bigint = await publicBalance(assetContract, victim, victim);
        expect(victimBeforeDeposits - victimAfterDeposits).toBe(totalVictimDeposits);

        const vaultAfterVictim = await publicBalance(assetContract, vaultContract.address, attacker);
        expect(vaultAfterVictim - vaultAfterAttacker).toBe(totalVictimDeposits);

        // 4) Attacker redeems their 1 private share
        await vaultContract.methods.redeem_private_to_public(attacker, attacker, 1n, 0).send({ from: attacker }).wait();

        const supplyAfterRedeem = await totalShares(vaultContract, attacker);
        expect(supplyAfterRedeem).toBeGreaterThan(0n);

        const strandedAssets = await publicBalance(assetContract, vaultContract.address, attacker);
        expect(strandedAssets).toBeGreaterThan(0n);

        const attackerFinal = await publicBalance(assetContract, attacker, attacker);
        const attackerNet = attackerFinal - attackerStart;

        // Attacker profits from victim's deposit!
        expect(attackerNet).toBeLessThanOrEqual(0n);
      }, 400_000);
    });
  });
});
