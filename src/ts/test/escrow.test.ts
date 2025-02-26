import { TokenContractArtifact, TokenContract } from '../../artifacts/Token.js';
import { EscrowContractArtifact, EscrowContract } from '../../artifacts/Escrow.js';
import {
  AccountWallet,
  createLogger,
  Fr,
  PXE,
  Logger,
  AztecAddress,
  AccountWalletWithSecretKey,
  Wallet,
} from '@aztec/aztec.js';
import { createAccount } from '@aztec/accounts/testing';
import { computePartialAddress, deriveKeys } from '@aztec/circuits.js';
import { createPXE, expectAddressNote, expectTokenBalances, expectUintNote, wad } from './utils.js';
import { deployToken } from './token.test.js';

async function deployEscrow(pxes: PXE[], wallet: Wallet, owner: AztecAddress) {
  const escrowSecretKey = Fr.random();
  const escrowPublicKeys = (await deriveKeys(escrowSecretKey)).publicKeys;
  const escrowDeployment = EscrowContract.deployWithPublicKeys(escrowPublicKeys, wallet, owner);
  const escrowInstance = await escrowDeployment.getInstance();

  await Promise.all(
    pxes.map(async (pxe) => pxe.registerAccount(escrowSecretKey, await computePartialAddress(escrowInstance))),
  );

  const escrowContract = await escrowDeployment.send().deployed();

  return escrowContract;
}

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
    token = (await deployToken(alice)) as TokenContract;

    // alice and bob know the token contract
    await alicePXE.registerContract({
      instance: token.instance,
      artifact: TokenContractArtifact,
    });
    await bobPXE.registerContract({
      instance: token.instance,
      artifact: TokenContractArtifact,
    });

    escrow = await deployEscrow([alicePXE, bobPXE], alice, bob.getAddress());

    // alice and bob know the escrow contract
    await alicePXE.registerContract({
      instance: escrow.instance,
      artifact: EscrowContractArtifact,
    });
    await bobPXE.registerContract({
      instance: escrow.instance,
      artifact: EscrowContractArtifact,
    });

    // bob knows alice and escrow
    await bobPXE.registerSender(escrow.address);
    await bobPXE.registerSender(alice.getAddress());

    bob.setScopes([bob.getAddress(), escrow.address]);
  });

  it('escrow', async () => {
    let events, notes;

    // this is here because the note is created in the constructor
    await escrow.withWallet(bob).methods.sync_notes().simulate({});

    // alice should have no notes
    notes = await alice.getNotes({ contractAddress: escrow.address });
    expect(notes.length).toBe(0);

    // bob should have a note with himself as owner, encrypted by escrow
    notes = await bob.getNotes({ contractAddress: escrow.address });
    expect(notes.length).toBe(1);
    expectAddressNote(notes[0], bob.getAddress(), bob.getAddress());

    // Fund escrow
    await token.withWallet(alice).methods.mint_to_private(alice.getAddress(), escrow.address, wad(10)).send().wait();

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
