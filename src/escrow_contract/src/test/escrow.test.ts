import { TokenContractArtifact, TokenContract } from '../../../artifacts/Token.js';
import { EscrowContractArtifact, EscrowContract } from '../../../artifacts/Escrow.js';
import {
  AccountWallet,
  createLogger,
  Fr,
  PXE,
  waitForPXE,
  createPXEClient,
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

    aliceWallet = await createAccount(alicePXE);
    bobWallet = await createAccount(bobPXE);

    alice = aliceWallet;
    bob = bobWallet;

    console.log({
      alice: aliceWallet.getAddress(),
      bob: bobWallet.getAddress(),
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
    bobPXE.registerSender(escrow.address);
    bobPXE.registerSender(alice.getAddress());

    bob.setScopes([bob.getAddress(), escrow.address]);
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

  const expectBalances = async (
    address: AztecAddress,
    publicBalance: bigint,
    privateBalance: bigint,
    accountWallet: AccountWallet,
  ) => {
    logger.info('checking balances for', address.toString());
    expect(await token.withWallet(accountWallet).methods.balance_of_public(address).simulate()).toBe(publicBalance);
    expect(await token.withWallet(accountWallet).methods.balance_of_private(address).simulate()).toBe(privateBalance);
  };

  const wad = (n: number = 1) => AMOUNT * BigInt(n);

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

    // mint initial amount
    await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), wad(10)).send().wait();

    await token
      .withWallet(alice)
      .methods.transfer_public_to_private(alice.getAddress(), alice.getAddress(), wad(10), 0)
      .send()
      .wait();
    await token.withWallet(alice).methods.sync_notes().simulate({});

    // assert balances
    await expectBalances(alice.getAddress(), wad(0), wad(10), aliceWallet);
    await expectBalances(bob.getAddress(), wad(0), wad(0), bobWallet);

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
      .methods.transfer_private_to_private(alice.getAddress(), escrow.address, wad(5), 0)
      .send()
      .wait({
        debug: true,
      });

    await token.withWallet(alice).methods.sync_notes().simulate({});
    await token.withWallet(bob).methods.sync_notes().simulate({});

    // assert balances, alice 0 and 0, escrow 0 and 10
    await expectBalances(alice.getAddress(), wad(0), wad(0), aliceWallet);
    await expectBalances(escrow.address, wad(0), wad(10), aliceWallet);
    await expectBalances(escrow.address, wad(0), wad(10), bobWallet);

    // alice should have a note with escrow as owner (why alice can see the escrow's note?)
    notes = await alice.getNotes({ contractAddress: token.address });
    expect(notes.length).toBe(2);
    expectNote(notes[0], wad(5), escrow.address);
    expectNote(notes[1], wad(5), escrow.address);

    await escrow.withWallet(alice).methods.sync_notes().simulate({});
    await escrow.withWallet(bob).methods.sync_notes().simulate({});

    notes = await alice.getNotes({ owner: escrow.address });
    expect(notes.length).toBe(2);
    expectNote(notes[0], wad(5), escrow.address);
    expectNote(notes[1], wad(5), escrow.address);

    notes = await bob.getNotes({ owner: escrow.address });
    expect(notes.length).toBe(2);
    expectNote(notes[0], wad(5), escrow.address);
    expectNote(notes[1], wad(5), escrow.address);

    // withdraw 7 from the escrow
    const withdrawTx = await escrow
      .withWallet(bob)
      .methods.withdraw(token.address, wad(7), bob.getAddress())
      .send()
      .wait({
        debug: true,
      });

    await expectBalances(escrow.address, wad(0), wad(3), aliceWallet);
    await expectBalances(escrow.address, wad(0), wad(3), bobWallet);
    await expectBalances(bob.getAddress(), wad(0), wad(7), bobWallet);
  }, 300_000);
});
