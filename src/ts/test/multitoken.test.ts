import { Fr } from '@aztec/aztec.js/fields';
import { AztecAddress } from '@aztec/aztec.js/addresses';
import { type EmbeddedWallet } from '@aztec/wallets/embedded';
import { SetPublicAuthwitContractInteraction, lookupValidity } from '@aztec/aztec.js/authorization';
import { type ContractFunctionInteractionCallIntent } from '@aztec/aztec.js/authorization';

import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';

import {
  setupTestSuite,
  AMOUNT,
  PRIVATE_ADDRESS,
  MULTITOKEN_NAME,
  MULTITOKEN_SYMBOL,
  ID_A,
  fieldFromShortString,
  compressedStringToBigInt,
  deployMultiTokenWithMinter,
  initializeMultiTokenTransferCommitment,
  expectMultiTokenTransferEvents,
} from './utils.js';

import { MultiTokenContract } from '../../../src/artifacts/MultiToken.js';

const TEST_TIMEOUT = 300_000;

// Scope of this suite: ONE end-to-end happy-path per main (state-mutating) function, exercised through
// the real client stack (deploy -> call -> read via SDK, with real authwit + additionalScopes), asserting
// the resulting balances and the decoded event. It answers "does each function work end-to-end?".
// Correctness details — reverts, overflow/underflow, per-id isolation, id=0, note lifecycle, the ARC-403
// authorization hook, boundaries — are covered by the Noir/TXE suite (src/multitoken_contract/src/test/*).
describe('MultiToken', () => {
  let cleanup: () => Promise<void>;

  let wallet: EmbeddedWallet;
  let accounts: AztecAddress[];

  let alice: AztecAddress;
  let bob: AztecAddress;
  let carl: AztecAddress;

  let multitoken: MultiTokenContract;

  beforeAll(async () => {
    ({ cleanup, wallet, accounts } = await setupTestSuite());

    [alice, bob, carl] = accounts;
  });

  beforeEach(async () => {
    // Default deploy: minter = alice, auth_contract = ZERO (ARC-403 hook disabled). The hook's behavior
    // is covered exhaustively by the Noir suite (authorization.nr); here every path runs with it off.
    multitoken = await deployMultiTokenWithMinter(wallet, alice, alice, AztecAddress.ZERO);
  });

  afterAll(async () => {
    await cleanup();
  });

  // --- deploy / views ---

  it(
    'deploys with a minter and reads back name/symbol/minter/auth_contract',
    async () => {
      const nameField = fieldFromShortString(MULTITOKEN_NAME);
      const symbolField = fieldFromShortString(MULTITOKEN_SYMBOL);

      const mt = await deployMultiTokenWithMinter(wallet, alice, alice, AztecAddress.ZERO);

      const nameResult = (await mt.methods.name().simulate({ from: alice })).result;
      const symbolResult = (await mt.methods.symbol().simulate({ from: alice })).result;
      expect(compressedStringToBigInt(nameResult)).toBe(nameField.toBigInt());
      expect(compressedStringToBigInt(symbolResult)).toBe(symbolField.toBigInt());

      const minter = (await mt.methods.get_minter().simulate({ from: alice })).result;
      expect(minter.equals(alice)).toBe(true);

      const authContract = (await mt.methods.get_auth_contract().simulate({ from: alice })).result;
      expect(authContract.equals(AztecAddress.ZERO)).toBe(true);
    },
    TEST_TIMEOUT,
  );

  // --- mint_to_private ---

  it(
    'mints to a private recipient balance and leaks nothing publicly',
    async () => {
      const id = ID_A;
      const { receipt: mintTx } = await multitoken.methods.mint_to_private(bob, id, AMOUNT).send({ from: alice });
      // mint_to_private: (no public events)
      await expectMultiTokenTransferEvents(mintTx.txHash, multitoken.address, []);
      // recipient sees its private balance; no public balance was written.
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: bob })).result).toBe(AMOUNT);
      expect((await multitoken.methods.balance_of_public(bob, id).simulate({ from: bob })).result).toBe(0n);
      // an uninvolved third party never observes another account's private notes.
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: carl })).result).toBe(0n);
    },
    TEST_TIMEOUT,
  );

  // --- mint_to_public ---

  it(
    'mints to public and emits a 4-field TransferSingle event',
    async () => {
      const id = ID_A;

      const { receipt: mintTx } = await multitoken.methods.mint_to_public(alice, id, AMOUNT).send({ from: alice });

      // mint_to_public: TransferSingle(0x0, alice, id, AMOUNT)
      await expectMultiTokenTransferEvents(mintTx.txHash, multitoken.address, [
        { from: AztecAddress.ZERO, to: alice, id, amount: AMOUNT },
      ]);

      expect((await multitoken.methods.balance_of_public(alice, id).simulate({ from: alice })).result).toBe(AMOUNT);
      // No private note written for the public mint.
      expect((await multitoken.methods.balance_of_private(alice, id).simulate({ from: alice })).result).toBe(0n);
    },
    TEST_TIMEOUT,
  );

  // --- mint_to_commitment ---

  it(
    'mints to a recipient-prepared commitment and credits the recipient privately',
    async () => {
      const id = ID_A;

      // Recipient (bob) prepares the commitment for himself in his own settled tx, bound to the minter (alice) as completer.
      const commitment = await initializeMultiTokenTransferCommitment(multitoken, bob, bob, alice);

      // Minter (alice = msg_sender) completes the commitment by minting into it.
      const { receipt: mintTx } = await multitoken.methods
        .mint_to_commitment(id, commitment, AMOUNT)
        .send({ from: alice });

      // mint_to_commitment: TransferSingle(0x0, PRIVATE, id, AMOUNT)
      await expectMultiTokenTransferEvents(mintTx.txHash, multitoken.address, [
        { from: AztecAddress.ZERO, to: PRIVATE_ADDRESS, id, amount: AMOUNT },
      ]);

      // bob holds the tokens privately for this id.
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: bob })).result).toBe(AMOUNT);
    },
    TEST_TIMEOUT,
  );

  // --- transfer_public_to_public (happy-path carries the PUBLIC authwit demo) ---

  it(
    'transfers public to public with a public authwit',
    async () => {
      const id = ID_A;

      const { receipt: mintTx } = await multitoken
        .withWallet(wallet)
        .methods.mint_to_public(alice, id, AMOUNT)
        .send({ from: alice });

      // mint_to_public: TransferSingle(0x0, alice, id, AMOUNT)
      await expectMultiTokenTransferEvents(mintTx.txHash, multitoken.address, [
        { from: AztecAddress.ZERO, to: alice, id, amount: AMOUNT },
      ]);

      // Build the transfer; carl will submit it under alice's public authwit.
      const nonce = Fr.random();
      const action = multitoken.withWallet(wallet).methods.transfer_public_to_public(alice, bob, id, AMOUNT, nonce);

      const intent: ContractFunctionInteractionCallIntent = {
        caller: carl,
        action,
      };
      const authWitness = await wallet.createAuthWit(alice, {
        caller: intent.caller,
        call: await intent.action.getFunctionCall(),
      });
      const setPublicAuthwitInteraction = await SetPublicAuthwitContractInteraction.create(wallet, alice, intent, true);
      await setPublicAuthwitInteraction.send();

      const validity = await lookupValidity(wallet, alice, intent, authWitness);
      expect(validity.isValidInPrivate).toBeTruthy();
      expect(validity.isValidInPublic).toBeTruthy();

      const { receipt: transferTx } = await action.send({ from: carl, authWitnesses: [authWitness] });

      // transfer_public_to_public: TransferSingle(alice, bob, id, AMOUNT)
      await expectMultiTokenTransferEvents(transferTx.txHash, multitoken.address, [
        { from: alice, to: bob, id, amount: AMOUNT },
      ]);

      expect((await multitoken.methods.balance_of_public(alice, id).simulate({ from: carl })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_public(bob, id).simulate({ from: carl })).result).toBe(AMOUNT);
    },
    TEST_TIMEOUT,
  );

  // --- transfer_public_to_private (happy-path carries the PRIVATE authwit + additionalScopes demo) ---

  it(
    'transfers public to private under a third-party private authwit with additionalScopes',
    async () => {
      const id = ID_A;

      await multitoken.methods.mint_to_public(alice, id, AMOUNT).send({ from: alice });

      // Third party (bob) submits alice -> carl spending alice's PUBLIC balance; gate is a private authwit by alice.
      const action = multitoken.methods.transfer_public_to_private(alice, carl, id, AMOUNT, 1n);

      const intent: ContractFunctionInteractionCallIntent = {
        caller: bob,
        action,
      };
      const witness = await wallet.createAuthWit(alice, {
        caller: intent.caller,
        call: await intent.action.getFunctionCall(),
      });

      // additionalScopes includes alice so bob's PXE can read alice's account-contract notes
      // (signing key) needed for private authwit verification.
      const { receipt: transferTx } = await action.send({
        from: bob,
        authWitnesses: [witness],
        additionalScopes: [alice],
      });

      // transfer_public_to_private: TransferSingle(alice, PRIVATE, id, AMOUNT)  (hidden recipient side is the sentinel)
      await expectMultiTokenTransferEvents(transferTx.txHash, multitoken.address, [
        { from: alice, to: PRIVATE_ADDRESS, id, amount: AMOUNT },
      ]);

      expect((await multitoken.methods.balance_of_public(alice, id).simulate({ from: bob })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_private(carl, id).simulate({ from: carl })).result).toBe(AMOUNT);
    },
    TEST_TIMEOUT,
  );

  // --- transfer_public_to_commitment ---

  it(
    'transfers public to a recipient commitment as a self-spend',
    async () => {
      const id = ID_A;
      // bob prepares the commitment for himself in his own settled tx, bound to alice (the payer) as completer.
      const commitment = await initializeMultiTokenTransferCommitment(multitoken, bob, bob, alice);
      await multitoken.methods.mint_to_public(alice, id, AMOUNT).send({ from: alice });
      const { receipt: transferTx } = await multitoken.methods
        .transfer_public_to_commitment(alice, id, commitment, AMOUNT, 0)
        .send({ from: alice });
      // transfer_public_to_commitment: TransferSingle(alice, PRIVATE, id, AMOUNT)
      await expectMultiTokenTransferEvents(transferTx.txHash, multitoken.address, [
        { from: alice, to: PRIVATE_ADDRESS, id, amount: AMOUNT },
      ]);
      expect((await multitoken.methods.balance_of_public(alice, id).simulate({ from: alice })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: bob })).result).toBe(AMOUNT);
    },
    TEST_TIMEOUT,
  );

  // --- transfer_private_to_private ---

  it(
    'transfers private to private as a self-spend and leaks nothing publicly',
    async () => {
      const id = ID_A;
      await multitoken.methods.mint_to_private(alice, id, AMOUNT).send({ from: alice });
      const { receipt: transferTx } = await multitoken.methods
        .transfer_private_to_private(alice, bob, id, AMOUNT, 0)
        .send({ from: alice });
      // transfer_private_to_private: (no public events)
      await expectMultiTokenTransferEvents(transferTx.txHash, multitoken.address, []);
      expect((await multitoken.methods.balance_of_private(alice, id).simulate({ from: alice })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: bob })).result).toBe(AMOUNT);
      expect((await multitoken.methods.balance_of_public(alice, id).simulate({ from: alice })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_public(bob, id).simulate({ from: alice })).result).toBe(0n);
      // Third party never observes bob's new private notes.
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: carl })).result).toBe(0n);
    },
    TEST_TIMEOUT,
  );

  // --- transfer_private_to_public ---

  it(
    'transfers private to public as a self-spend and credits the recipient publicly',
    async () => {
      const id = ID_A;
      await multitoken.methods.mint_to_private(alice, id, AMOUNT).send({ from: alice });
      const { receipt: transferTx } = await multitoken.methods
        .transfer_private_to_public(alice, bob, id, AMOUNT, 0)
        .send({ from: alice });
      // transfer_private_to_public: TransferSingle(PRIVATE, bob, id, AMOUNT)
      await expectMultiTokenTransferEvents(transferTx.txHash, multitoken.address, [
        { from: PRIVATE_ADDRESS, to: bob, id, amount: AMOUNT },
      ]);
      expect((await multitoken.methods.balance_of_private(alice, id).simulate({ from: alice })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_public(bob, id).simulate({ from: alice })).result).toBe(AMOUNT);
    },
    TEST_TIMEOUT,
  );

  // --- transfer_private_to_commitment ---

  it(
    'transfers private to a settled commitment as a self-spend with no public event',
    async () => {
      const id = ID_A;
      // bob prepares the commitment for himself in a PRIOR settled tx, bound to alice (payer) as completer.
      // complete_from_private requires the validity commitment to be from a prior settled tx (the helper settles it).
      const commitment = await initializeMultiTokenTransferCommitment(multitoken, bob, bob, alice);
      await multitoken.methods.mint_to_private(alice, id, AMOUNT).send({ from: alice });
      const { receipt: transferTx } = await multitoken.methods
        .transfer_private_to_commitment(alice, id, commitment, AMOUNT, 0)
        .send({ from: alice });
      // transfer_private_to_commitment: (no public events) — private completion uses a private log, not a public write.
      await expectMultiTokenTransferEvents(transferTx.txHash, multitoken.address, []);
      expect((await multitoken.methods.balance_of_private(alice, id).simulate({ from: alice })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: bob })).result).toBe(AMOUNT);
    },
    TEST_TIMEOUT,
  );

  // --- burn_private ---

  it(
    'burns from a private balance as a self-spend',
    async () => {
      const id = ID_A;
      await multitoken.methods.mint_to_private(alice, id, AMOUNT).send({ from: alice });
      await multitoken.methods.burn_private(alice, id, AMOUNT, 0).send({ from: alice });
      expect((await multitoken.methods.balance_of_private(alice, id).simulate({ from: alice })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_public(alice, id).simulate({ from: alice })).result).toBe(0n);
    },
    TEST_TIMEOUT,
  );

  // --- burn_public ---

  it(
    'burns from a public balance and emits a burn event',
    async () => {
      const id = ID_A;
      await multitoken.methods.mint_to_public(alice, id, AMOUNT).send({ from: alice });
      const { receipt: burnTx } = await multitoken.methods.burn_public(alice, id, AMOUNT, 0).send({ from: alice });
      // burn_public: TransferSingle(alice, 0x0, id, AMOUNT)
      await expectMultiTokenTransferEvents(burnTx.txHash, multitoken.address, [
        { from: alice, to: AztecAddress.ZERO, id, amount: AMOUNT },
      ]);
      expect((await multitoken.methods.balance_of_public(alice, id).simulate({ from: alice })).result).toBe(0n);
    },
    TEST_TIMEOUT,
  );

  // --- initialize_transfer_commitment ---

  it(
    'initializes a transfer commitment (non-zero, no authwit, no balance change)',
    async () => {
      const id = ID_A;
      // Uses the sanctioned wallet-internals commitment helper (the ONLY sanctioned PXE/wallet-internals escape hatch).
      const commitment = await initializeMultiTokenTransferCommitment(multitoken, alice, bob, alice);
      expect(commitment).not.toBe(0n);
      // No id is bound at initialization; no balance is credited to the recipient or completer.
      expect((await multitoken.methods.balance_of_private(bob, id).simulate({ from: bob })).result).toBe(0n);
      expect((await multitoken.methods.balance_of_public(bob, id).simulate({ from: bob })).result).toBe(0n);
    },
    TEST_TIMEOUT,
  );
});
