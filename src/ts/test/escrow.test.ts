import { TokenContract } from '../../artifacts/Token.js';
import { EscrowContract, EscrowKeys } from '../../artifacts/Escrow.js';
import { AccountWallet, PXE, Logger, AccountWalletWithSecretKey, Fr } from '@aztec/aztec.js';
import { createAccount } from '@aztec/accounts/testing';
import { createPXE, deployEscrow, expectAccountNote, expectTokenBalances, wad } from './utils.js';
import { deployToken } from './token.test.js';

describe('Escrow - Multi PXE', () => {
  let alicePXE: PXE;
  let bobPXE: PXE;

  let aliceWallet: AccountWalletWithSecretKey;
  let bobWallet: AccountWalletWithSecretKey;

  let alice: AccountWallet;
  let bob: AccountWallet;
  let carl: AccountWallet;

  let token: TokenContract;
  let escrow: EscrowContract;

  let logger: Logger;

  beforeAll(async () => {
    alicePXE = await createPXE(0);
    bobPXE = await createPXE(1);

    aliceWallet = await createAccount(alicePXE);
    bobWallet = await createAccount(bobPXE);

    alice = aliceWallet;
    bob = bobWallet;

    console.log({
      alice: alice.getAddress(),
      bob: bob.getAddress(),
    });
  });

  beforeEach(async () => {
    token = await deployToken(alice);
    escrow = await deployEscrow(alice, bob.getAddress());

    // alice and bob know the token contract
    await alicePXE.registerContract(token);
    await bobPXE.registerContract(token);

    // alice and bob know the escrow contract
    await alicePXE.registerContract(escrow);
    await bobPXE.registerContract(escrow);

    // bob knows alice and escrow
    await bobPXE.registerSender(escrow.address);
    await bobPXE.registerSender(alice.getAddress());

    bob.setScopes([bob.getAddress(), escrow.address]);
  });

  it('escrow', async () => {
    let notes;
    // Fund escrow
    await token.withWallet(alice).methods.mint_to_private(alice.getAddress(), escrow.address, wad(10)).send().wait();

    // make alice sync the notes and retrieve the AccountNote stored in the Escrow, which contains the escrow secret
    alice.setScopes([alice.getAddress(), escrow.address]);
    await escrow.withWallet(alice).methods.sync_notes().simulate({});
    notes = await alice.getNotes({ owner: escrow.address });
    expectAccountNote(notes[0], bob.getAddress());
    const accountNote = notes[0];

    // Only the escrow's owner call `leak_keys`, but Bob doesn't have the escrow's account registered yet
    // so we obtain the escrow secret from the AccountNote (retrieved above by alice) and register it in Bob's PXE.
    const escrowSecretKey = accountNote.note.items[1];
    await bob.registerAccount(escrowSecretKey, await escrow.partialAddress);
    bob.setScopes([bob.getAddress(), escrow.address]);

    // now Bob (escrow's owner) can leak the escrow's secret keys to himself
    const leakTx = await escrow.withWallet(bob).methods.leak_keys(bob.getAddress()).send().wait();

    // Bob should now have received private log with the escrow's secret keys in the leakTx
    const events = await bob.getPrivateEvents<EscrowKeys>(EscrowContract.events.EscrowKeys, leakTx.blockNumber!, 10);
    expect(events.length).toBe(1);
    let escrowSecreKeyEvent = events[0];
    // check the secret retrieved from the AccountNote matches the secret leaked in the private log
    expect(Fr.fromString(escrowSecreKeyEvent.escrow_secret.toString())).toStrictEqual(escrowSecretKey);

    // withdraw 7 from the escrow
    const withdrawTx = await escrow
      .withWallet(bob)
      .methods.withdraw(token.address, wad(7), bob.getAddress())
      .send()
      .wait({
        debug: true,
      });

    await expectTokenBalances(token, escrow.address, wad(0), wad(3), bobWallet);
    await expectTokenBalances(token, bob.getAddress(), wad(0), wad(7), bobWallet);
  }, 300_000);
});
