import { TokenContract } from '../../artifacts/Token.js';
import { EscrowContract } from '../../artifacts/Escrow.js';
import { ClawbackEscrowContract } from '../../artifacts/ClawbackEscrow.js';
import { AccountWallet, PXE, Logger, AccountWalletWithSecretKey } from '@aztec/aztec.js';
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
    token = (await deployToken(alice)) as TokenContract;
    clawback = (await deployClawbackEscrow(aliceWallet)) as ClawbackEscrowContract;
    escrow = (await deployEscrow([alicePXE, bobPXE], alice, clawback.address)) as EscrowContract;

    // register everything to both PXEs
    for (const pxe of [alicePXE, bobPXE]) {
      await pxe.registerContract(token);
      await pxe.registerContract(clawback);
      // TODO: ideally Bob doesn't know about the escrow yet
      await pxe.registerContract(escrow);

      await pxe.registerSender(escrow.address);
    }
    bob.setScopes([bob.getAddress(), escrow.address]);

    console.log({
      token: token.address,
      clawback: clawback.address,
      escrow: escrow.address,
    });
  });

  it('clawback ', async () => {
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

    // sync notes for alice and bob
    await clawback.withWallet(bob).methods.sync_notes().simulate({});
    await clawback.withWallet(alice).methods.sync_notes().simulate({});

    notes = await alice.getNotes({ contractAddress: clawback.address });
    expect(notes.length).toBe(1);
    expectClawbackNote(notes[0], alice.getAddress(), bob.getAddress(), escrow.address);

    notes = await bob.getNotes({ contractAddress: clawback.address });
    expect(notes.length).toBe(1);
    expectClawbackNote(notes[0], alice.getAddress(), bob.getAddress(), escrow.address);

    // TODO: assert nullifier is pushed

    // bob claims the escrow
    await clawback.withWallet(bob).methods.claim(escrow.address, token.address, wad(10)).send().wait();

    await expectTokenBalances(token, escrow.address, wad(0), wad(0));
    await expectTokenBalances(token, bob.getAddress(), wad(0), wad(10), bobWallet);
  }, 300_000);
});
