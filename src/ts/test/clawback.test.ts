import { TokenContractArtifact, TokenContract } from '../../artifacts/Token.js';
import { EscrowContractArtifact, EscrowContract, PrivacyKeys } from '../../artifacts/Escrow.js';
import { ClawbackEscrowContractArtifact, ClawbackEscrowContract } from '../../artifacts/ClawbackEscrow.js';
import {
  AccountWallet,
  createLogger,
  Fr,
  PXE,
  Logger,
  AztecAddress,
  AccountWalletWithSecretKey,
  Wallet,
  Note,
  UniqueNote,
  ContractDeployer,
} from '@aztec/aztec.js';
import { createAccount } from '@aztec/accounts/testing';
import { computePartialAddress, deriveKeys, getContractInstanceFromDeployParams } from '@aztec/circuits.js';
import { createPXE, expectTokenBalances, logger, wad } from './utils.js';
import { deployToken } from './token.test.js';

async function deployEscrow(pxes: PXE[], deployerWallet: Wallet, owner: AztecAddress): Promise<EscrowContract> {
  const escrowSecretKey = Fr.random();
  const escrowPublicKeys = (await deriveKeys(escrowSecretKey)).publicKeys;
  const escrowDeployment = EscrowContract.deployWithPublicKeys(escrowPublicKeys, deployerWallet, owner);
  const escrowInstance = await escrowDeployment.getInstance();
  await Promise.all(
    pxes.map(async (pxe) => pxe.registerAccount(escrowSecretKey, await computePartialAddress(escrowInstance))),
  );

  const contractMetadata = await pxes[0].getContractMetadata(escrowInstance.address);
  expect(contractMetadata).toBeDefined();
  expect(contractMetadata.isContractPubliclyDeployed).toBeFalsy();

  const escrowContract = await escrowDeployment.send().deployed();
  logger.info('escrow deployed', escrowContract.address);
  return escrowContract;
}

async function deployClawbackEscrow(pxes: PXE[], wallet: Wallet) {
  const clawbackSecretKey = Fr.random();
  const clawbackPublicKeys = (await deriveKeys(clawbackSecretKey)).publicKeys;
  const clawbackDeployment = ClawbackEscrowContract.deployWithPublicKeys(clawbackPublicKeys, wallet);
  const clawbackInstance = await clawbackDeployment.getInstance();

  await Promise.all(
    pxes.map(async (pxe) => pxe.registerAccount(clawbackSecretKey, await computePartialAddress(clawbackInstance))),
  );

  const clawbackContract = await clawbackDeployment.send().deployed();

  logger.info(`clawback address: ${clawbackContract.address}`);

  return clawbackContract;
}

describe.only('Clawback Escrow - Multi PXE', () => {
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
    bobPXE = await createPXE(0);

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
    clawback = (await deployClawbackEscrow([alicePXE, bobPXE], alice)) as ClawbackEscrowContract;
    // escrow = await deployEscrow([alicePXE, bobPXE], alice, clawback.address) as EscrowContract;
    escrow = (await deployEscrow([alicePXE, bobPXE], alice, clawback.address)) as EscrowContract;
    console.log({
      token: token.address,
      clawback: clawback.address,
      escrow: escrow.address,
    });
    // alice and bob know the token contract
    await alicePXE.registerContract(token);
    await bobPXE.registerContract(token);

    await alicePXE.registerContract(escrow);
    await bobPXE.registerContract(escrow);

    await alicePXE.registerContract(clawback);
    await bobPXE.registerContract(clawback);

    await alicePXE.registerSender(clawback.address);
    await alicePXE.registerSender(escrow.address);

    await bobPXE.registerSender(clawback.address);
    await bobPXE.registerSender(alice.getAddress());

    bob.setScopes([bob.getAddress(), alice.getAddress(), escrow.address, clawback.address]);
  });

  const expectClawbackNote = (note: UniqueNote, sender: AztecAddress, receiver: AztecAddress, escrow: AztecAddress) => {
    // expect(note.note.items.length).toBe(3);
    expect(note.note.items[0]).toEqual(new Fr(sender.toBigInt()));
    expect(note.note.items[1]).toEqual(new Fr(receiver.toBigInt()));
    expect(note.note.items[2]).toEqual(new Fr(escrow.toBigInt()));
  };

  it('clawback ', async () => {
    let events, notes;

    // mint to alice
    await token
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), alice.getAddress(), wad(10))
      .send()
      .wait();
    await expectTokenBalances(token, alice.getAddress(), wad(0), wad(10));

    // fund escrow
    await token
      .withWallet(alice)
      .methods.transfer_private_to_private(alice.getAddress(), escrow.address, wad(10), 0)
      .send()
      .wait();
    await expectTokenBalances(token, escrow.address, wad(0), wad(10));

    // create the clawback escrow:
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

    // todo : assert nullifier is pushed

    // bob claims the escrow
    await clawback.withWallet(bob).methods.claim(escrow.address, token.address, wad(10)).send().wait();

    await expectTokenBalances(token, escrow.address, wad(0), wad(0));
    await expectTokenBalances(token, bob.getAddress(), wad(0), wad(10), bobWallet);
  }, 300_000);
});
