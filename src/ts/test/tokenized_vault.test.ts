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
  let carl: AccountWalletWithSecretKey;
  let vault: TokenContract;
  let asset: TokenContract;

  beforeAll(async () => {
    ({ pxe, wallets, store } = await setupTestSuite());
    [alice, bob, carl] = wallets;
  });

  beforeEach(async () => {
    [vault, asset] = (await deployVaultAndAssetWithMinter(alice)) as [TokenContract, TokenContract];
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('Successful interactions, no authwits.', () => {
    it('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
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
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount - 9), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - 15), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(9), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(10), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

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
      let bobShares = await vault.methods.balance_of_public(bob.getAddress()).simulate();
      await vault
        .withWallet(bob)
        .methods.redeem_public_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0)
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount + 4), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);

    it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
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
      const depositAction = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, 9, 0);
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
        .methods.issue_private_to_public_exact(bob.getAddress(), bob.getAddress(), 10, 15, 0)
        .with({ authWitnesses: [issuanceAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - 9));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount - 15));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(9), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(10), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws private assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // await vault
      //   .withWallet(alice)
      //   .methods.withdraw_public_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
      //   .send()
      //   .wait();

      // // Bob redeems private shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // const minAssets = 15;
      // await vault
      //   .withWallet(bob)
      //   .methods.redeem_public_to_private_exact(bob.getAddress(), bob.getAddress(), bobShares, minAssets, 0)
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + 4));
      // await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount));
      // await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // // Check shares balances
      // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);

    it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      const initialAmount = 100;
      await asset.withWallet(alice).methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
      await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits public assets, receives public shares
      const depositAction = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, 9, 0);
      await setPublicAuthWit(vault.address, depositAction, alice);
      await vault
        .withWallet(alice)
        .methods.deposit_public_to_private(alice.getAddress(), alice.getAddress(), 9, 9, 0)
        .send()
        .wait();

      // Simulate yield: mint assets to vault
      await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

      // Bob issues public shares for public assets
      const issuanceAction = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, 15, 0);
      await setPublicAuthWit(vault.address, issuanceAction, bob);
      await vault
        .withWallet(bob)
        .methods.issue_public_to_private(bob.getAddress(), bob.getAddress(), 10, 15, 0)
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount - 9), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - 15), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(9));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(10));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      await vault
        .withWallet(alice)
        .methods.withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
        .send()
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      let bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
      await vault
        .withWallet(bob)
        .methods.redeem_private_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0)
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount + 4), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);

    it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
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
      const depositAction = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, 9, 0);
      const depositAuthWitness = await setPrivateAuthWit(vault.address, depositAction, alice);
      await vault
        .withWallet(alice)
        .methods.deposit_private_to_private(alice.getAddress(), alice.getAddress(), 9, 9, 0)
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
        .methods.issue_private_to_private_exact(bob.getAddress(), bob.getAddress(), 10, 15, 0)
        .with({ authWitnesses: [issuanceAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - 9));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount - 15));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(9));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(10));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws public assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // await vault
      //   .withWallet(alice)
      //   .methods.withdraw_private_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
      //   .send()
      //   .wait();

      // // Bob redeems public shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // await vault
      //   .withWallet(bob)
      //   .methods.redeem_private_to_private_exact(bob.getAddress(), bob.getAddress(), bobShares, 15, 0)
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + 4));
      // await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount));
      // await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // // Check shares balances
      // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);

    it('Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      const initialAmount = 100;
      await asset
        .withWallet(alice)
        .methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount)
        .send()
        .wait();
      await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives public shares
      const privateDepositAction = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, 9, 0);
      const depositAuthWitness = await setPrivateAuthWit(vault.address, privateDepositAction, alice);
      await vault
        .withWallet(alice)
        .methods.deposit_private_to_private_exact(alice.getAddress(), alice.getAddress(), 9, 9, 0)
        .with({ authWitnesses: [depositAuthWitness] })
        .send()
        .wait();

      // Simulate yield: mint assets to vault
      await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

      // Bob issues public shares for public assets
      const publicDepositAction = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, 15, 0);
      await setPublicAuthWit(vault.address, publicDepositAction, bob);
      await vault
        .withWallet(bob)
        .methods.deposit_public_to_private_exact(bob.getAddress(), bob.getAddress(), 15, 10, 0)
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - 9));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - 15), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(9));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(10));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws public assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // await vault
      //   .withWallet(alice)
      //   .methods.withdraw_private_to_private_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
      //   .send()
      //   .wait();

      // // Bob redeems public shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // await vault
      //   .withWallet(bob)
      //   .methods.withdraw_private_to_public_exact(bob.getAddress(), bob.getAddress(), 15, bobShares, 0)
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + 4));
      // await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
      // await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // // Check shares balances
      // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);
  });

  describe('Successful interactions with authwits.', () => {
    it('Public assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      const initialAmount = 100;
      await asset.withWallet(alice).methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
      await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits public assets, receives public shares
      const assetDepositApproval = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, 9, 0);
      await setPublicAuthWit(vault.address, assetDepositApproval, alice);
      const depositAction = vault.methods.deposit_public_to_public(alice.getAddress(), alice.getAddress(), 9, 0);
      await setPublicAuthWit(carl.getAddress(), depositAction, alice);
      await vault
        .withWallet(carl)
        .methods.deposit_public_to_public(alice.getAddress(), alice.getAddress(), 9, 0)
        .send()
        .wait();

      // Simulate yield: mint assets to vault
      await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

      // Bob issues public shares for public assets
      const assetIssuaApproval = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, 15, 0);
      await setPublicAuthWit(vault.address, assetIssuaApproval, bob);
      const issueAction = vault.methods.issue_public_to_public(bob.getAddress(), bob.getAddress(), 10, 15, 0);
      await setPublicAuthWit(carl.getAddress(), issueAction, bob);
      await vault
        .withWallet(carl)
        .methods.issue_public_to_public(bob.getAddress(), bob.getAddress(), 10, 15, 0)
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount - 9), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - 15), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(9), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(10), BigInt(0));
      await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

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
      await setPublicAuthWit(carl.getAddress(), withdrawAction, alice);
      await vault
        .withWallet(carl)
        .methods.withdraw_public_to_public(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
        .send()
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      let bobShares = await vault.methods.balance_of_public(bob.getAddress()).simulate();
      const redeemAction = vault.methods.redeem_public_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0);
      await setPublicAuthWit(carl.getAddress(), redeemAction, bob);
      await vault
        .withWallet(carl)
        .methods.redeem_public_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0)
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount + 4), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);

    it('Private assets, Public shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
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
      const assetDepositApproval = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, 9, 0);
      const assetDepositAuthWitness = await setPrivateAuthWit(vault.address, assetDepositApproval, alice);
      const depositAction = vault.methods.deposit_private_to_public(alice.getAddress(), alice.getAddress(), 9, 0);
      const depositAuthWitness = await setPrivateAuthWit(carl.getAddress(), depositAction, alice);
      await vault
        .withWallet(carl)
        .methods.deposit_private_to_public(alice.getAddress(), alice.getAddress(), 9, 0)
        .with({ authWitnesses: [depositAuthWitness, assetDepositAuthWitness] })
        .send()
        .wait();

      // Simulate yield: mint assets to vault
      await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

      // Bob issues public shares for public assets
      const assetIssueApproval = asset.methods.transfer_private_to_public(bob.getAddress(), vault.address, 15, 0);
      const assetIssueAuthWitness = await setPrivateAuthWit(vault.address, assetIssueApproval, bob);
      const issueAction = vault.methods.issue_private_to_public_exact(bob.getAddress(), bob.getAddress(), 10, 15, 0);
      const issueAuthWitness = await setPrivateAuthWit(carl.getAddress(), issueAction, bob);
      await vault
        .withWallet(carl)
        .methods.issue_private_to_public_exact(bob.getAddress(), bob.getAddress(), 10, 15, 0)
        .with({ authWitnesses: [issueAuthWitness, assetIssueAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - 9));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount - 15));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(9), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(10), BigInt(0));
      await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws private assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // await vault
      //   .withWallet(alice)
      //   .methods.withdraw_public_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 0)
      //   .send()
      //   .wait();

      // // Bob redeems private shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // const minAssets = 15;
      // await vault
      //   .withWallet(bob)
      //   .methods.redeem_public_to_private_exact(bob.getAddress(), bob.getAddress(), bobShares, minAssets, 0)
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + 4));
      // await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount));
      // await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // // Check shares balances
      // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
      // await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
    }, 300_000);

    it('Public assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      const initialAmount = 100;
      await asset.withWallet(alice).methods.mint_to_public(alice.getAddress(), initialAmount).send().wait();
      await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits public assets, receives public shares
      const assetDepositApproval = asset.methods.transfer_public_to_public(alice.getAddress(), vault.address, 9, 0);
      await setPublicAuthWit(vault.address, assetDepositApproval, alice);
      const depositAction = vault.methods.deposit_public_to_private(alice.getAddress(), alice.getAddress(), 9, 9, 0);
      const depositAuthWitness = await setPrivateAuthWit(carl.getAddress(), depositAction, alice);
      await vault
        .withWallet(carl)
        .methods.deposit_public_to_private(alice.getAddress(), alice.getAddress(), 9, 9, 0)
        .with({ authWitnesses: [depositAuthWitness] })
        .send()
        .wait();

      // Simulate yield: mint assets to vault
      await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

      // Bob issues public shares for public assets
      const assetIssuaApproval = asset.methods.transfer_public_to_public(bob.getAddress(), vault.address, 15, 0);
      await setPublicAuthWit(vault.address, assetIssuaApproval, bob);
      const issueAction = vault.methods.issue_public_to_private(bob.getAddress(), bob.getAddress(), 10, 15, 0);
      const issueAuthWitness = await setPrivateAuthWit(carl.getAddress(), issueAction, bob);
      await vault
        .withWallet(carl)
        .methods.issue_public_to_private(bob.getAddress(), bob.getAddress(), 10, 15, 0)
        .with({ authWitnesses: [issueAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount - 9), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - 15), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(9));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(10));
      await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // Alice withdraws public assets by burning public shares
      // TODO: call preview max withdraw function
      // Cannot withdraw 14 due to rounding.
      const maxWithdraw = 13;
      const withdrawAction = vault.methods.withdraw_private_to_public_exact(
        alice.getAddress(),
        alice.getAddress(),
        maxWithdraw,
        9,
        0,
      );
      const withdrawAuthWitness = await setPrivateAuthWit(carl.getAddress(), withdrawAction, alice);
      await vault
        .withWallet(carl)
        .methods.withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
        .with({ authWitnesses: [withdrawAuthWitness] })
        .send()
        .wait();

      // Bob redeems public shares for public assets
      // Bob should get 15 asset tokens back, 1 token remains in the vault
      let bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
      const redeemAction = vault.methods.redeem_private_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0);
      const redeemAuthWitness = await setPrivateAuthWit(carl.getAddress(), redeemAction, bob);
      await vault
        .withWallet(carl)
        .methods.redeem_private_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0)
        .with({ authWitnesses: [redeemAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(initialAmount + 4), BigInt(0));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);

    it('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
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
      const assetDepositApproval = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, 9, 0);
      const assetDepositAuthWitness = await setPrivateAuthWit(vault.address, assetDepositApproval, alice);
      const depositAction = vault.methods.deposit_private_to_private(alice.getAddress(), alice.getAddress(), 9, 9, 0);
      const depositAuthWitness = await setPrivateAuthWit(carl.getAddress(), depositAction, alice);
      await vault
        .withWallet(carl)
        .methods.deposit_private_to_private(alice.getAddress(), alice.getAddress(), 9, 9, 0)
        .with({ authWitnesses: [depositAuthWitness, assetDepositAuthWitness] })
        .send()
        .wait();

      // Simulate yield: mint assets to vault
      await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

      // Bob issues public shares for public assets
      const assetIssueApproval = asset.methods.transfer_private_to_public(bob.getAddress(), vault.address, 15, 0);
      const assetIssueAuthWitness = await setPrivateAuthWit(vault.address, assetIssueApproval, bob);
      const issueAction = vault.methods.issue_private_to_private_exact(bob.getAddress(), bob.getAddress(), 10, 15, 0);
      const issueAuthWitness = await setPrivateAuthWit(carl.getAddress(), issueAction, bob);
      await vault
        .withWallet(carl)
        .methods.issue_private_to_private_exact(bob.getAddress(), bob.getAddress(), 10, 15, 0)
        .with({ authWitnesses: [issueAuthWitness, assetIssueAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - 9));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount - 15));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(9));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(10));
      await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws public assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // const withdrawAction = vault.methods.withdraw_private_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0);
      // const withdrawAuthWitness = await setPrivateAuthWit(carl.getAddress(), withdrawAction, alice);
      // await vault
      //   .withWallet(carl)
      //   .methods.withdraw_private_to_private(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
      //   .with({ authWitnesses: [withdrawAuthWitness] })
      //   .send()
      //   .wait();

      // // Bob redeems public shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // let bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
      // const redeemAction = vault.methods.redeem_private_to_private_exact(bob.getAddress(), bob.getAddress(), bobShares, 15, 0);
      // const redeemAuthWitness = await setPrivateAuthWit(carl.getAddress(), redeemAction, bob);
      // await vault
      //   .withWallet(carl)
      //   .methods.redeem_private_to_private_exact(bob.getAddress(), bob.getAddress(), bobShares, 15, 0)
      //   .with({ authWitnesses: [redeemAuthWitness] })
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + 4));
      // await expectTokenBalances(asset, bob.getAddress(), BigInt(0), BigInt(initialAmount));
      // await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // // Check shares balances
      // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);

    it('Exact methods, Mixed Assets, Private shares: Alice deposits/withdraws, Bob deposits/withdraws', async () => {
      // Mint some assets to Alice and Bob for deposit/issue
      const initialAmount = 100;
      await asset
        .withWallet(alice)
        .methods.mint_to_private(alice.getAddress(), alice.getAddress(), initialAmount)
        .send()
        .wait();
      await asset.withWallet(alice).methods.mint_to_public(bob.getAddress(), initialAmount).send().wait();

      // Alice deposits private assets, receives public shares
      const assetDepositApproval = asset.methods.transfer_private_to_public(alice.getAddress(), vault.address, 9, 0);
      const assetDepositAuthWitness = await setPrivateAuthWit(vault.address, assetDepositApproval, alice);
      const depositAction = vault.methods.deposit_private_to_private_exact(
        alice.getAddress(),
        alice.getAddress(),
        9,
        9,
        0,
      );
      const depositAuthWitness = await setPrivateAuthWit(carl.getAddress(), depositAction, alice);
      await vault
        .withWallet(carl)
        .methods.deposit_private_to_private_exact(alice.getAddress(), alice.getAddress(), 9, 9, 0)
        .with({ authWitnesses: [depositAuthWitness, assetDepositAuthWitness] })
        .send()
        .wait();

      // Simulate yield: mint assets to vault
      await asset.withWallet(alice).methods.mint_to_public(vault.address, 5).send().wait();

      // Bob issues public shares for public assets
      const publicAssetDepositApproval = asset.methods.transfer_public_to_public(
        bob.getAddress(),
        vault.address,
        15,
        0,
      );
      await setPublicAuthWit(vault.address, publicAssetDepositApproval, bob);
      const publicDepositAction = vault.methods.deposit_public_to_private_exact(
        bob.getAddress(),
        bob.getAddress(),
        15,
        10,
        0,
      );
      const publicDepositAuthWitness = await setPrivateAuthWit(carl.getAddress(), publicDepositAction, bob);
      await vault
        .withWallet(carl)
        .methods.deposit_public_to_private_exact(bob.getAddress(), bob.getAddress(), 15, 10, 0)
        .with({ authWitnesses: [publicDepositAuthWitness] })
        .send()
        .wait();

      // Check asset balances
      await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount - 9));
      await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount - 15), BigInt(0));
      await expectTokenBalances(asset, vault.address, BigInt(29), BigInt(0));
      await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // Check shares balances
      await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(9));
      await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(10));
      await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      expect(await vault.methods.total_supply().simulate()).toBe(BigInt(19));

      // TODO: vault cannot encrypt note due to lack of app tagging secret: Simulation error: No public key registered for address
      // // Alice withdraws public assets by burning public shares
      // // TODO: call preview max withdraw function
      // // Cannot withdraw 14 due to rounding.
      // const maxWithdraw = 13;
      // const withdrawAction = vault.methods.withdraw_private_to_private_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0);
      // const withdrawAuthWitness = await setPrivateAuthWit(carl.getAddress(), withdrawAction, alice);
      // await vault
      //   .withWallet(carl)
      //   .methods.withdraw_private_to_private_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
      //   .with({ authWitnesses: [withdrawAuthWitness] })
      //   .send()
      //   .wait();

      // // Bob redeems public shares for public assets
      // // Bob should get 15 asset tokens back, 1 token remains in the vault
      // const bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
      // const publicWithdrawAction = vault.methods.withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), 15, bobShares, 0);
      // const publicWithdrawAuthWitness = await setPrivateAuthWit(carl.getAddress(), publicWithdrawAction, alice);
      // await vault
      //   .withWallet(carl)
      //   .methods.withdraw_private_to_public_exact(bob.getAddress(), bob.getAddress(), 15, bobShares, 0)
      //   .with({ authWitnesses: [publicWithdrawAuthWitness] })
      //   .send()
      //   .wait();

      // // Check asset balances
      // await expectTokenBalances(asset, alice.getAddress(), BigInt(0), BigInt(initialAmount + 4));
      // await expectTokenBalances(asset, bob.getAddress(), BigInt(initialAmount), BigInt(0));
      // await expectTokenBalances(asset, vault.address, BigInt(1), BigInt(0));
      // await expectTokenBalances(asset, carl.getAddress(), BigInt(0), BigInt(0));
      // // Check shares balances
      // await expectTokenBalances(vault, alice.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, bob.getAddress(), BigInt(0), BigInt(0));
      // await expectTokenBalances(vault, carl.getAddress(), BigInt(0), BigInt(0));
      // expect(await vault.methods.total_supply().simulate()).toBe(BigInt(0));
    }, 300_000);
  });
});
