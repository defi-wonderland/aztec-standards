import {
  setupTestSuite,
  ensureVaultContractClassPublished,
  deployVaultAndAssetWithMinter,
  deployVaultWithInitialDeposit,
  deployTokenWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  expectTokenBalances,
  expectTransferEvents,
  PRIVATE_ADDRESS,
} from './utils.js';

import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type EmbeddedWallet } from '@aztec/wallets/embedded';
import { type ContractFunctionInteraction } from '@aztec/aztec.js/contracts';
import { type TxHash } from '@aztec/aztec.js/tx';

import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';

import { TokenContract } from '../../../src/artifacts/Token.js';
import { VaultContract } from '../../../src/artifacts/Vault.js';
const TEST_TIMEOUT = 300_000;

describe('Vault', () => {
  let cleanup: () => Promise<void>;
  let wallet: EmbeddedWallet;
  let accounts: AztecAddress[];
  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;
  let vault: VaultContract;
  let asset: TokenContract;
  let shares: TokenContract;

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
    const { receipt } = await action.send({ from: caller });
    return receipt.txHash;
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
    const { receipt } = await action.with({ authWitnesses: [transferAuthWitness] }).send({ from: caller });
    return receipt.txHash;
  }

  async function callVaultWithPublicAuthWitFromWallet(
    vaultContract: VaultContract,
    assetContract: TokenContract,
    action: ContractFunctionInteraction,
    wallet: EmbeddedWallet,
    from: AztecAddress,
    amount: bigint,
  ) {
    const transfer = assetContract.methods.transfer_public_to_public(from, vaultContract.address, amount, 0);
    await setPublicAuthWit(vaultContract.address, transfer, from, wallet);
    await action.send({ from });
  }

  /** Authorize vault to burn public shares from `from` on the shares token */
  async function authorizeBurnPublic(from: AztecAddress, amount: number | bigint) {
    const burn = shares.methods.burn_public(from, amount, 0);
    await setPublicAuthWit(vault.address, burn, from, wallet);
  }

  /** Authorize vault to burn private shares from `from` on the shares token */
  async function authorizeBurnPrivate(from: AztecAddress, amount: number | bigint) {
    const burn = shares.methods.burn_private(from, amount, 0);
    return setPrivateAuthWit(vault.address, burn, from, wallet);
  }

  async function publicBalance(token: TokenContract, address: AztecAddress, reader: AztecAddress): Promise<bigint> {
    return (await token.methods.balance_of_public(address).simulate({ from: reader })).result;
  }

  async function totalShares(sharesContract: TokenContract, reader: AztecAddress): Promise<bigint> {
    return (await sharesContract.methods.total_supply().simulate({ from: reader })).result;
  }

  const scale = 1_000_000n; // 6 decimals

  beforeAll(async () => {
    ({ cleanup, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;

    await ensureVaultContractClassPublished(wallet, alice);
  });

  beforeEach(async () => {
    [vault, asset, shares] = await deployVaultAndAssetWithMinter(wallet, alice);
  });

  afterAll(async () => {
    await cleanup();
  });

  describe('Successful interactions, no authwits.', () => {
    it(
      'Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        const { receipt: mintAliceTx } = await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice });
        await expectTransferEvents(mintAliceTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(initialAmount) },
        ]);
        const { receipt: mintBobTx } = await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });
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
        await expectTransferEvents(depositTx, shares.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        const { receipt: yieldTx } = await asset.methods
          .mint_to_public(vault.address, yieldAmount)
          .send({ from: alice });
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
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
        await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(shares, alice, sharesAlice, 0);
        await expectTokenBalances(shares, bob, sharesBob, 0);
        expect(await totalShares(shares, alice)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws public assets by burning public shares
        // withdraw_public_to_public: vault Transfer(from, 0x0, shares) + asset Transfer(vault, to, assets)
        const { result: maxWithdraw } = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        await authorizeBurnPublic(alice, maxWithdraw > 0n ? sharesAlice : 0);
        const { receipt: withdrawTx } = await vault.methods
          .withdraw_public_to_public(alice, alice, maxWithdraw, 0)
          .send({ from: alice });
        const withdrawShares = BigInt(sharesAlice); // shares = convert_to_shares(maxWithdraw, ROUND_UP) = sharesAlice
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: alice, to: AztecAddress.ZERO, amount: withdrawShares },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for public assets
        // redeem_public_to_public: vault Transfer(from, 0x0, shares) + asset Transfer(vault, to, assets)
        await authorizeBurnPublic(bob, sharesBob);
        const { receipt: redeemTx } = await vault.methods
          .redeem_public_to_public(bob, bob, sharesBob, 0)
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        expect(await totalShares(shares, alice)).toBe(0n);
      },
      TEST_TIMEOUT * 2,
    );

    it(
      'Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        // mint_to_private enqueues increase_total_supply_internal which emits Transfer(0x0, PRIVATE, amount)
        const { receipt: mintAliceTx } = await asset.methods
          .mint_to_private(alice, initialAmount)
          .send({ from: alice });
        await expectTransferEvents(mintAliceTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(initialAmount) },
        ]);
        const { receipt: mintBobTx } = await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });
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
        await expectTransferEvents(depositTx, shares.address, [
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
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
        await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(shares, alice, sharesAlice, 0);
        await expectTokenBalances(shares, bob, sharesBob, 0);
        expect(await totalShares(shares, alice)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning public shares
        // withdraw_public_to_private: vault Transfer(from, 0x0, shares) + asset Transfer(vault, PRIVATE, assets)
        const { result: maxWithdraw } = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        await authorizeBurnPublic(alice, sharesAlice);
        const { receipt: withdrawTx } = await vault.methods
          .withdraw_public_to_private(alice, alice, maxWithdraw, 0)
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: alice, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for private assets
        // redeem_public_to_private_exact: vault Transfer(from, 0x0, shares) + asset Transfer(vault, PRIVATE, min_assets)
        // + optionally asset Transfer(vault, PRIVATE, outstanding) via commitment
        const minAssets = assetsBob;
        await authorizeBurnPublic(bob, sharesBob);
        const { receipt: redeemTx } = await vault.methods
          .redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0)
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        expect(await totalShares(shares, alice)).toBe(0n);
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
        await expectTransferEvents(depositTx, shares.address, [
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
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
        await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(shares, alice, 0, sharesAlice);
        await expectTokenBalances(shares, bob, 0, sharesBob);
        expect(await totalShares(shares, alice)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws public assets by burning private shares
        // withdraw_private_to_public_exact: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, to, assets)
        // + potentially vault commitment surplus (0 in this case since sharesAlice = exact)
        const { result: maxRedeemPriv } = await shares.methods.balance_of_private(alice).simulate({ from: alice });
        const { result: maxWithdraw } = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const burnAuthWit = await authorizeBurnPrivate(alice, sharesAlice);
        const { receipt: withdrawTx } = await vault.methods
          .withdraw_private_to_public_exact(alice, alice, maxWithdraw, sharesAlice, 0)
          .with({ authWitnesses: [burnAuthWit] })
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for public assets
        // redeem_private_to_public: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, to, assets)
        const burnAuthWitBob = await authorizeBurnPrivate(bob, sharesBob);
        const { receipt: redeemTx } = await vault.methods
          .redeem_private_to_public(bob, bob, sharesBob, 0)
          .with({ authWitnesses: [burnAuthWitBob] })
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        expect(await totalShares(shares, alice)).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    it(
      'Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems',
      async () => {
        // Mint some assets to Alice and Bob for deposit/issue
        const { receipt: mintAliceTx } = await asset.methods
          .mint_to_private(alice, initialAmount)
          .send({ from: alice });
        await expectTransferEvents(mintAliceTx.txHash, asset.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(initialAmount) },
        ]);
        const { receipt: mintBobTx } = await asset.methods.mint_to_private(bob, initialAmount).send({ from: alice });
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
        await expectTransferEvents(depositTx, shares.address, [
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
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
        await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        // Check shares balances
        await expectTokenBalances(shares, alice, 0, sharesAlice);
        await expectTokenBalances(shares, bob, 0, sharesBob);
        expect(await totalShares(shares, alice)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning private shares
        // withdraw_private_to_private: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, PRIVATE, assets)
        const { result: maxRedeemPriv } = await shares.methods.balance_of_private(alice).simulate({ from: alice });
        const { result: maxWithdraw } = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const burnAuthWit = await authorizeBurnPrivate(alice, sharesAlice);
        const { receipt: withdrawTx } = await vault.methods
          .withdraw_private_to_private(alice, alice, maxWithdraw, sharesAlice, 0)
          .with({ authWitnesses: [burnAuthWit] })
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for private assets
        // redeem_private_to_private_exact: vault Transfer(PRIVATE, 0x0, shares)
        // + optionally asset Transfer(vault, PRIVATE, outstanding_assets) via commitment
        const burnAuthWitBob = await authorizeBurnPrivate(bob, sharesBob);
        const { receipt: redeemTx } = await vault.methods
          .redeem_private_to_private_exact(bob, bob, sharesBob, assetsBob, 0)
          .with({ authWitnesses: [burnAuthWitBob] })
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
        await expectTokenBalances(asset, bob, 0, initialAmount);
        await expectTokenBalances(asset, vault.address, dust, 0, alice);
        // Check shares balances
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        expect(await totalShares(shares, alice)).toBe(0n);
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
        await expectTransferEvents(depositAliceTx, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, sharesAlice);
        await expectTokenBalances(shares, bob, 0, sharesBob);
        expect(await totalShares(shares, alice)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning private shares (exact)
        // withdraw_private_to_private_exact: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, PRIVATE, assets)
        // + potentially vault commitment surplus
        const { result: maxRedeemPriv } = await shares.methods.balance_of_private(alice).simulate({ from: alice });
        const { result: maxWithdraw } = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const burnAuthWit = await authorizeBurnPrivate(alice, sharesAlice);
        const { receipt: withdrawAliceTx } = await vault.methods
          .withdraw_private_to_private_exact(alice, alice, maxWithdraw, sharesAlice, 0)
          .with({ authWitnesses: [burnAuthWit] })
          .send({ from: alice });
        await expectTransferEvents(withdrawAliceTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawAliceTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob withdraws public assets by burning private shares (exact)
        // withdraw_private_to_public_exact: vault Transfer(PRIVATE, 0x0, shares) + asset Transfer(vault, to, assets)
        // + potentially vault commitment surplus
        const burnAuthWitBob = await authorizeBurnPrivate(bob, sharesBob);
        const { receipt: withdrawBobTx } = await vault.methods
          .withdraw_private_to_public_exact(bob, bob, assetsBob, sharesBob, 0)
          .with({ authWitnesses: [burnAuthWitBob] })
          .send({ from: bob });
        await expectTransferEvents(withdrawBobTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        expect(await totalShares(shares, alice)).toBe(0n);
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
        await expectTransferEvents(depositTx, shares.address, [
          { from: AztecAddress.ZERO, to: alice, amount: BigInt(sharesAlice) },
        ]);

        // Simulate yield: mint assets to vault
        await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

        // Bob issues public shares for public assets
        const issueAction = vault.methods.issue_public_to_public(bob, bob, sharesBob, assetsBob, 0);
        await setPublicAuthWit(carl, issueAction, bob, wallet);
        const issueTx = await callVaultWithPublicAuthWit(issueAction, bob, assetsBob, { caller: carl });
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
        await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        await expectTokenBalances(asset, carl, 0, 0);
        // Check shares balances
        await expectTokenBalances(shares, alice, sharesAlice, 0);
        await expectTokenBalances(shares, bob, sharesBob, 0);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws public assets by burning public shares
        const { result: maxWithdraw } = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        await authorizeBurnPublic(alice, sharesAlice);
        const withdrawAction = vault.methods.withdraw_public_to_public(alice, alice, maxWithdraw, 0);
        await setPublicAuthWit(carl, withdrawAction, alice, wallet);
        const { receipt: withdrawTx } = await withdrawAction.send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: alice, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for public assets
        await authorizeBurnPublic(bob, sharesBob);
        const redeemAction = vault.methods.redeem_public_to_public(bob, bob, sharesBob, 0);
        await setPublicAuthWit(carl, redeemAction, bob, wallet);
        const { receipt: redeemTx } = await redeemAction.send({ from: carl });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    // Skipped: requires `additionalScopes` (not yet available) so carl's PXE can
    // access alice's/bob's private notes when carl submits the tx.
    it.skip(
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
        await expectTransferEvents(depositTx, shares.address, [
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
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: bob, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
        await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        await expectTokenBalances(asset, carl, 0, 0);
        // Check shares balances
        await expectTokenBalances(shares, alice, sharesAlice, 0);
        await expectTokenBalances(shares, bob, sharesBob, 0);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning public shares
        const { result: maxWithdraw } = await vault.methods.max_withdraw(alice).simulate({ from: alice });
        await authorizeBurnPublic(alice, sharesAlice);
        const { receipt: withdrawTx } = await vault.methods
          .withdraw_public_to_private(alice, alice, maxWithdraw, 0)
          .send({ from: alice });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: alice, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems public shares for private assets
        const minAssets = 15;
        await authorizeBurnPublic(bob, sharesBob);
        const { receipt: redeemTx } = await vault.methods
          .redeem_public_to_private_exact(bob, bob, sharesBob, minAssets, 0)
          .send({ from: bob });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        expect(await totalShares(shares, carl)).toBe(0n);
        await expectTokenBalances(shares, carl, 0, 0);
      },
      TEST_TIMEOUT,
    );

    // Skipped: requires `additionalScopes` (not yet available) so carl's PXE can
    // access alice's/bob's private notes when carl submits the tx.
    it.skip(
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
        await expectTransferEvents(depositTx, shares.address, [
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
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0);
        await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        await expectTokenBalances(asset, carl, 0, 0);
        // Check shares balances
        await expectTokenBalances(shares, alice, 0, sharesAlice);
        await expectTokenBalances(shares, bob, 0, sharesBob);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws public assets by burning private shares
        const { result: maxRedeemPriv } = await shares.methods.balance_of_private(alice).simulate({ from: alice });
        const { result: maxWithdraw } = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const burnAuthWit = await authorizeBurnPrivate(alice, sharesAlice);
        const withdrawAction = vault.methods.withdraw_private_to_public_exact(
          alice,
          alice,
          maxWithdraw,
          sharesAlice,
          0,
        );
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        const { receipt: withdrawTx } = await withdrawAction
          .with({ authWitnesses: [withdrawAuthWitness, burnAuthWit] })
          .send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: alice, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for public assets
        const burnAuthWitBob = await authorizeBurnPrivate(bob, sharesBob);
        const redeemAction = vault.methods.redeem_private_to_public(bob, bob, sharesBob, 0);
        const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
        const { receipt: redeemTx } = await redeemAction
          .with({ authWitnesses: [redeemAuthWitness, burnAuthWitBob] })
          .send({ from: carl });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    // Skipped: requires `additionalScopes` (not yet available) so carl's PXE can
    // access alice's/bob's private notes when carl submits the tx.
    it.skip(
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
        await expectTransferEvents(depositTx, shares.address, [
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
        await expectTransferEvents(issueTx, shares.address, [
          { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount - assetsAlice);
        await expectTokenBalances(asset, bob, 0, initialAmount - assetsBob);
        await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0, alice);
        await expectTokenBalances(asset, carl, 0, 0);
        // Check shares balances
        await expectTokenBalances(shares, alice, 0, sharesAlice);
        await expectTokenBalances(shares, bob, 0, sharesBob);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning private shares
        const { result: maxRedeemPriv } = await shares.methods.balance_of_private(alice).simulate({ from: alice });
        const { result: maxWithdraw } = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const burnAuthWit = await authorizeBurnPrivate(alice, sharesAlice);
        const withdrawAction = vault.methods.withdraw_private_to_private(alice, alice, maxWithdraw, 9, 0);
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        const { receipt: withdrawTx } = await withdrawAction
          .with({ authWitnesses: [withdrawAuthWitness, burnAuthWit] })
          .send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob redeems private shares for private assets
        const burnAuthWitBob = await authorizeBurnPrivate(bob, sharesBob);
        const redeemAction = vault.methods.redeem_private_to_private_exact(bob, bob, sharesBob, 15, 0);
        const redeemAuthWitness = await setPrivateAuthWit(carl, redeemAction, bob, wallet);
        const { receipt: redeemTx } = await redeemAction
          .with({ authWitnesses: [redeemAuthWitness, burnAuthWitBob] })
          .send({ from: carl });
        await expectTransferEvents(redeemTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesBob) },
        ]);

        // Check asset balances
        await expectTokenBalances(asset, alice, 0, initialAmount + aliceEarnings);
        await expectTokenBalances(asset, bob, 0, initialAmount);
        await expectTokenBalances(asset, vault.address, dust, 0, alice);
        await expectTokenBalances(asset, carl, 0, 0);
        // Check shares balances
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    // Skipped: requires `additionalScopes` (not yet available) so carl's PXE can
    // access alice's/bob's private notes when carl submits the tx.
    it.skip(
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
        await expectTransferEvents(depositTx, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, sharesAlice);
        await expectTokenBalances(shares, bob, 0, sharesBob);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(BigInt(sharesBob + sharesAlice));

        // Alice withdraws private assets by burning private shares (exact)
        const { result: maxRedeemPriv } = await shares.methods.balance_of_private(alice).simulate({ from: alice });
        const { result: maxWithdraw } = await vault.methods.preview_redeem(maxRedeemPriv).simulate({ from: alice });
        const burnAuthWit = await authorizeBurnPrivate(alice, sharesAlice);
        const withdrawAction = vault.methods.withdraw_private_to_private_exact(alice, alice, maxWithdraw, 9, 0);
        const withdrawAuthWitness = await setPrivateAuthWit(carl, withdrawAction, alice, wallet);
        const { receipt: withdrawTx } = await withdrawAction
          .with({ authWitnesses: [withdrawAuthWitness, burnAuthWit] })
          .send({ from: carl });
        await expectTransferEvents(withdrawTx.txHash, shares.address, [
          { from: PRIVATE_ADDRESS, to: AztecAddress.ZERO, amount: BigInt(sharesAlice) },
        ]);
        await expectTransferEvents(withdrawTx.txHash, asset.address, [
          { from: vault.address, to: PRIVATE_ADDRESS, amount: maxWithdraw },
        ]);

        // Bob withdraws public assets by burning private shares (exact)
        const burnAuthWitBob = await authorizeBurnPrivate(bob, sharesBob);
        const publicWithdrawAction = vault.methods.withdraw_private_to_public_exact(bob, bob, 15, sharesBob, 0);
        const publicWithdrawAuthWitness = await setPrivateAuthWit(carl, publicWithdrawAction, bob, wallet);
        const { receipt: withdrawBobTx } = await publicWithdrawAction
          .with({ authWitnesses: [publicWithdrawAuthWitness, burnAuthWitBob] })
          .send({ from: carl });
        await expectTransferEvents(withdrawBobTx.txHash, shares.address, [
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
        await expectTokenBalances(shares, alice, 0, 0);
        await expectTokenBalances(shares, bob, 0, 0);
        await expectTokenBalances(shares, carl, 0, 0);
        expect(await totalShares(shares, carl)).toBe(0n);
      },
      TEST_TIMEOUT,
    );

    describe('Inflation attacks', () => {
      it(
        'zero-share deposit reverts',
        async () => {
          // Deploy vault without initial deposit (no protection)
          const [vaultContract, assetContract, sharesContract] = await deployVaultAndAssetWithMinter(wallet, alice);

          const attacker = bob;
          const victim = carl;

          // Fund attacker and victim
          await assetContract.methods.mint_to_public(attacker, 20_000n * scale).send({ from: alice });
          await assetContract.methods.mint_to_public(victim, 20_000n * scale).send({ from: alice });

          // 1) Attacker inflates the exchange rate: donate + mint 1 share
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

          const supplyAfterAttacker = await totalShares(sharesContract, attacker);
          expect(supplyAfterAttacker).toBe(1n);

          // 2) Victim deposits dust below threshold — would yield 0 shares, reverts
          const currentVaultAssets = await publicBalance(assetContract, vaultContract.address, attacker);
          const thresholdForOneShare = (currentVaultAssets + 1n) / 2n;
          const victimDepositAmount = thresholdForOneShare - 1n;

          const victimDepositAction = vaultContract
            .withWallet(wallet)
            .methods.deposit_public_to_public(victim, victim, victimDepositAmount, 0);
          await expect(
            callVaultWithPublicAuthWitFromWallet(
              vaultContract,
              assetContract,
              victimDepositAction,
              wallet,
              victim,
              victimDepositAmount,
            ),
          ).rejects.toThrow(/Zero shares|Assertion failed/);
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
          const [vaultContract, sharesContract] = await deployVaultWithInitialDeposit(
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
          expect(await totalShares(sharesContract, attacker)).toBe(initialDeposit);

          // 1) Attacker attempts the SAME donation as without protection
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

          const supplyAfterAttacker = await totalShares(sharesContract, attacker);

          const vaultAfterAttacker = await publicBalance(assetContract, vaultContract.address, attacker);

          // 2) Victim deposits just below threshold to get 0 shares
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
          const victimShares = await publicBalance(sharesContract, victim, victim);
          expect(victimShares).toBeGreaterThan(0n);

          const supplyAfterVictim = await totalShares(sharesContract, attacker);
          expect(supplyAfterVictim).toBeGreaterThan(supplyAfterAttacker);
          expect(supplyAfterVictim - supplyAfterAttacker).toBe(victimShares);

          const victimAfterDeposits: bigint = await publicBalance(assetContract, victim, victim);
          expect(victimBeforeDeposits - victimAfterDeposits).toBe(totalVictimDeposits);

          const vaultAfterVictim = await publicBalance(assetContract, vaultContract.address, attacker);
          expect(vaultAfterVictim - vaultAfterAttacker).toBe(totalVictimDeposits);

          // 4) Attacker redeems their 1 private share
          const burnAuthWit = await setPrivateAuthWit(
            vaultContract.address,
            sharesContract.methods.burn_private(attacker, 1n, 0),
            attacker,
            wallet,
          );
          await vaultContract.methods
            .redeem_private_to_public(attacker, attacker, 1n, 0)
            .with({ authWitnesses: [burnAuthWit] })
            .send({ from: attacker });

          const supplyAfterRedeem = await totalShares(sharesContract, attacker);
          expect(supplyAfterRedeem).toBeGreaterThan(0n);

          const strandedAssets = await publicBalance(assetContract, vaultContract.address, attacker);
          expect(strandedAssets).toBeGreaterThan(0n);

          const attackerFinal = await publicBalance(assetContract, attacker, attacker);
          const attackerNet = attackerFinal - attackerStart;

          // Attacker does NOT profit!
          expect(attackerNet).toBeLessThanOrEqual(0n);
        },
        TEST_TIMEOUT * 2,
      );
    });
  });
});
