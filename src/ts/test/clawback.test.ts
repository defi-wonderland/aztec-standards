import { TokenContract } from '../../artifacts/Token.js';
import { EscrowContract, EscrowKeys } from '../../artifacts/Escrow.js';
import { ClawbackEscrowContract } from '../../artifacts/ClawbackEscrow.js';
import { AccountWallet, PXE, Logger, AccountWalletWithSecretKey, Fr } from '@aztec/aztec.js';
import { createAccount } from '@aztec/accounts/testing';
import {
  createPXE,
  deployClawbackEscrow,
  deployEscrow,
  expectClawbackNote,
  expectTokenBalances,
  logger,
  wad,
} from './utils.js';
import { deployToken } from './token.test.js';

describe('ClawbackEscrow - Multi PXE', () => {
  let alicePXE: PXE;
  let bobPXE: PXE;

  let aliceWallet: AccountWalletWithSecretKey;
  let bobWallet: AccountWalletWithSecretKey;

  let alice: AccountWallet;
  let bob: AccountWallet;

  let token: TokenContract;
  let escrow: EscrowContract;
  let clawback: ClawbackEscrowContract;

  let logger: Logger;

  beforeAll(async () => {
    alicePXE = await createPXE(0);
    bobPXE = await createPXE(1);

    aliceWallet = await createAccount(alicePXE);
    bobWallet = await createAccount(bobPXE);

    alice = aliceWallet;
    bob = bobWallet;

    await bob.registerSender(alice.getAddress());
    // TODO: why do I need to register Alice's account?
    await bob.registerAccount(aliceWallet.getSecretKey(), await alice.getCompleteAddress().partialAddress);

    console.log({
      alice: alice.getAddress(),
      bob: bob.getAddress(),
    });
  });

  beforeEach(async () => {
    token = await deployToken(alice);
    clawback = await deployClawbackEscrow(aliceWallet);
    escrow = await deployEscrow(alice, clawback.address);

    // Token and Clawback is known to both PXEs
    for (const pxe of [alicePXE, bobPXE]) {
      await pxe.registerContract(token);
      await pxe.registerContract(clawback);
    }

    // Alice must have access to the escrow's notes, otherwise it won't be able to retrieve the AccountNote
    alice.setScopes([alice.getAddress(), escrow.address]);

    console.log({
      token: token.address,
      clawback: clawback.address,
      escrow: escrow.address,
    });
  });

  it('clawback', async () => {
    let events, notes;

    // fund the escrow
    await token.withWallet(alice).methods.mint_to_private(alice.getAddress(), escrow.address, wad(10)).send().wait();
    await expectTokenBalances(token, escrow.address, wad(0), wad(10));

    // create the clawback escrow
    let tx = await clawback
      .withWallet(alice)
      .methods.create_clawback_escrow(escrow.address, bob.getAddress())
      .send()
      .wait({ debug: true });

    // Alice and Bob sync notes in ClawbackEscrow
    await clawback.withWallet(bob).methods.sync_notes().simulate({});
    await clawback.withWallet(alice).methods.sync_notes().simulate({});

    // Check that the clawback note is accessible to Alice and Bob
    notes = await alice.getNotes({ txHash: tx.txHash });
    expect(notes.length).toBe(1);
    expectClawbackNote(notes[0], alice.getAddress(), bob.getAddress(), escrow.address);

    notes = await bob.getNotes({ txHash: tx.txHash });
    expect(notes.length).toBe(1);
    expectClawbackNote(notes[0], alice.getAddress(), bob.getAddress(), escrow.address);

    // Bob should have received a private event with the escrow's secret keys
    events = await bob.getPrivateEvents<EscrowKeys>(EscrowContract.events.EscrowKeys, tx.blockNumber!, 10);
    expect(events.length).toBe(1);
    let escrowSecreKeyEvent = events[0];
    // TODO: could we compute these values in advance to properly check the event's contents?
    expect(escrowSecreKeyEvent.escrow_secret).toBeDefined();
    expect(escrowSecreKeyEvent.nullification_secret).toBeDefined();

    // Bob is now aware of the escrow, so we can register it
    let escrowSecretKey = Fr.fromString(escrowSecreKeyEvent.escrow_secret.toString());
    await bob.registerAccount(escrowSecretKey, await escrow.partialAddress);
    bob.setScopes([bob.getAddress(), escrow.address]);
    await bob.registerContract(escrow);

    // TODO: assert nullifier is pushed

    // Bob syncs notes
    await escrow.withWallet(bob).methods.sync_notes().simulate({});

    // bob claims the escrow
    await clawback.withWallet(bob).methods.claim(escrow.address, token.address, wad(10)).send().wait();

    await expectTokenBalances(token, escrow.address, wad(0), wad(0));
    await expectTokenBalances(token, bob.getAddress(), wad(0), wad(10), bobWallet);
  }, 300_000);
});
