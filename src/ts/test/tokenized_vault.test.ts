import {
  setupTestSuite,
  deployVaultAndAssetWithMinter,
  deployVaultWithInitialDeposit,
  deployTokenWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  expectTokenBalances,
} from './utils.js';

import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
import { type ContractFunctionInteraction } from '@aztec/aztec.js/contracts';

import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';

import { TokenContract } from '../../../src/artifacts/Token.js';

const TEST_TIMEOUT = 300_000;

describe('Tokenized Vault', () => {
  let cleanup: () => Promise<void>;
  let wallet: TestWallet;
  let accounts: AztecAddress[];
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
    await action.send({ from: caller });
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
    await action.with({ authWitnesses: [transferAuthWitness] }).send({ from: caller });
  }

  async function callVaultWithPublicAuthWitFromWallet(
    vaultContract: TokenContract,
    assetContract: TokenContract,
    action: ContractFunctionInteraction,
    wallet: TestWallet,
    from: AztecAddress,
    amount: bigint,
  ) {
    const transfer = assetContract.methods.transfer_public_to_public(from, vaultContract.address, amount, 0);
    await setPublicAuthWit(vaultContract.address, transfer, from, wallet);
    await action.send({ from });
  }

  async function publicBalance(token: TokenContract, address: AztecAddress, reader: AztecAddress): Promise<bigint> {
    return token.methods.balance_of_public(address).simulate({ from: reader });
  }

  async function totalShares(vaultContract: TokenContract, reader: AztecAddress): Promise<bigint> {
    return vaultContract.methods.total_supply().simulate({ from: reader });
  }

  const scale = 1_000_000n; // 6 decimals

  beforeAll(async () => {
    ({ cleanup, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    [vault, asset] = (await deployVaultAndAssetWithMinter(wallet, alice)) as [TokenContract, TokenContract];
    // Alice is the minter of the asset contract and the one interacting with it to mint tokens.
  });

  afterAll(async () => {
    await cleanup();
  });

  describe('Successful interactions, no authwits.', () => {
    it(
      'Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });

        // Alice deposits public assets, receives public shares
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, assetsAlice, 0),
          alice,
          assetsAlice,
        );

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxWithdraw = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        await vault.methods.withdraw_public_to_public(alice, alice, maxWithdraw, 0).send({ from: alice });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        await vault.methods.redeem_public_to_public(bob, bob, sharesBob, 0).send({ from: bob });

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
        await expectTokenBalances(asset, bob, initialAmount, 0);
        await expectTokenBalances(asset, vault.address, dust, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, 0);
        await expectTokenBalances(vault, bob, 0, 0);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
      },
      TEST_TIMEOUT * 2,
    );

    it(
      'Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });

        // Alice deposits private assets, receives public shares
        await callVaultWithPrivateAuthWit(
          vault.methods.deposit_private_to_public(alice, alice, assetsAlice, 0),
          alice,
          assetsAlice,
        );

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxWithdraw = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        await vault.methods.withdraw_public_to_private(alice, alice, maxWithdraw, 0).send({ from: alice });

        // Bob redeems private shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        const minAssets = assetsBob;
        await vault.methods.redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0).send({ from: bob });

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
        await expectTokenBalances(asset, bob, 0, initialAmount);
        await expectTokenBalances(asset, vault.address, dust, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, 0);
        await expectTokenBalances(vault, bob, 0, 0);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    it(
      'Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });

        // Alice deposits public assets, receives public shares
        await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_private(alice, alice, assetsAlice, sharesAlice, 0),
          alice,
          assetsAlice,
        );

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        await vault.methods
          .withdraw_private_to_public_exact(alice, alice, maxWithdraw, sharesAlice, 0)
          .send({ from: alice });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        await vault.methods.redeem_private_to_public(bob, bob, sharesBob, 0).send({ from: bob });

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0);
        await expectTokenBalances(asset, bob, initialAmount, 0);
        await expectTokenBalances(asset, vault.address, dust, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, 0);
        await expectTokenBalances(vault, bob, 0, 0);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    it(
      'Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });

        // Alice deposits private assets, receives private shares
        await callVaultWithPrivateAuthWit(
          vault.methods.deposit_private_to_private(alice, alice, assetsAlice, sharesAlice, 0),
          alice,
          assetsAlice,
        );

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        await vault.methods
          .withdraw_private_to_private(alice, alice, maxWithdraw, sharesAlice, 0)
          .send({ from: alice });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        await vault.methods.redeem_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0).send({ from: bob });

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
        await expectTokenBalances(asset, bob, 0, initialAmount);
        await expectTokenBalances(asset, vault.address, dust, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, 0);
        await expectTokenBalances(vault, bob, 0, 0);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    it(
      'Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });

        // Alice deposits private assets, receives public shares
        await callVaultWithPrivateAuthWit(
          vault.methods.deposit_private_to_private_exact(alice, alice, assetsAlice, sharesAlice, 0),
          alice,
          assetsAlice,
        );

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        await vault.methods
          .withdraw_private_to_private_exact(alice, alice, maxWithdraw, sharesAlice, 0)
          .send({ from: alice });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        await vault.methods.withdraw_private_to_public_exact(bob, bob, assetsBob, sharesBob, 0).send({ from: bob });

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
        await expectTokenBalances(asset, bob, initialAmount, 0);
        await expectTokenBalances(asset, vault.address, dust, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, 0);
        await expectTokenBalances(vault, bob, 0, 0);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
      },
      TEST_TIMEOUT,
    );
  });

  describe('Successful interactions with authwits.', () => {
    // Carl exclusively interacts with the vault in this tests

    it(
      'Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });

        // Alice deposits public assets, receives public shares
        const depositAction = vault.methods.deposit_public_to_public(alice, alice, assetsAlice, 0);
        await setPublicAuthWit(carl, depositAction, alice, wallet);
        await callVaultWithPublicAuthWit(depositAction, alice, assetsAlice, { caller: carl });

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxWithdraw = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        const withdrawAction = vault.methods.withdraw_public_to_public(alice, alice, maxWithdraw, 0);
        await setPublicAuthWit(carl, withdrawAction, alice, wallet);
        await withdrawAction.send({ from: carl });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        const redeemAction = vault.methods.redeem_public_to_public(bob, bob, sharesBob, 0);
        await setPublicAuthWit(carl, redeemAction, bob, wallet);
        await redeemAction.send({ from: carl });

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
      },
      TEST_TIMEOUT,
    );

    it(
      'Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });

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
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxWithdraw = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        await vault.methods.withdraw_public_to_private(alice, alice, maxWithdraw, 0).send({ from: alice });

        // Bob redeems private shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        const minAssets = 15;
        await vault.methods.redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0).send({ from: bob });

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
      },
      TEST_TIMEOUT,
    );

    it(
      'Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });

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
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawAction = vault.methods.withdraw_private_to_public_exact(
          alice,
          alice,
          maxWithdraw,
          sharesAlice,
          0,
        );
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        await withdrawAction.with({ authWitnesses: [withdrawAuthWitness] }).send({ from: carl });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        const redeemAction = vault.methods.redeem_private_to_public(bob, bob, sharesBob, 0);
        const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
        await redeemAction.with({ authWitnesses: [redeemAuthWitness] }).send({ from: carl });

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
      },
      TEST_TIMEOUT,
    );

    it(
      'Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });

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
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawAction = vault.methods.withdraw_private_to_private(alice, alice, maxWithdraw, 9, 0);
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        await withdrawAction.with({ authWitnesses: [withdrawAuthWitness] }).send({ from: carl });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        const redeemAction = vault.methods.redeem_private_to_private_exact(bob, bob, sharesBob, 15, 0);
        const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
        await redeemAction.with({ authWitnesses: [redeemAuthWitness] }).send({ from: carl });

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
      },
      TEST_TIMEOUT,
    );

    it(
      'Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });

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
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

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
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawAction = vault.methods.withdraw_private_to_private_exact(alice, alice, maxWithdraw, 9, 0);
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        await withdrawAction.with({ authWitnesses: [withdrawAuthWitness] }).send({ from: carl });

        // Bob redeems public shares for public assets
        // Bob should get 15 asset tokens back, 1 token remains in the vault
        const publicWithdrawAction = vault.methods.withdraw_private_to_public_exact(bob, bob, 15, sharesBob, 0);
        const publicWithdrawAuthWitness = await setPrivateAuthWit(carl, publicWithdrawAction, bob, wallet);
        await publicWithdrawAction.with({ authWitnesses: [publicWithdrawAuthWitness] }).send({ from: carl });

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
      },
      TEST_TIMEOUT,
    );

    describe('Inflation attacks', () => {
      it(
        'attack succeeds when vault deployed with initial deposit = 0',
        async () => {
          // Deploy vault with initial deposit = 0 (no protection)
          const initialDeposit = 0n;
          const vaultContract = await deployVaultWithInitialDeposit(wallet, alice, asset, initialDeposit, alice);

          const attacker = bob;
          const victim = carl;

          // Fund attacker and victim
          await asset.methods.mint_to_public(attacker, 20_000n * scale).send({ from: alice });
          await asset.methods.mint_to_public(victim, 20_000n * scale).send({ from: alice });

          const attackerStart = await publicBalance(asset, attacker, attacker);

          // Vault starts with 0 assets
          expect(await publicBalance(asset, vaultContract.address, attacker)).toBe(0n);

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
            asset,
            attackerDepositAction,
            wallet,
            attacker,
            attackerAssetsToSend,
          );

          const supplyAfterAttacker = await totalShares(vaultContract, attacker);
          expect(supplyAfterAttacker).toBe(1n);

          const vaultAfterAttacker = await publicBalance(asset, vaultContract.address, attacker);
          expect(vaultAfterAttacker).toBe(attackerAssetsToSend);

          // 2) Victim deposits just below threshold to get 0 shares
          // threshold for 1 share = (totalAssets + 1) / (totalSupply + 1) = (A+1)/2
          const currentVaultAssets = await publicBalance(asset, vaultContract.address, attacker);
          const thresholdForOneShare = (currentVaultAssets + 1n) / 2n;
          // In this case thresholdForOneShare is 500_000_000 = (1000*scale + 2) / 2
          const victimDepositAmount = thresholdForOneShare - 1n;

          // 3) Victim deposits
          const numberOfVictims = 8;
          let totalVictimDeposits = 0n;
          const victimBeforeDeposits: bigint = await publicBalance(asset, victim, victim);
          for (let i = 0; i < numberOfVictims; i++) {
            const victimDepositAction = vaultContract
              .withWallet(wallet)
              .methods.deposit_public_to_public(victim, victim, victimDepositAmount, 0);
            await callVaultWithPublicAuthWitFromWallet(
              vaultContract,
              asset,
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

          const victimAfterDeposits: bigint = await publicBalance(asset, victim, victim);
          expect(victimBeforeDeposits - victimAfterDeposits).toBe(totalVictimDeposits);

          const vaultAfterVictim = await publicBalance(asset, vaultContract.address, attacker);
          expect(vaultAfterVictim).toBe(attackerAssetsToSend + totalVictimDeposits);

          // 4) Attacker redeems their 1 private share
          await vaultContract.methods.redeem_private_to_public(attacker, attacker, 1n, 0).send({ from: attacker });

          const supplyAfterRedeem = await totalShares(vaultContract, attacker);
          expect(supplyAfterRedeem).toBe(0n);

          const strandedAssets = await publicBalance(asset, vaultContract.address, attacker);
          expect(strandedAssets).toBeGreaterThan(0n);

          const attackerFinal = await publicBalance(asset, attacker, attacker);
          const attackerNet = attackerFinal - attackerStart;

          // Attacker profits from victim's deposit!
          expect(attackerNet).toBeGreaterThan(0n);
        },
        TEST_TIMEOUT * 2,
      );

      it(
        'attack fails when vault deployed with initial deposit > 0 (only 5 wei initial deposit)',
        async () => {
          // Deploy asset contract with alice as minter
          const assetContract = (await deployTokenWithMinter(wallet, alice)) as TokenContract;

          // Initial deposit creates locked shares that dilute any manipulation
          const initialDeposit = 5n;
          await assetContract.methods.mint_to_public(alice, initialDeposit).send({ from: alice });
          const vaultContract = await deployVaultWithInitialDeposit(
            wallet,
            alice,
            assetContract,
            initialDeposit,
            alice,
          );

          const attacker = bob;
          const victim = carl;

          // Fund attacker and victim
          await assetContract.methods.mint_to_public(attacker, 20_000n * scale).send({ from: alice });
          await assetContract.methods.mint_to_public(victim, 20_000n * scale).send({ from: alice });

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
          await vaultContract.methods.redeem_private_to_public(attacker, attacker, 1n, 0).send({ from: attacker });

          const supplyAfterRedeem = await totalShares(vaultContract, attacker);
          expect(supplyAfterRedeem).toBeGreaterThan(0n);

          const strandedAssets = await publicBalance(assetContract, vaultContract.address, attacker);
          expect(strandedAssets).toBeGreaterThan(0n);

          const attackerFinal = await publicBalance(assetContract, attacker, attacker);
          const attackerNet = attackerFinal - attackerStart;

          // Attacker profits from victim's deposit!
          expect(attackerNet).toBeLessThanOrEqual(0n);
        },
        TEST_TIMEOUT * 2,
      );
    });
  });
});
