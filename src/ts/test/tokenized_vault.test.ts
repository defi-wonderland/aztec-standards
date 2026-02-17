import {
  setupTestSuite,
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  expectTokenBalances,
  expectTransferEvents,
  PRIVATE_ADDRESS,
} from './utils.js';

import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
import { type ContractFunctionInteraction } from '@aztec/aztec.js/contracts';
import { type TxHash } from '@aztec/aztec.js/tx';

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
  ): Promise<TxHash> {
    const { nonce = 0, caller = from } = options;
    const transfer = asset.methods.transfer_public_to_public(from, vault.address, amount, nonce);
    await setPublicAuthWit(vault.address, transfer, from, wallet);
    const tx = await action.send({ from: caller });
    return tx.txHash;
  }

  async function callVaultWithPrivateAuthWit(
    action: ContractFunctionInteraction,
    from: AztecAddress,
    amount: number,
    options: { nonce?: number; caller?: AztecAddress } = {},
  ): Promise<TxHash> {
    const { nonce = 0, caller = from } = options;
    const transfer = asset.methods.transfer_private_to_public(from, vault.address, amount, nonce);
    const transferAuthWitness = await setPrivateAuthWit(vault.address, transfer, from, wallet);
    const tx = await action.with({ authWitnesses: [transferAuthWitness] }).send({ from: caller });
    return tx.txHash;
  }

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
        const mintAliceTx = await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice });
        await expectTransferEvents(mintAliceTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(initialAmount) },
        ]);
        const mintBobTx = await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });
        await expectTransferEvents(mintBobTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(initialAmount) },
        ]);

        // Alice deposits public assets, receives public shares
        // deposit_public_to_public: asset Transfer(from, vault, assets) + vault Transfer(0x0, to, shares)
        const depositTx = await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_public(alice, alice, assetsAlice, 0),
          alice,
          assetsAlice,
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: alice, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        const yieldTx = await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });
        await expectTransferEvents(yieldTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: vault.address, amount: BigInt(yieldAmount) },
        ]);

        // Bob issues public shares for public assets
        // issue_public_to_public: asset Transfer(from, vault, max_assets) + vault Transfer(0x0, to, shares) + optionally asset Transfer(vault, from, change)
        const issueTx = await callVaultWithPublicAuthWit(
          vault.methods.issue_public_to_public(bob, bob, sharesBob, assetsBob, 0),
          bob,
          assetsBob,
        );
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
        await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, sharesAlice, 0);
        await expectTokenBalances(vault, bob, sharesBob, 0);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws public assets by burning public shares
        // withdraw_public_to_public: vault Transfer(from, 0x0, shares) + asset Transfer(vault, to, assets)
        const maxWithdraw = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        const withdrawTx = await vault.methods
          .withdraw_public_to_public(alice, alice, maxWithdraw, 0)
          .send({ from: alice });
        const withdrawShares = BigInt(sharesAlice); // shares = convert_to_shares(maxWithdraw, ROUND_UP) = sharesAlice
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: alice, to: AztecAddress.ZERO, amount: withdrawShares },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for public assets
        // redeem_public_to_public: vault Transfer(from, 0x0, shares) + asset Transfer(vault, to, assets)
        const redeemTx = await vault.methods.redeem_public_to_public(bob, bob, sharesBob, 0).send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: bob, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(redeemTx.txHash, asset.address, [
          { from: vault.address, to: bob, amount: BigInt(assetsBob) },
        ]);

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
        // mint_to_private enqueues increase_total_supply_internal which emits Transfer(0x0, PRIVATE, amount)
        const mintAliceTx = await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await expectTransferEvents(mintAliceTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(initialAmount) },
        ]);
        const mintBobTx = await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });
        await expectTransferEvents(mintBobTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(initialAmount) },
        ]);

        // Alice deposits private assets, receives public shares
        // deposit_private_to_public: asset Transfer(PRIVATE, vault, assets) + vault Transfer(0x0, to, shares)
        const depositTx = await callVaultWithPrivateAuthWit(
          vault.methods.deposit_private_to_public(alice, alice, assetsAlice, 0),
          alice,
          assetsAlice,
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: PRIVATE_ADDRESS, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues public shares for private assets
        // issue_private_to_public_exact: asset Transfer(PRIVATE, vault, max_assets) + vault Transfer(0x0, to, shares)
        // + optionally asset Transfer(vault, PRIVATE, change) via commitment
        const issueTx = await callVaultWithPrivateAuthWit(
          vault.methods.issue_private_to_public_exact(bob, bob, sharesBob, assetsBob, 0),
          bob,
          assetsBob,
        );
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
        await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, sharesAlice, 0);
        await expectTokenBalances(vault, bob, sharesBob, 0);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning public shares
        // withdraw_public_to_private: vault Transfer(from, 0x0, shares) + asset Transfer(vault, PRIVATE, assets)
        const maxWithdraw = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        const withdrawTx = await vault.methods
          .withdraw_public_to_private(alice, alice, maxWithdraw, 0)
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: alice, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for private assets
        // redeem_public_to_private_exact: vault Transfer(from, 0x0, shares) + asset Transfer(vault, PRIVATE, min_assets)
        // + optionally asset Transfer(vault, PRIVATE, outstanding) via commitment
        const minAssets = assetsBob;
        const redeemTx = await vault.methods
          .redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0)
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: bob, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(redeemTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: BigInt(minAssets) },
        ]);

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

        // Alice deposits public assets, receives private shares
        // deposit_public_to_private: asset Transfer(from, vault, assets) + vault Transfer(0x0, PRIVATE, shares)
        const depositTx = await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_private(alice, alice, assetsAlice, sharesAlice, 0),
          alice,
          assetsAlice,
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: alice, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues private shares for public assets
        // issue_public_to_private: asset Transfer(from, vault, max_assets) + vault Transfer(0x0, PRIVATE, shares)
        // + optionally asset Transfer(vault, from, change)
        const issueTx = await callVaultWithPublicAuthWit(
          vault.methods.issue_public_to_private(bob, bob, sharesBob, assetsBob, 0),
          bob,
          assetsBob,
        );
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
        await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, sharesAlice);
        await expectTokenBalances(vault, bob, 0, sharesBob);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws public assets by burning private shares
        // withdraw_private_to_public_exact: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, to, assets)
        // + potentially vault commitment surplus (0 in this case since sharesAlice = exact)
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawTx = await vault.methods
          .withdraw_private_to_public_exact(alice, alice, maxWithdraw, sharesAlice, 0)
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for public assets
        // redeem_private_to_public: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, to, assets)
        const redeemTx = await vault.methods.redeem_private_to_public(bob, bob, sharesBob, 0).send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(redeemTx.txHash, asset.address, [
          { from: vault.address, to: bob, amount: BigInt(assetsBob) },
        ]);

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
        const mintAliceTx = await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });
        await expectTransferEvents(mintAliceTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(initialAmount) },
        ]);
        const mintBobTx = await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });
        await expectTransferEvents(mintBobTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(initialAmount) },
        ]);

        // Alice deposits private assets, receives private shares
        // deposit_private_to_private: asset Transfer(PRIVATE, vault, assets) + vault Transfer(0x0, PRIVATE, shares)
        const depositTx = await callVaultWithPrivateAuthWit(
          vault.methods.deposit_private_to_private(alice, alice, assetsAlice, sharesAlice, 0),
          alice,
          assetsAlice,
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: PRIVATE_ADDRESS, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues private shares for private assets
        // issue_private_to_private_exact: asset Transfer(PRIVATE, vault, max_assets) + vault Transfer(0x0, PRIVATE, shares)
        // + optionally asset Transfer(vault, PRIVATE, change) via commitment
        const issueTx = await callVaultWithPrivateAuthWit(
          vault.methods.issue_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0),
          bob,
          assetsBob,
        );
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
        await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, sharesAlice);
        await expectTokenBalances(vault, bob, 0, sharesBob);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning private shares
        // withdraw_private_to_private: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, PRIVATE, assets)
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawTx = await vault.methods
          .withdraw_private_to_private(alice, alice, maxWithdraw, sharesAlice, 0)
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for private assets
        // redeem_private_to_private_exact: vault Transfer(PRIVATE, 0x0, shares)
        // + optionally asset Transfer(vault, PRIVATE, outstanding_assets) via commitment
        const redeemTx = await vault.methods
          .redeem_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0)
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);

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

        // Alice deposits private assets, receives private shares (exact)
        // deposit_private_to_private_exact: asset Transfer(PRIVATE, vault, assets) + vault Transfer(0x0, PRIVATE, max_shares)
        const depositAliceTx = await callVaultWithPrivateAuthWit(
          vault.methods.deposit_private_to_private_exact(alice, alice, assetsAlice, sharesAlice, 0),
          alice,
          assetsAlice,
        );
        await expectTransferEvents(depositAliceTx, asset.address, [
          { from: PRIVATE_ADDRESS, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        // For the first deposit, max_shares = sharesAlice (since total_supply is 0)
        await expectTransferEvents(depositAliceTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob deposits public assets, receives private shares (exact)
        // deposit_public_to_private_exact: asset Transfer(from, vault, assets) + vault Transfer(0x0, PRIVATE, max_shares)
        const depositBobTx = await callVaultWithPublicAuthWit(
          vault.methods.deposit_public_to_private_exact(bob, bob, assetsBob, sharesBob, 0),
          bob,
          assetsBob,
        );
        await expectTransferEvents(depositBobTx, asset.address, [
          { from: bob, to: vault.address, amount: BigInt(assetsBob) },
        ]);
        // vault emits Transfer(0x0, PRIVATE, max_shares) where max_shares = convert_to_shares(assetsBob)
        // sharesBob was passed as min_shares; max_shares >= sharesBob

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
        await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(vault, alice, 0, sharesAlice);
        await expectTokenBalances(vault, bob, 0, sharesBob);
        expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning private shares (exact)
        // withdraw_private_to_private_exact: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, PRIVATE, assets)
        // + potentially vault commitment surplus
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawAliceTx = await vault.methods
          .withdraw_private_to_private_exact(alice, alice, maxWithdraw, sharesAlice, 0)
          .send({ from: alice });
        await expectTransferEvents(withdrawAliceTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawAliceTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob withdraws public assets by burning private shares (exact)
        // withdraw_private_to_public_exact: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, to, assets)
        // + potentially vault commitment surplus
        const withdrawBobTx = await vault.methods
          .withdraw_private_to_public_exact(bob, bob, assetsBob, sharesBob, 0)
          .send({ from: bob });
        await expectTransferEvents(withdrawBobTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(withdrawBobTx.txHash, asset.address, [
          { from: vault.address, to: bob, amount: BigInt(assetsBob) },
        ]);

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
        const depositTx = await callVaultWithPublicAuthWit(depositAction, alice, assetsAlice, { caller: carl });
        await expectTransferEvents(depositTx, asset.address, [
          { from: alice, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues public shares for public assets
        const issueAction = vault.methods.issue_public_to_public(bob, bob, sharesBob, assetsBob, 0);
        await setPublicAuthWit(carl, issueAction, bob, wallet);
        const issueTx = await callVaultWithPublicAuthWit(issueAction, bob, assetsBob, { caller: carl });
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

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
        const withdrawTx = await withdrawAction.send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: alice, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for public assets
        const redeemAction = vault.methods.redeem_public_to_public(bob, bob, sharesBob, 0);
        await setPublicAuthWit(carl, redeemAction, bob, wallet);
        const redeemTx = await redeemAction.send({ from: carl });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: bob, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(redeemTx.txHash, asset.address, [
          { from: vault.address, to: bob, amount: BigInt(assetsBob) },
        ]);

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
        const depositTx = await callVaultWithPrivateAuthWit(
          depositAction.with({ authWitnesses: [depositAuthWitness] }),
          alice,
          assetsAlice,
          { caller: carl },
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: PRIVATE_ADDRESS, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues public shares for private assets
        const issueAction = vault.methods.issue_private_to_public_exact(bob, bob, sharesBob, assetsBob, 0);
        const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob, wallet);
        const issueTx = await callVaultWithPrivateAuthWit(
          issueAction.with({ authWitnesses: [issueAuthWitness] }),
          bob,
          assetsBob,
          { caller: carl },
        );
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

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
        const withdrawTx = await vault.methods
          .withdraw_public_to_private(alice, alice, maxWithdraw, 0)
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: alice, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for private assets
        const minAssets = 15;
        const redeemTx = await vault.methods
          .redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0)
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: bob, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(redeemTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: BigInt(minAssets) },
        ]);

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

        // Alice deposits public assets, receives private shares
        const depositAction = vault.methods.deposit_public_to_private(alice, alice, assetsAlice, sharesAlice, 0);
        const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice, wallet);
        const depositTx = await callVaultWithPublicAuthWit(
          depositAction.with({ authWitnesses: [depositAuthWitness] }),
          alice,
          assetsAlice,
          { caller: carl },
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: alice, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues private shares for public assets
        const issueAction = vault.methods.issue_public_to_private(bob, bob, sharesBob, assetsBob, 0);
        const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob, wallet);
        const issueTx = await callVaultWithPublicAuthWit(
          issueAction.with({ authWitnesses: [issueAuthWitness] }),
          bob,
          assetsBob,
          { caller: carl },
        );
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

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

        // Alice withdraws public assets by burning private shares
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
        const withdrawTx = await withdrawAction.with({ authWitnesses: [withdrawAuthWitness] }).send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for public assets
        const redeemAction = vault.methods.redeem_private_to_public(bob, bob, sharesBob, 0);
        const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
        const redeemTx = await redeemAction.with({ authWitnesses: [redeemAuthWitness] }).send({ from: carl });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(redeemTx.txHash, asset.address, [
          { from: vault.address, to: bob, amount: BigInt(assetsBob) },
        ]);

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

        // Alice deposits private assets, receives private shares
        const depositAction = vault.methods.deposit_private_to_private(alice, alice, assetsAlice, sharesAlice, 0);
        const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice, wallet);
        const depositTx = await callVaultWithPrivateAuthWit(
          depositAction.with({ authWitnesses: [depositAuthWitness] }),
          alice,
          assetsAlice,
          { caller: carl },
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: PRIVATE_ADDRESS, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues private shares for private assets
        const issueAction = vault.methods.issue_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0);
        const issueAuthWitness = await setPrivateAuthWit(carl, issueAction, bob, wallet);
        const issueTx = await callVaultWithPrivateAuthWit(
          issueAction.with({ authWitnesses: [issueAuthWitness] }),
          bob,
          assetsBob,
          { caller: carl },
        );
        await expectTransferEvents(issueTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

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

        // Alice withdraws private assets by burning private shares
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawAction = vault.methods.withdraw_private_to_private(alice, alice, maxWithdraw, 9, 0);
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        const withdrawTx = await withdrawAction.with({ authWitnesses: [withdrawAuthWitness] }).send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for private assets
        const redeemAction = vault.methods.redeem_private_to_private_exact(bob, bob, sharesBob, 15, 0);
        const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
        const redeemTx = await redeemAction.with({ authWitnesses: [redeemAuthWitness] }).send({ from: carl });
        await expectTransferEvents(redeemTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);

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

        // Alice deposits private assets, receives private shares (exact)
        const depositAction = vault.methods.deposit_private_to_private_exact(alice, alice, assetsAlice, sharesAlice, 0);
        const depositAuthWitness = await setPrivateAuthWit(carl, depositAction, alice, wallet);
        const depositTx = await callVaultWithPrivateAuthWit(
          depositAction.with({ authWitnesses: [depositAuthWitness] }),
          alice,
          assetsAlice,
          { caller: carl },
        );
        await expectTransferEvents(depositTx, asset.address, [
          { from: PRIVATE_ADDRESS, to: vault.address, amount: BigInt(assetsAlice) },
        ]);
        await expectTransferEvents(depositTx, vault.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob deposits public assets, receives private shares (exact)
        const publicDepositAction = vault.methods.deposit_public_to_private_exact(bob, bob, assetsBob, sharesBob, 0);
        const publicDepositAuthWitness = await setPrivateAuthWit(carl, publicDepositAction, bob, wallet);
        const depositBobTx = await callVaultWithPublicAuthWit(
          publicDepositAction.with({ authWitnesses: [publicDepositAuthWitness] }),
          bob,
          assetsBob,
          { caller: carl },
        );
        await expectTransferEvents(depositBobTx, asset.address, [
          { from: bob, to: vault.address, amount: BigInt(assetsBob) },
        ]);

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

        // Alice withdraws private assets by burning private shares (exact)
        const maxRedeemPriv = await vault.methods.balance_of_private(alice).simulate({ from: alice });
        const maxWithdraw = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const withdrawAction = vault.methods.withdraw_private_to_private_exact(alice, alice, maxWithdraw, 9, 0);
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        const withdrawTx = await withdrawAction.with({ authWitnesses: [withdrawAuthWitness] }).send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob withdraws public assets by burning private shares (exact)
        const publicWithdrawAction = vault.methods.withdraw_private_to_public_exact(bob, bob, 15, sharesBob, 0);
        const publicWithdrawAuthWitness = await setPrivateAuthWit(carl, publicWithdrawAction, bob, wallet);
        const withdrawBobTx = await publicWithdrawAction
          .with({ authWitnesses: [publicWithdrawAuthWitness] })
          .send({ from: carl });
        await expectTransferEvents(withdrawBobTx.txHash, vault.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);
        await expectTransferEvents(withdrawBobTx.txHash, asset.address, [
          { from: vault.address, to: bob, amount: 15n },
        ]);

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
  });
});
