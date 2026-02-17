import { Fr } from '@aztec/aztec.js/fields';
import { type AztecNode } from '@aztec/aztec.js/node';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type TestWallet } from '@aztec/test-wallet/server';
import { ContractDeployer } from '@aztec/aztec.js/deployment';
import { SetPublicAuthwitContractInteraction } from '@aztec/aztec.js/authorization';
import { type ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';
import { getContractInstanceFromInstantiationParams } from '@aztec/aztec.js/contracts';

import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';

import {
  setupTestSuite,
  AMOUNT,
  deployTokenWithMinter,
  initializeTransferCommitment,
  expectTransferEvents,
  PRIVATE_ADDRESS,
} from './utils.js';

import { TokenContractArtifact, TokenContract } from '../../../src/artifacts/Token.js';

const TEST_TIMEOUT = 300_000;

describe('Token', () => {
  let cleanup: () => Promise<void>;

  let wallet: TestWallet;
  let accounts: AztecAddress[];

  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  let token: TokenContract;

  beforeAll(async () => {
    ({ cleanup, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    token = (await deployTokenWithMinter(wallet, alice, { from: alice })) as TokenContract;
  });

  afterAll(async () => {
    await cleanup();
  });

  it(
    'deploys the contract with minter',
    async () => {
      const salt = Fr.random();
      const deployerWallet = alice;

      const deploymentData = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
        constructorArtifact: 'constructor_with_minter',
        constructorArgs: ['PrivateToken', 'PT', 18, deployerWallet, deployerWallet],
        salt,
        deployer: deployerWallet,
      });

      const deployer = new ContractDeployer(TokenContractArtifact, wallet, undefined, 'constructor_with_minter');
      const contract = await deployer.deploy('PrivateToken', 'PT', 18, deployerWallet, deployerWallet).send({
        contractAddressSalt: salt,
        from: deployerWallet,
      });

      const contractMetadata = await wallet.getContractMetadata(deploymentData.address);
      expect(contractMetadata).toBeDefined();
      expect(contractMetadata.isContractPublished).toBeTruthy();

      expect(contract.address).toEqual(deploymentData.address);
    },
    TEST_TIMEOUT,
  );

  it(
    'deploys the contract with initial supply',
    async () => {
      const salt = Fr.random();
      const deployerWallet = alice; // using first account as deployer

      const deploymentData = await getContractInstanceFromInstantiationParams(TokenContractArtifact, {
        constructorArtifact: 'constructor_with_initial_supply',
        constructorArgs: ['PrivateToken', 'PT', 18, 1, deployerWallet, deployerWallet],
        salt,
        deployer: deployerWallet,
      });
      const deployer = new ContractDeployer(
        TokenContractArtifact,
        wallet,
        undefined,
        'constructor_with_initial_supply',
      );
      const contract = await deployer
        .deploy('PrivateToken', 'PT', 18, 1, deployerWallet, deployerWallet)
        .send({ contractAddressSalt: salt, from: deployerWallet });

      const contractMetadata = await wallet.getContractMetadata(deploymentData.address);
      expect(contractMetadata).toBeDefined();
      expect(contractMetadata.isContractPublished).toBeTruthy();

      expect(contract.address).toEqual(deploymentData.address);
    },
    TEST_TIMEOUT,
  );

  it('mint in public, prepare partial note and finalize it', async () => {
    // We create a new account manager for bob and override the address for this test
    const bobAccountManager = await wallet.createAccount();
    const bob = bobAccountManager.address;

    const mintTx = await token.methods.mint_to_public(alice, AMOUNT).send({ from: alice });

    // Assert mint event: Transfer(0x0, alice, AMOUNT)
    await expectTransferEvents(mintTx.txHash, token.address, [{ from: AztecAddress.ZERO, to: alice, amount: AMOUNT }]);

    // alice has tokens in public
    expect(await token.methods.balance_of_public(alice).simulate({ from: alice })).toBe(AMOUNT);
    expect(await token.methods.balance_of_private(alice).simulate({ from: alice })).toBe(0n);
    // bob has 0 tokens
    expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(0n);
    expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(0n);

    expect(await token.methods.total_supply().simulate({ from: alice })).toBe(AMOUNT);

    // alice prepares partial note for bob
    const commitment = await initializeTransferCommitment(token, alice, bobAccountManager, alice);

    // alice still has tokens in public
    expect(await token.methods.balance_of_public(alice).simulate({ from: alice })).toBe(AMOUNT);

    // finalize partial note passing the commitment slot
    const commitmentTx = await token
      .withWallet(wallet)
      .methods.transfer_public_to_commitment(alice, commitment as bigint, AMOUNT, 0)
      .send({ from: alice });

    // Assert commitment transfer event: Transfer(alice, PRIVATE_ADDRESS, AMOUNT)
    await expectTransferEvents(commitmentTx.txHash, token.address, [
      { from: alice, to: PRIVATE_ADDRESS, amount: AMOUNT },
    ]);

    // alice now has no tokens
    expect(await token.methods.balance_of_public(alice).simulate({ from: alice })).toBe(0n);
    // bob has tokens in private
    expect(await token.methods.balance_of_public(bob).simulate({ from: alice })).toBe(0n);
    expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(AMOUNT);
    // total supply is still the same
    expect(await token.methods.total_supply().simulate({ from: alice })).toBe(AMOUNT);
  }, 300_000);

  it('public transfer with authwitness', async () => {
    // Mint tokens to Alice in public
    const mintTx = await token.withWallet(wallet).methods.mint_to_public(alice, AMOUNT).send({ from: alice });

    // Assert mint event
    await expectTransferEvents(mintTx.txHash, token.address, [{ from: AztecAddress.ZERO, to: alice, amount: AMOUNT }]);

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

    await setPublicAuthwitInteraction.send();

    // check validity of alice's authwit
    const validity = await wallet.lookupValidity(alice, intent, authWitness);
    expect(validity.isValidInPrivate).toBeTruthy();
    expect(validity.isValidInPublic).toBeTruthy();

    // Carl submits the action, using alice's authwit
    const transferTx = await action.send({ from: carl, authWitnesses: [authWitness] });

    // Assert public transfer event: Transfer(alice, bob, AMOUNT)
    await expectTransferEvents(transferTx.txHash, token.address, [{ from: alice, to: bob, amount: AMOUNT }]);

    // Check balances, alice to should 0
    expect(await token.methods.balance_of_public(alice).simulate({ from: carl })).toBe(0n);
    // Bob should have the a non-zero amount
    expect(await token.methods.balance_of_public(bob).simulate({ from: carl })).toBe(AMOUNT);
  }, 300_000);

  it('private transfer with authwitness', async () => {
    // setup balances
    const mintTx = await token.withWallet(wallet).methods.mint_to_public(alice, AMOUNT).send({ from: alice });

    // Assert mint event
    await expectTransferEvents(mintTx.txHash, token.address, [{ from: AztecAddress.ZERO, to: alice, amount: AMOUNT }]);

    const toPrivateTx = await token
      .withWallet(wallet)
      .methods.transfer_public_to_private(alice, alice, AMOUNT, 0)
      .send({ from: alice });

    // Assert transfer_public_to_private event: decrease_public_balance_internal emits Transfer(alice, PRIVATE_ADDRESS, AMOUNT)
    await expectTransferEvents(toPrivateTx.txHash, token.address, [
      { from: alice, to: PRIVATE_ADDRESS, amount: AMOUNT },
    ]);

    expect(await token.methods.balance_of_private(alice).simulate({ from: alice })).toBe(AMOUNT);

    // prepare action
    const nonce = Fr.random();
    const action = token.withWallet(wallet).methods.transfer_private_to_private(alice, bob, AMOUNT, nonce);

    // Verify the action can be converted to a function call
    const functionCall = await action.getFunctionCall();
    if (!functionCall.selector) {
      throw new Error('Function selector is undefined - method may not exist in contract artifact');
    }

    const intent = { caller: carl, action };
    const witness = await wallet.createAuthWit(alice, intent);

    const validity = await wallet.lookupValidity(alice, intent, witness);
    expect(validity.isValidInPrivate).toBeTruthy();
    expect(validity.isValidInPublic).toBeFalsy();

    const privateTx = await action.send({ from: carl, authWitnesses: [witness] });

    // transfer_private_to_private is purely private: no public events emitted
    await expectTransferEvents(privateTx.txHash, token.address, []);

    expect(await token.methods.balance_of_private(alice).simulate({ from: alice })).toBe(0n);
    expect(await token.methods.balance_of_private(bob).simulate({ from: alice })).toBe(AMOUNT);
  }, 300_000);
});
