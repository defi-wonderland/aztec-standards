import {
  setupTestSuite,
  deployVaultAndAssetWithMinter,
  setPrivateAuthWit,
  setPublicAuthWit,
  expectTokenBalances,
  MAX_U128_VALUE,
} from './utils.js';

import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
import { type ContractFunctionInteraction } from '@aztec/aztec.js/contracts';

import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';

import { TokenContract } from '../../../src/artifacts/Token.js';
import { TokenizedVaultContract } from '../../../src/artifacts/TokenizedVault.js';

const TEST_TIMEOUT = 300_000;

describe('Tokenized Vault', () => {
  let cleanup: () => Promise<void>;
  let wallet: TestWallet;
  let accounts: AztecAddress[];
  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  let vault: TokenizedVaultContract;
  let asset: TokenContract;
  let vaultToken: TokenContract;

  const initialAmount = 100n;
  const assetsAlice = 9n;
  const sharesAlice = assetsAlice;
  const yieldAmount = 5n;
  const sharesBob = 10n;
  const aliceEarnings = 4n;
  const dust = 1n;

  async function authorizePublicAssetTransfer(from: AztecAddress, amount: bigint, nonce: number | bigint) {
    const transfer = asset.methods.transfer_public_to_public(from, vault.address, amount, nonce);
    await setPublicAuthWit(vault.address, transfer, from, wallet);
  }

  async function authorizePrivateAssetTransfer(from: AztecAddress, amount: bigint, nonce: number | bigint) {
    const transfer = asset.methods.transfer_private_to_public(from, vault.address, amount, nonce);
    return setPrivateAuthWit(vault.address, transfer, from, wallet);
  }

  async function authorizeShareBurn(from: AztecAddress, shares: bigint, nonce: number | bigint) {
    const burn = vaultToken.methods.burn_public(from, shares, nonce);
    await setPublicAuthWit(vault.address, burn, from, wallet);
  }

  async function sendPublicVaultActionWithAssetAuth(
    action: ContractFunctionInteraction,
    from: AztecAddress,
    amount: bigint,
    nonce: number | bigint,
    caller: AztecAddress = from,
  ) {
    await authorizePublicAssetTransfer(from, amount, nonce);
    if (!caller.equals(from)) {
      await setPublicAuthWit(caller, action, from, wallet);
    }
    await action.send({ from: caller });
  }

  async function sendWithdrawPublicToPublic(
    from: AztecAddress,
    to: AztecAddress,
    assetsToWithdraw: bigint,
    nonce: number | bigint,
    caller: AztecAddress = from,
  ) {
    const sharesToBurn = await vault.methods.preview_withdraw(assetsToWithdraw).simulate({ from });
    await authorizeShareBurn(from, sharesToBurn, nonce);

    const action = vault.methods.withdraw_public_to_public(from, to, assetsToWithdraw, nonce);
    if (!caller.equals(from)) {
      await setPublicAuthWit(caller, action, from, wallet);
    }
    await action.send({ from: caller });
  }

  async function sendRedeemPublicToPublic(
    from: AztecAddress,
    to: AztecAddress,
    shares: bigint,
    nonce: number | bigint,
    caller: AztecAddress = from,
  ) {
    await authorizeShareBurn(from, shares, nonce);

    const action = vault.methods.redeem_public_to_public(from, to, shares, nonce);
    if (!caller.equals(from)) {
      await setPublicAuthWit(caller, action, from, wallet);
    }
    await action.send({ from: caller });
  }

  beforeAll(async () => {
    ({ cleanup, wallet, accounts } = await setupTestSuite());
    [alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    const deployment = await deployVaultAndAssetWithMinter(wallet, alice);
    vault = deployment.vaultContract;
    asset = deployment.assetContract;
    vaultToken = deployment.vaultTokenContract;
  });

  afterAll(async () => {
    await cleanup();
  });

  it(
    'public assets/public shares lifecycle: deposit, issue, withdraw, redeem',
    async () => {
      await asset.methods.mint_to_public(alice, initialAmount).send({ from: alice });
      await asset.methods.mint_to_public(bob, initialAmount).send({ from: alice });

      await sendPublicVaultActionWithAssetAuth(
        vault.methods.deposit_public_to_public(alice, alice, assetsAlice, 11),
        alice,
        assetsAlice,
        11,
      );

      await asset.methods.mint_to_public(vault.address, yieldAmount).send({ from: alice });

      const assetsBob = await vault.methods.preview_issue(sharesBob).simulate({ from: bob });
      await sendPublicVaultActionWithAssetAuth(
        vault.methods.issue_public_to_public(bob, bob, sharesBob, assetsBob, 12),
        bob,
        assetsBob,
        12,
      );

      await expectTokenBalances(asset, alice, initialAmount - assetsAlice, 0n);
      await expectTokenBalances(asset, bob, initialAmount - assetsBob, 0n);
      await expectTokenBalances(asset, vault.address, assetsAlice + assetsBob + yieldAmount, 0n, alice);

      await expectTokenBalances(vaultToken, alice, sharesAlice, 0n);
      await expectTokenBalances(vaultToken, bob, sharesBob, 0n);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(sharesAlice + sharesBob);

      const maxWithdrawAlice = await vault.methods.max_withdraw(alice).simulate({ from: alice });
      await sendWithdrawPublicToPublic(alice, alice, maxWithdrawAlice, 13);
      await sendRedeemPublicToPublic(bob, bob, sharesBob, 14);

      await expectTokenBalances(asset, alice, initialAmount + aliceEarnings, 0n);
      await expectTokenBalances(asset, bob, initialAmount, 0n);
      await expectTokenBalances(asset, vault.address, dust, 0n, alice);

      await expectTokenBalances(vaultToken, alice, 0n, 0n);
      await expectTokenBalances(vaultToken, bob, 0n, 0n);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
    },
    TEST_TIMEOUT,
  );

  it(
    'private asset deposit mints public shares and can be withdrawn back publicly',
    async () => {
      await asset.methods.mint_to_private(alice, initialAmount).send({ from: alice });

      const privateDepositAction = vault.methods.deposit_private_to_public(alice, alice, 10n, 21);
      const privateAuthWitness = await authorizePrivateAssetTransfer(alice, 10n, 21);
      await privateDepositAction.with({ authWitnesses: [privateAuthWitness] }).send({ from: alice });

      await expectTokenBalances(asset, alice, 0n, initialAmount - 10n);
      await expectTokenBalances(asset, vault.address, 10n, 0n, alice);
      await expectTokenBalances(vaultToken, alice, 10n, 0n);

      await sendWithdrawPublicToPublic(alice, alice, 10n, 22);

      await expectTokenBalances(asset, alice, 10n, initialAmount - 10n);
      await expectTokenBalances(asset, vault.address, 0n, 0n, alice);
      await expectTokenBalances(vaultToken, alice, 0n, 0n);
    },
    TEST_TIMEOUT,
  );

  it(
    'supports delegated public calls with authwits at both vault and token layers',
    async () => {
      await asset.methods.mint_to_public(alice, 20n).send({ from: alice });

      const depositAction = vault.methods.deposit_public_to_public(alice, alice, 5n, 31);
      await sendPublicVaultActionWithAssetAuth(depositAction, alice, 5n, 31, carl);

      await expectTokenBalances(asset, alice, 15n, 0n);
      await expectTokenBalances(vaultToken, alice, 5n, 0n);

      await sendRedeemPublicToPublic(alice, alice, 5n, 32, carl);

      await expectTokenBalances(asset, alice, 20n, 0n);
      await expectTokenBalances(asset, carl, 0n, 0n);
      await expectTokenBalances(vaultToken, alice, 0n, 0n);
    },
    TEST_TIMEOUT,
  );

  it(
    'exposes the expected view behavior',
    async () => {
      expect(await vault.methods.asset().simulate({ from: alice })).toEqual(asset.address);
      expect(await vault.methods.vault_token().simulate({ from: alice })).toEqual(vaultToken.address);
      expect(await vault.methods.get_vault_offset().simulate({ from: alice })).toBe(1n);

      expect(await vault.methods.max_deposit(alice).simulate({ from: alice })).toBe(MAX_U128_VALUE);
      expect(await vault.methods.max_issue(alice).simulate({ from: alice })).toBe(MAX_U128_VALUE);

      expect(await vault.methods.preview_deposit(7n).simulate({ from: alice })).toBe(7n);
      expect(await vault.methods.convert_to_shares(7n).simulate({ from: alice })).toBe(7n);
      expect(await vault.methods.preview_issue(7n).simulate({ from: alice })).toBe(7n);
      expect(await vault.methods.convert_to_assets(7n).simulate({ from: alice })).toBe(7n);
      expect(await vault.methods.preview_withdraw(7n).simulate({ from: alice })).toBe(7n);
      expect(await vault.methods.preview_redeem(7n).simulate({ from: alice })).toBe(7n);

      expect(await vault.methods.balance_of_public(alice).simulate({ from: alice })).toBe(0n);
      expect(await vault.methods.total_assets().simulate({ from: alice })).toBe(0n);
      expect(await vault.methods.total_supply().simulate({ from: alice })).toBe(0n);
      expect(await vault.methods.max_withdraw(alice).simulate({ from: alice })).toBe(0n);
      expect(await vault.methods.max_redeem(alice).simulate({ from: alice })).toBe(0n);
    },
    TEST_TIMEOUT,
  );
});
