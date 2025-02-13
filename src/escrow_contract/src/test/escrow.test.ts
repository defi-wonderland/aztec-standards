import { TokenContractArtifact, TokenContract } from '../../../artifacts/Token.js';
import { EscrowContractArtifact, EscrowContract } from '../../../artifacts/Escrow.js';
import {
  AccountWallet,
  createLogger,
  Fr,
  PXE,
  waitForPXE,
  TxStatus,
  createPXEClient,
  getContractInstanceFromDeployParams,
  Logger,
  Contract,
  AztecAddress,
  AccountWalletWithSecretKey,
  Wallet,
  UniqueNote,
} from '@aztec/aztec.js';
import { createAccount } from '@aztec/accounts/testing';
import { computePartialAddress, deriveKeys } from '@aztec/circuits.js';

const createPXE = async (id: number = 0) => {
  // TODO: we should probably define testing fixtures for this kind of configuration
  const { BASE_PXE_URL = `http://localhost` } = process.env;
  const url = `${BASE_PXE_URL}:${8080 + id}`;
  const pxe = createPXEClient(url);
  await waitForPXE(pxe);
  return pxe;
};

const setupSandbox = async () => {
  return createPXE();
};

async function deployToken(deployer: AccountWallet) {
  const contract = await Contract.deploy(deployer, TokenContractArtifact, ['PrivateToken', 'PT', 18]).send().deployed();
  return contract;
}

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

describe('Multi PXE', () => {
  let alicePXE: PXE;
  let bobPXE: PXE;

  let aliceWallet: AccountWalletWithSecretKey;
  let bobWallet: AccountWalletWithSecretKey;

  let alice: AccountWallet;
  let bob: AccountWallet;
  let carl: AccountWallet;

  let token: TokenContract;
  let escrow: EscrowContract;
  const AMOUNT = 1000n;

  let logger: Logger;

  beforeAll(async () => {
    logger = createLogger('aztec:aztec-starter');
    logger.info('Aztec-Starter tests running.');

    alicePXE = await createPXE(0);
    bobPXE = await createPXE(1);

    // TODO: assert that the used PXEs are actually separate instances?

    aliceWallet = await createAccount(alicePXE);
    bobWallet = await createAccount(bobPXE);

    alice = aliceWallet;
    bob = bobWallet;
  });

  beforeEach(async () => {
    token = (await deployToken(alice)) as TokenContract;

    await bobPXE.registerContract(token);

    escrow = await deployEscrow([alicePXE, bobPXE], alice, bob.getAddress());
    await bobPXE.registerContract({
      instance: escrow.instance,
      artifact: EscrowContractArtifact,
    });
    await alicePXE.registerContract({
      instance: escrow.instance,
      artifact: EscrowContractArtifact,
    });

    // alice knows bob
    await alicePXE.registerAccount(bobWallet.getSecretKey(), bob.getCompleteAddress().partialAddress);
    alicePXE.registerSender(bob.getAddress());
    alice.setScopes([
      alice.getAddress(),
      bob.getAddress(),
      // token.address,
    ]);
    // bob knows alice
    await bobPXE.registerAccount(aliceWallet.getSecretKey(), alice.getCompleteAddress().partialAddress);
    bobPXE.registerSender(alice.getAddress());

    bob.setScopes([
      bob.getAddress(),
      alice.getAddress(),
      // token.address
      escrow.address,
    ]);
  });

  const expectAddressNote = (note: UniqueNote, address: AztecAddress, owner: AztecAddress) => {
    logger.info('checking address note {} {}', [address, owner]);
    expect(note.note.items[0]).toEqual(new Fr(address.toBigInt()));
    expect(note.note.items[1]).toEqual(new Fr(owner.toBigInt()));
  };

  const expectNote = (note: UniqueNote, amount: bigint, owner: AztecAddress) => {
    // 3th element of items is randomness, so we slice the first 2
    expect(note.note.items.slice(0, 2)).toStrictEqual([new Fr(amount), new Fr(owner.toBigInt())]);
  };

  const expectBalances = async (address: AztecAddress, publicBalance: bigint, privateBalance: bigint) => {
    logger.info('checking balances for', address.toString());
    expect(await token.methods.balance_of_public(address).simulate()).toBe(publicBalance);
    expect(await token.methods.balance_of_private(address).simulate()).toBe(privateBalance);
  };

  const wad = (n: number = 1) => AMOUNT * BigInt(n);

  it('escrow', async () => {
    let events, notes;

    // this is here because the note is created in the constructor
    await escrow.withWallet(alice).methods.sync_notes().simulate({});
    await escrow.withWallet(bob).methods.sync_notes().simulate({});

    // alice should have no notes (But it has because I gave it access to Bob's notes)
    notes = await alice.getNotes({ contractAddress: escrow.address });
    expect(notes.length).toBe(1);
    expectAddressNote(notes[0], bob.getAddress(), bob.getAddress());

    // bob should have a note with himself as owner, encrypted by alice
    notes = await bob.getNotes({ contractAddress: escrow.address });
    expect(notes.length).toBe(1);
    expectAddressNote(notes[0], bob.getAddress(), bob.getAddress());

    // mint initial amount
    await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), wad(10)).send().wait();

    await token
      .withWallet(alice)
      .methods.transfer_public_to_private(alice.getAddress(), alice.getAddress(), wad(5), 0)
      .send()
      .wait();
    await token.withWallet(alice).methods.sync_notes().simulate({});

    // assert balances
    await expectBalances(alice.getAddress(), wad(5), wad(5));
    await expectBalances(bob.getAddress(), wad(0), wad(0));

    // Transfer both in private and public
    const fundEscrowTx = await token
      .withWallet(alice)
      .methods.transfer_private_to_private(alice.getAddress(), escrow.address, wad(5), 0)
      .send()
      .wait({
        debug: true,
      });

    const fundEscrowTx2 = await token
      .withWallet(alice)
      .methods.transfer_public_to_public(alice.getAddress(), escrow.address, wad(5), 0)
      .send()
      .wait({
        debug: true,
      });

    await token.withWallet(alice).methods.sync_notes().simulate({});

    // assert balances, alice 0 and 0, escrow 5 and 5
    await expectBalances(alice.getAddress(), wad(0), wad(0));
    await expectBalances(escrow.address, wad(5), wad(5));

    // alice should have a note with escrow as owner (why alice can see the escrow's note?)
    notes = await alice.getNotes({ contractAddress: token.address });
    expect(notes.length).toBe(1);
    expectNote(notes[0], wad(5), escrow.address);

    await escrow.withWallet(alice).methods.sync_notes().simulate({});
    await escrow.withWallet(bob).methods.sync_notes().simulate({});

    // Q: why only alice can see the escrow's notes if both have the escrow registered?
    notes = await alice.getNotes({ owner: escrow.address });
    expect(notes.length).toBe(1);
    expectNote(notes[0], wad(5), escrow.address);

    notes = await bob.getNotes({ owner: escrow.address });
    expect(notes.length).toBe(0);

    // withdraw 1 from the escrow
    const withdrawTx = await escrow
      .withWallet(bob)
      .methods.withdraw(token.address, wad(1), bob.getAddress())
      .send()
      .wait({
        debug: true,
      });

    await expectBalances(escrow.address, wad(5), wad(4));
    await expectBalances(bob.getAddress(), wad(0), wad(1));
  }, 300_000);
});
