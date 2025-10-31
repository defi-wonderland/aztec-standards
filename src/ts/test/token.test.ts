import { ContractDeployer } from '@aztec/aztec.js/deployment';
import { Fr } from '@aztec/aztec.js/fields';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { TxStatus } from '@aztec/aztec.js/tx';
import { Contract } from '@aztec/aztec.js/contracts';
import type { Wallet } from '@aztec/aztec.js/wallet';
import type { TestWallet } from '@aztec/test-wallet/server';
import type { ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';
import { SetPublicAuthwitContractInteraction } from '@aztec/aztec.js/authorization';

import { getContractInstanceFromInstantiationParams } from '@aztec/aztec.js/contracts';
import {
  setupTestSuite,
  AMOUNT,
  deployTokenWithMinter,
  expectTokenBalances,
  expectUintNote,
  // initializeTransferCommitment,
  wad,
} from './utils.js';
import type { PXE } from '@aztec/pxe/server';
import type { AztecLMDBStoreV2 } from '@aztec/kv-store/lmdb-v2';
import { TokenContractArtifact, TokenContract } from '../../../artifacts/Token.js';

describe('Token - Single PXE', () => {
  let pxe: PXE;
  let store: AztecLMDBStoreV2;

  let wallet: TestWallet;
  let accounts: AztecAddress[];

  let deployer: AztecAddress;
  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  let token: TokenContract;

  beforeAll(async () => {
    ({ pxe, store, wallet, accounts } = await setupTestSuite());

    [deployer, alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    token = (await deployTokenWithMinter(wallet, alice, { from: alice })) as TokenContract;
  });

  afterAll(async () => {
    await store.delete();
  });

  it('deploys the contract with minter', async () => {
    const salt = Fr.random();
    const deployerWallet = alice;

    const deploymentData = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
      constructorArtifact: 'constructor_with_minter',
      constructorArgs: ['PrivateToken', 'PT', 18, deployerWallet, deployerWallet],
      salt,
      deployer: deployerWallet,
    });

    const deployer = new ContractDeployer(TokenContractArtifact, wallet, undefined, 'constructor_with_minter');
    const tx = deployer.deploy('PrivateToken', 'PT', 18, deployerWallet, deployerWallet).send({
      contractAddressSalt: salt,
      from: deployerWallet,
    });
    const receipt = await tx.getReceipt();

    expect(receipt).toEqual(
      expect.objectContaining({
        status: TxStatus.PENDING,
        error: '',
      }),
    );

    const receiptAfterMined = await tx.wait({ wallet: wallet });

    const contractMetadata = await pxe.getContractMetadata(deploymentData.address);
    expect(contractMetadata).toBeDefined();
    // TODO: Fix this
    // expect(contractMetadata.isContractPubliclyDeployed).toBeTruthy();
    expect(receiptAfterMined).toEqual(
      expect.objectContaining({
        status: TxStatus.SUCCESS,
      }),
    );

    expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
  }, 300_000);

  it('deploys the contract with initial supply', async () => {
    const salt = Fr.random();
    const deployerWallet = alice; // using first account as deployer

    const deploymentData = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
      constructorArtifact: 'constructor_with_initial_supply',
      constructorArgs: ['PrivateToken', 'PT', 18, 1, deployerWallet, deployerWallet],
      salt,
      deployer: deployerWallet,
    });
    const deployer = new ContractDeployer(TokenContractArtifact, wallet, undefined, 'constructor_with_initial_supply');
    const tx = deployer
      .deploy('PrivateToken', 'PT', 18, 1, deployerWallet, deployerWallet)
      .send({ contractAddressSalt: salt, from: deployerWallet });
    const receipt = await tx.getReceipt();

    expect(receipt).toEqual(
      expect.objectContaining({
        status: TxStatus.PENDING,
        error: '',
      }),
    );

    const receiptAfterMined = await tx.wait({ wallet: wallet });

    const contractMetadata = await pxe.getContractMetadata(deploymentData.address);
    expect(contractMetadata).toBeDefined();
    // TODO: Fix this
    // expect(contractMetadata.isContractPubliclyDeployed).toBeTruthy();
    expect(receiptAfterMined).toEqual(
      expect.objectContaining({
        status: TxStatus.SUCCESS,
      }),
    );

    expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
  }, 300_000);

  it('mints', async () => {
    const tx = await token.methods.mint_to_public(bob, AMOUNT).send({ from: alice }).wait();
    const balance = await token.methods.balance_of_public(bob).simulate({ from: alice });
    expect(balance).toBe(AMOUNT);
  }, 300_000);

  it('transfers tokens between public accounts', async () => {
    // First mint 2 tokens to alice
    await token
      .withWallet(wallet)
      .methods.mint_to_public(alice, AMOUNT * 2n)
      .send({ from: alice })
      .wait();

    // Transfer 1 token from alice to bob
    await token
      .withWallet(wallet)
      .methods.transfer_public_to_public(alice, bob, AMOUNT, 0)
      .send({ from: alice })
      .wait();

    // Check balances are correct
    const aliceBalance = await token.methods.balance_of_public(alice).simulate({ from: alice });
    const bobBalance = await token.methods.balance_of_public(bob).simulate({ from: alice });

    expect(aliceBalance).toBe(AMOUNT);
    expect(bobBalance).toBe(AMOUNT);
  }, 300_000);

  // TODO(#29): burn was nuked because of this PR, re-enable it
  // it('burns public tokens', async () => {
  //   // First mint 2 tokens to alice
  //   await token
  //     .withWallet(wallet)
  //     .methods.mint_to_public(alice, AMOUNT * 2n)
  //     .send()
  //     .wait();

  //   // Burn 1 token from alice
  //   await token.withWallet(wallet).methods.burn_public(alice, AMOUNT, 0).send({ from: alice }).wait();

  //   // Check balance and total supply are reduced
  //   const aliceBalance = await token.methods.balance_of_public(alice).simulate({ from: alice });
  //   const totalSupply = await token.methods.total_supply().simulate({ from: alice });

  //   expect(aliceBalance).toBe(AMOUNT);
  //   expect(totalSupply).toBe(AMOUNT);
  // }, 300_000);

  it('transfers tokens from private to public balance', async () => {
    // First mint to private 2 tokens to alice
    await token
      .withWallet(wallet)
      .methods.mint_to_private(alice, AMOUNT * 2n)
      .send({ from: alice })
      .wait();

    // Transfer 1 token from alice's private balance to public balance
    await token
      .withWallet(wallet)
      .methods.transfer_private_to_public(alice, alice, AMOUNT, 0)
      .send({ from: alice })
      .wait();

    // Check public balance is correct
    const alicePublicBalance = await token.methods.balance_of_public(alice).simulate({ from: alice });
    expect(alicePublicBalance).toBe(AMOUNT);

    // Check total supply hasn't changed
    const totalSupply = await token.methods.total_supply().simulate({ from: alice });
    expect(totalSupply).toBe(AMOUNT * 2n);
  }, 300_000);

  it.skip('fails when transferring more tokens than available in private balance', async () => {
    // Mint 1 token privately to alice
    await token.withWallet(wallet).methods.mint_to_private(alice, AMOUNT).send({ from: alice }).wait();

    // Try to transfer more tokens than available from private to public balance
    // TODO(#29): fix "Invalid arguments size: expected 3, got 2" error handling
    // await expect(
    //   token
    //     .withWallet(wallet)
    //     .methods.transfer_private_to_public(alice, alice, AMOUNT + 1n, 0)
    //     .send()
    //     .wait(),
    // ).rejects.toThrow(/Balance too low/);
  }, 300_000);

  it('can transfer tokens between private balances', async () => {
    // Mint 2*AMOUNT tokens privately to alice
    await token
      .withWallet(wallet)
      .methods.mint_to_private(alice, AMOUNT * 2n)
      .send({ from: alice })
      .wait();

    // Transfer AMOUNT token from alice to bob's private balance
    await token
      .withWallet(wallet)
      .methods.transfer_private_to_private(alice, bob, AMOUNT, 0)
      .send({ from: alice })
      .wait();

    // Transfer zero tokens from alice to bob's private balance
    await token.withWallet(wallet).methods.transfer_private_to_private(alice, bob, 0, 0).send({ from: alice }).wait();

    // Try to transfer more than available balance
    // TODO(#29): fix "Invalid arguments size: expected 3, got 2" error handling
    // await expect(
    //   token
    //     .withWallet(wallet)
    //     .methods.transfer_private_to_private(alice, bob, AMOUNT + 1n, 0)
    //     .send()
    //     .wait(),
    // ).rejects.toThrow(/Balance too low/);

    // Check total supply hasn't changed
    const totalSupply = await token.methods.total_supply().simulate({ from: alice });
    expect(totalSupply).toBe(AMOUNT * 2n);
  }, 300_000);

  it('can mint tokens to private balance', async () => {
    // Mint 2 tokens privately to alice
    await token
      .withWallet(wallet)
      .methods.mint_to_private(alice, AMOUNT * 2n)
      .send({ from: alice })
      .wait();

    // Check total supply increased
    const totalSupply = await token.methods.total_supply().simulate({ from: alice });
    expect(totalSupply).toBe(AMOUNT * 2n);

    // Public balance should be 0 since we minted privately
    const alicePublicBalance = await token.methods.balance_of_public(alice).simulate({ from: alice });
    expect(alicePublicBalance).toBe(0n);
  }, 300_000);

  it('can burn tokens from private balance', async () => {
    // Mint 2 tokens privately to alice
    await token
      .withWallet(wallet)
      .methods.mint_to_private(alice, AMOUNT * 2n)
      .send({ from: alice })
      .wait();

    // Burn 1 token from alice's private balance
    await token.withWallet(wallet).methods.burn_private(alice, AMOUNT, 0).send({ from: alice }).wait();

    // Try to burn more than available balance
    await expect(
      token
        .withWallet(wallet)
        .methods.burn_private(alice, AMOUNT * 2n, 0)
        .send({ from: alice })
        .wait(),
    ).rejects.toThrow(/Balance too low/);

    // Check total supply decreased
    const totalSupply = await token.methods.total_supply().simulate({ from: alice });
    expect(totalSupply).toBe(AMOUNT);

    // Public balance should still be 0
    const alicePublicBalance = await token.methods.balance_of_public(alice).simulate({ from: alice });
    expect(alicePublicBalance).toBe(0n);
  }, 300_000);

  it('can transfer tokens from public to private balance', async () => {
    // Mint 2 tokens publicly to alice
    await token
      .withWallet(wallet)
      .methods.mint_to_public(alice, AMOUNT * 2n)
      .send({ from: alice })
      .wait();

    // Transfer 1 token from alice's public balance to private balance
    await token
      .withWallet(wallet)
      .methods.transfer_public_to_private(alice, alice, AMOUNT, 0)
      .send({ from: alice })
      .wait();

    // Try to transfer more than available public balance
    // TODO(#29): fix "Invalid arguments size: expected 3, got 2" error handling
    // await expect(
    //   token
    //     .withWallet(wallet)
    //     .methods.transfer_public_to_private(alice, alice, AMOUNT * 2n, 0)
    //     .send()
    //     .wait(),
    // ).rejects.toThrow(/attempt to subtract with underflow/);

    // Check total supply stayed the same
    const totalSupply = await token.methods.total_supply().simulate({ from: alice });
    expect(totalSupply).toBe(AMOUNT * 2n);

    // Public balance should be reduced by transferred amount
    const alicePublicBalance = await token.methods.balance_of_public(alice).simulate({ from: alice });
    expect(alicePublicBalance).toBe(AMOUNT);
  }, 300_000);

  // TODO: fix test when initializeTransferCommitment is fixed
  // it('mint in public, prepare partial note and finalize it', async () => {
  //   await token.withWallet(wallet);

  //   await token.methods.mint_to_public(alice, AMOUNT).send({ from: alice }).wait();

  //   // alice has tokens in public
  //   expect(await token.methods.balance_of_public(alice).simulate({ from: alice })).toBe(
  //     AMOUNT,
  //   );
  //   expect(await token.methods.balance_of_private(alice).simulate({ from: alice })).toBe(0n);
  //   // bob has 0 tokens
  //   expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(0n);
  //   expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(0n);

  //   expect(await token.methods.total_supply().simulate({ from: alice })).toBe(AMOUNT);

  //   // alice prepares partial note for bob
  //   const commitment = await initializeTransferCommitment(wallet, token, alice, bob, alice);

  //   // alice still has tokens in public
  //   expect(await token.methods.balance_of_public(alice).simulate({ from: alice })).toBe(
  //     AMOUNT,
  //   );

  //   // finalize partial note passing the commitment slot
  //   await token
  //     .withWallet(wallet)
  //     .methods.transfer_public_to_commitment(alice, commitment as bigint, AMOUNT, 0)
  //     .send({ from: alice })
  //     .wait();
  //   // alice now has no tokens
  //   expect(await token.methods.balance_of_public(alice).simulate({ from: alice })).toBe(0n);
  //   // bob has tokens in private
  //   expect(await token.methods.balance_of_public(bob).simulate({ from: alice })).toBe(0n);
  //   expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(
  //     AMOUNT,
  //   );
  //   // total supply is still the same
  //   expect(await token.methods.total_supply().simulate({ from: alice })).toBe(AMOUNT);
  // }, 300_000);

  // TODO: Can't figure out why this is failing
  // Assertion failed: unauthorized 'true, authorized'
  it.skip('public transfer with authwitness', async () => {
    // Mint tokens to Alice in public
    await token.withWallet(wallet).methods.mint_to_public(alice, AMOUNT).send({ from: alice }).wait();

    // build transfer public to public call
    const nonce = Fr.random();
    const action = token.withWallet(wallet).methods.transfer_public_to_public(alice, bob, AMOUNT, nonce);

    // define intent
    const intent: ContractFunctionInteractionCallIntent = {
      caller: carl,
      action,
    };
    // alice creates authwitness
    const authWitness = await wallet.createAuthWit(alice, intent);
    // alice authorizes the public authwit
    const setPublicAuthwitInteraction = await SetPublicAuthwitContractInteraction.create(wallet, alice, intent, true);

    await setPublicAuthwitInteraction.send().wait();

    // check validity of alice's authwit
    const validity = await wallet.lookupValidity(alice, intent, authWitness);
    expect(validity.isValidInPrivate).toBeTruthy();
    expect(validity.isValidInPublic).toBeTruthy();

    // Carl submits the action, using alice's authwit
    await action.send({ from: carl, authWitnesses: [authWitness] }).wait();

    // Check balances, alice to should 0
    expect(await token.methods.balance_of_public(alice).simulate({ from: carl })).toBe(0n);
    // Bob should have the a non-zero amount
    expect(await token.methods.balance_of_public(bob).simulate({ from: carl })).toBe(AMOUNT);
  }, 300_000);

  // TODO: fix when authwit is fixed
  //   it('private transfer with authwitness', async () => {
  //     // setup balances
  //     await token
  //       .withWallet(wallet)
  //       .methods.mint_to_public(alice, AMOUNT)
  //       .send({ from: alice })
  //       .wait();
  //     await token
  //       .withWallet(wallet)
  //       .methods.transfer_public_to_private(alice, alice, AMOUNT, 0)
  //       .send({ from: alice })
  //       .wait();

  //     expect(await token.methods.balance_of_private(alice).simulate({ from: alice })).toBe(
  //       AMOUNT,
  //     );

  //     // prepare action
  //     const nonce = Fr.random();
  //     const action = token
  //       .withWallet(wallet)
  //       .methods.transfer_private_to_private(alice, bob, AMOUNT, nonce);

  //     const intent: ContractFunctionInteractionCallIntent = {
  //       caller: carl,
  //       action,
  //     };

  //     console.log('intent', intent);
  //     const witness = await wallet.createAuthWit(alice, intent);

  //     const validity = await wallet.lookupValidity(carl, intent, witness);
  //     expect(validity.isValidInPrivate).toBeTruthy();
  //     expect(validity.isValidInPublic).toBeFalsy();

  //     await action.send({ from: carl, authWitnesses: [witness] }).wait();

  //     expect(await token.methods.balance_of_private(alice).simulate({ from: alice })).toBe(0n);
  //     expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(
  //       AMOUNT,
  //     );
  //   }, 300_000);
});

// While upgrading in early August multi PXE support was broken, this test is skipped until it is fixed.
// TODO: we should re-evaluate the necessity of this test suite, the other contracts don't have it and we don't seem to care.
describe.skip('Token - Multi PXE', () => {
  let pxe: PXE;

  let wallet: TestWallet;
  let accounts: AztecAddress[];
  let deployer: AztecAddress;

  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  let token: TokenContract;

  let alicePXE: PXE;
  let bobPXE: PXE;

  beforeAll(async () => {
    ({ pxe, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;

    // TODO: use different PXE instances.
    alicePXE = pxe;
    bobPXE = pxe;
  });

  beforeEach(async () => {
    token = (await deployTokenWithMinter(wallet, alice)) as TokenContract;
    await bobPXE.registerContract(token);

    // alice knows bob
    await alicePXE.registerSender(bob);

    // bob knows alice
    await bobPXE.registerSender(alice);
  });

  it('transfers', async () => {
    let events, notes;

    // mint initial amount to alice
    await token.withWallet(wallet).methods.mint_to_public(alice, wad(10)).send({ from: alice }).wait();

    // self-transfer 5 public tokens to private
    const aliceShieldTx = await token
      .withWallet(wallet)
      .methods.transfer_public_to_private(alice, alice, wad(5), 0)
      .send({ from: alice })
      .wait();
    await token.withWallet(wallet).methods.sync_private_state().simulate({ from: alice });

    // assert balances
    await expectTokenBalances(token, alice, wad(5), wad(5));

    // retrieve notes from last tx
    notes = await alicePXE.getNotes({ contractAddress: token.address, scopes: [alice] });
    expect(notes.length).toBe(1);
    expectUintNote(notes[0], wad(5), alice);

    // transfer some private tokens to bob
    const fundBobTx = await token
      .withWallet(wallet)
      .methods.transfer_public_to_private(alice, bob, wad(5), 0)
      .send({ from: alice })
      .wait();

    await token.withWallet(wallet).methods.sync_private_state().simulate({ from: alice });
    await token.withWallet(wallet).methods.sync_private_state().simulate({ from: bob });

    notes = await alicePXE.getNotes({ contractAddress: token.address, scopes: [alice] });
    expect(notes.length).toBe(1);
    expectUintNote(notes[0], wad(5), bob);

    // TODO: Bob is not receiving notes
    // notes = await bob.getNotes({ txHash: fundBobTx.txHash });
    // expect(notes.length).toBe(1);
    // expectUintNote(notes[0], wad(5), bob);

    // fund bob again
    const fundBobTx2 = await token
      .withWallet(wallet)
      .methods.transfer_private_to_private(alice, bob, wad(5), 0)
      .send({ from: alice })
      .wait();

    await token.withWallet(wallet).methods.sync_private_state().simulate({ from: alice });
    await token.withWallet(wallet).methods.sync_private_state().simulate({ from: bob });

    // assert balances
    await expectTokenBalances(token, alice, wad(0), wad(0));
    await expectTokenBalances(token, bob, wad(0), wad(10));

    // Alice shouldn't have any notes because it not a sender/registered account in her PXE
    // (but she has because I gave her access to Bob's notes)
    notes = await alicePXE.getNotes({ contractAddress: token.address, scopes: [alice] });
    expect(notes.length).toBe(1);
    expectUintNote(notes[0], wad(5), bob);

    // TODO: Bob is not receiving notes
    // Bob should have a note
    // notes = await bob.getNotes({txHash: fundBobTx2.txHash});
    // expect(notes.length).toBe(1);
    // expectUintNote(notes[0], wad(5), bob);

    // assert alice's balances again
    await expectTokenBalances(token, alice, wad(0), wad(0));
    // assert bob's balances
    await expectTokenBalances(token, bob, wad(0), wad(10));
  }, 300_000);
});
