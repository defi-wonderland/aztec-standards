import { Contract, AccountWalletWithSecretKey } from '@aztec/aztec.js';
import { setupPXE, deployVaultAndAssetWithMinter, setPrivateAuthWit, setPublicAuthWit } from './utils.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';

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
  let vault: Contract;
  let asset: Contract;

  beforeAll(async () => {
    ({ pxe, wallets, store } = await setupTestSuite());
    [alice, bob] = wallets;
  });

  beforeEach(async () => {
    [vault, asset] = await deployVaultAndAssetWithMinter(alice);
  });

  afterAll(async () => {
    await store.delete();
  });

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
    // aliceAssets = await asset.methods.balance_of_private(alice.getAddress()).simulate();
    // bobAssets = await asset.methods.balance_of_private(bob.getAddress()).simulate();
    // vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    // expect(aliceAssets).toBe(BigInt(initialAmount + 4)); // Got yield
    // expect(bobAssets).toBe(BigInt(initialAmount)); // Didn't get yield
    // expect(vaultAssets).toBe(BigInt(1)); // 1 token left in vault due to rounding
    // // Check shares balances
    // aliceShares = await vault.methods.balance_of_public(alice.getAddress()).simulate();
    // bobShares = await vault.methods.balance_of_public(bob.getAddress()).simulate();
    // totalSupply = await vault.methods.total_supply().simulate();
    // expect(aliceShares).toBe(BigInt(0));
    // expect(bobShares).toBe(BigInt(0));
    // expect(totalSupply).toBe(BigInt(0));
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
    let aliceAssets = await asset.methods.balance_of_public(alice.getAddress()).simulate();
    let bobAssets = await asset.methods.balance_of_public(bob.getAddress()).simulate();
    let vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    expect(aliceAssets).toBe(BigInt(initialAmount - 9)); // Got yield
    expect(bobAssets).toBe(BigInt(initialAmount - 15)); // Didn't get yield
    expect(vaultAssets).toBe(BigInt(29)); // 1 token left in vault due to rounding
    // Check shares balances
    let aliceShares = await vault.methods.balance_of_private(alice.getAddress()).simulate();
    let bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
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
      .methods.withdraw_private_to_public_exact(alice.getAddress(), alice.getAddress(), maxWithdraw, 9, 0)
      .send()
      .wait();

    // Bob redeems public shares for public assets
    // Bob should get 15 asset tokens back, 1 token remains in the vault
    await vault
      .withWallet(bob)
      .methods.redeem_private_to_public(bob.getAddress(), bob.getAddress(), bobShares, 0)
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
    aliceShares = await vault.methods.balance_of_private(alice.getAddress()).simulate();
    bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
    totalSupply = await vault.methods.total_supply().simulate();
    expect(aliceShares).toBe(BigInt(0));
    expect(bobShares).toBe(BigInt(0));
    expect(totalSupply).toBe(BigInt(0));
  }, 300_000);

  it.only('Private assets, Private shares: Alice deposits/withdraws, Bob issues/redeems', async () => {
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

    // // Check asset balances
    let aliceAssets = await asset.methods.balance_of_private(alice.getAddress()).simulate();
    let bobAssets = await asset.methods.balance_of_private(bob.getAddress()).simulate();
    let vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    expect(aliceAssets).toBe(BigInt(initialAmount - 9)); // Got yield
    expect(bobAssets).toBe(BigInt(initialAmount - 15)); // Didn't get yield
    expect(vaultAssets).toBe(BigInt(29)); // 1 token left in vault due to rounding
    // // Check shares balances
    let aliceShares = await vault.methods.balance_of_private(alice.getAddress()).simulate();
    let bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
    let totalSupply = await vault.methods.total_supply().simulate();
    expect(aliceShares).toBe(BigInt(9));
    expect(bobShares).toBe(BigInt(10));
    expect(totalSupply).toBe(BigInt(19));

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
    // aliceAssets = await asset.methods.balance_of_private(alice.getAddress()).simulate();
    // bobAssets = await asset.methods.balance_of_private(bob.getAddress()).simulate();
    // vaultAssets = await asset.methods.balance_of_public(vault.address).simulate();
    // expect(aliceAssets).toBe(BigInt(initialAmount + 4)); // Got yield
    // expect(bobAssets).toBe(BigInt(initialAmount)); // Didn't get yield
    // expect(vaultAssets).toBe(BigInt(1)); // 1 token left in vault due to rounding
    // // Check shares balances
    // aliceShares = await vault.methods.balance_of_private(alice.getAddress()).simulate();
    // bobShares = await vault.methods.balance_of_private(bob.getAddress()).simulate();
    // totalSupply = await vault.methods.total_supply().simulate();
    // expect(aliceShares).toBe(BigInt(0));
    // expect(bobShares).toBe(BigInt(0));
    // expect(totalSupply).toBe(BigInt(0));
  }, 300_000);
});
