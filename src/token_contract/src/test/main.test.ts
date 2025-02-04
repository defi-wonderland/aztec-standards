import { TokenContractArtifact, TokenContract, Transfer } from '../../../artifacts/Token.js';
import {
  AccountWallet,
  CompleteAddress,
  ContractDeployer,
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
import { createAccount, getInitialTestAccountsWallets } from '@aztec/accounts/testing';
import {
  computePartialAddress,
  deriveKeys,
  deriveMasterIncomingViewingSecretKey,
  derivePublicKeyFromSecretKey,
} from '@aztec/circuits.js';
import { EscrowContract, EscrowContractArtifact } from '@aztec/noir-contracts.js/Escrow';
import { ContractInstanceDeployerContract } from '@aztec/noir-contracts.js/ContractInstanceDeployer';

const startPXE = async (id: number = 0) => {
  const { PXE_URL = `http://localhost:${8080 + id}` } = process.env;
  const pxe = createPXEClient(PXE_URL);
  await waitForPXE(pxe);
  return pxe;
};

const setupSandbox = async () => {
  return startPXE();
};

async function deployToken(deployer: AccountWallet, minter: AztecAddress) {
  const contract = await Contract.deploy(deployer, TokenContractArtifact, [minter, 'PrivateToken', 'PT', 18])
    .send()
    .deployed();
  console.log('Token contract deployed at', contract.address);
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
  // await pxe.registerAccount(escrowSecretKey, await computePartialAddress(escrowInstance));

  const escrowContract = await escrowDeployment.send().deployed();
  console.log(`Escrow contract deployed at ${escrowContract.address}`);

  return escrowContract;
}

describe('Token', () => {
  let pxe: PXE;
  let wallets: AccountWalletWithSecretKey[] = [];
  let accounts: CompleteAddress[] = [];

  let alice: AccountWallet;
  let bob: AccountWallet;
  let carl: AccountWallet;

  let token: TokenContract;

  const AMOUNT = 1000n;

  let logger: Logger;

  beforeAll(async () => {
    logger = createLogger('aztec:aztec-starter');
    logger.info('Aztec-Starter tests running.');

    pxe = await setupSandbox();

    wallets = await getInitialTestAccountsWallets(pxe);
    accounts = wallets.map((w) => w.getCompleteAddress());

    alice = wallets[0];
    bob = wallets[1];
    carl = wallets[2];
  });

  beforeEach(async () => {
    token = (await deployToken(alice, alice.getAddress())) as TokenContract;
  });

  it('deploys the contract', async () => {
    const salt = Fr.random();
    const [deployerWallet] = wallets; // using first account as deployer

    const deploymentData = await getContractInstanceFromDeployParams(TokenContractArtifact, {
      constructorArgs: [deployerWallet.getAddress(), 'PrivateToken', 'PT', 18],
      salt,
      deployer: deployerWallet.getAddress(),
    });
    const deployer = new ContractDeployer(TokenContractArtifact, deployerWallet);
    const tx = deployer
      .deploy(deployerWallet.getAddress(), 'PrivateToken', 'PT', 18)
      .send({ contractAddressSalt: salt });
    const receipt = await tx.getReceipt();

    expect(receipt).toEqual(
      expect.objectContaining({
        status: TxStatus.PENDING,
        error: '',
      }),
    );

    const receiptAfterMined = await tx.wait({ wallet: deployerWallet });

    expect(await pxe.getContractInstance(deploymentData.address)).toBeDefined();
    expect(await pxe.isContractPubliclyDeployed(deploymentData.address)).toBeTruthy();
    expect(receiptAfterMined).toEqual(
      expect.objectContaining({
        status: TxStatus.SUCCESS,
      }),
    );

    expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
  }, 300_000);

  it('mints', async () => {
    await token.withWallet(alice);
    const tx = await token.methods.mint_to_public(bob.getAddress(), AMOUNT).send().wait();
    const balance = await token.methods.balance_of_public(bob.getAddress()).simulate();
    expect(balance).toBe(AMOUNT);
  }, 300_000);

  it('transfers tokens between public accounts', async () => {
    // First mint 2 tokens to alice
    await token
      .withWallet(alice)
      .methods.mint_to_public(alice.getAddress(), AMOUNT * 2n)
      .send()
      .wait();

    // Transfer 1 token from alice to bob
    await token
      .withWallet(alice)
      .methods.transfer_in_public(alice.getAddress(), bob.getAddress(), AMOUNT, 0)
      .send()
      .wait();

    // Check balances are correct
    const aliceBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
    const bobBalance = await token.methods.balance_of_public(bob.getAddress()).simulate();

    expect(aliceBalance).toBe(AMOUNT);
    expect(bobBalance).toBe(AMOUNT);
  }, 300_000);

  it('burns public tokens', async () => {
    // First mint 2 tokens to alice
    await token
      .withWallet(alice)
      .methods.mint_to_public(alice.getAddress(), AMOUNT * 2n)
      .send()
      .wait();

    // Burn 1 token from alice
    await token.withWallet(alice).methods.burn_public(alice.getAddress(), AMOUNT, 0).send().wait();

    // Check balance and total supply are reduced
    const aliceBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
    const totalSupply = await token.methods.total_supply().simulate();

    expect(aliceBalance).toBe(AMOUNT);
    expect(totalSupply).toBe(AMOUNT);
  }, 300_000);

  it('transfers tokens from private to public balance', async () => {
    // First mint to private 2 tokens to alice
    await token
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), alice.getAddress(), AMOUNT * 2n)
      .send()
      .wait();

    // Transfer 1 token from alice's private balance to public balance
    await token
      .withWallet(alice)
      .methods.transfer_to_public(alice.getAddress(), alice.getAddress(), AMOUNT, 0)
      .send()
      .wait();

    // Check public balance is correct
    const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
    expect(alicePublicBalance).toBe(AMOUNT);

    // Check total supply hasn't changed
    const totalSupply = await token.methods.total_supply().simulate();
    expect(totalSupply).toBe(AMOUNT * 2n);
  }, 300_000);

  it('fails when using an invalid nonce', async () => {
    // Mint 1 token privately to alice
    await token.withWallet(alice).methods.mint_to_private(alice.getAddress(), alice.getAddress(), AMOUNT).send().wait();

    // This fails because of the nonce check
    await expect(
      token
        .withWallet(alice)
        .methods.transfer_to_public(alice.getAddress(), alice.getAddress(), AMOUNT * 2n, 1)
        .send()
        .wait(),
    ).rejects.toThrow(/invalid nonce/);
  }, 300_000);

  it('fails when transferring more tokens than available in private balance', async () => {
    // Mint 1 token privately to alice
    await token.withWallet(alice).methods.mint_to_private(alice.getAddress(), alice.getAddress(), AMOUNT).send().wait();

    // Try to transfer more tokens than available from private to public balance
    await expect(
      token
        .withWallet(alice)
        .methods.transfer_to_public(alice.getAddress(), alice.getAddress(), AMOUNT + 1n, 0)
        .send()
        .wait(),
    ).rejects.toThrow(/Balance too low/);
  }, 300_000);

  it('can transfer tokens between private balances', async () => {
    // Mint 2 tokens privately to alice
    await token
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), alice.getAddress(), AMOUNT * 2n)
      .send()
      .wait();

    // Transfer 1 token from alice to bob's private balance
    await token.withWallet(alice).methods.transfer(bob.getAddress(), AMOUNT).send().wait();

    // Try to transfer more than available balance
    await expect(
      token
        .withWallet(alice)
        .methods.transfer(bob.getAddress(), AMOUNT + 1n)
        .send()
        .wait(),
    ).rejects.toThrow(/Balance too low/);

    // Check total supply hasn't changed
    const totalSupply = await token.methods.total_supply().simulate();
    expect(totalSupply).toBe(AMOUNT * 2n);
  }, 300_000);

  it('can mint tokens to private balance', async () => {
    // Mint 2 tokens privately to alice
    await token
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), alice.getAddress(), AMOUNT * 2n)
      .send()
      .wait();

    // Check total supply increased
    const totalSupply = await token.methods.total_supply().simulate();
    expect(totalSupply).toBe(AMOUNT * 2n);

    // Public balance should be 0 since we minted privately
    const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
    expect(alicePublicBalance).toBe(0n);
  }, 300_000);

  it('can burn tokens from private balance', async () => {
    // Mint 2 tokens privately to alice
    await token
      .withWallet(alice)
      .methods.mint_to_private(alice.getAddress(), alice.getAddress(), AMOUNT * 2n)
      .send()
      .wait();

    // Burn 1 token from alice's private balance
    await token.withWallet(alice).methods.burn_private(alice.getAddress(), AMOUNT, 0).send().wait();

    // Try to burn more than available balance
    await expect(
      token
        .withWallet(alice)
        .methods.burn_private(alice.getAddress(), AMOUNT * 2n, 0)
        .send()
        .wait(),
    ).rejects.toThrow(/Balance too low/);

    // Check total supply decreased
    const totalSupply = await token.methods.total_supply().simulate();
    expect(totalSupply).toBe(AMOUNT);

    // Public balance should still be 0
    const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
    expect(alicePublicBalance).toBe(0n);
  }, 300_000);

  it('can transfer tokens from public to private balance', async () => {
    // Mint 2 tokens publicly to alice
    await token
      .withWallet(alice)
      .methods.mint_to_public(alice.getAddress(), AMOUNT * 2n)
      .send()
      .wait();

    // Transfer 1 token from alice's public balance to private balance
    await token.withWallet(alice).methods.transfer_to_private(alice.getAddress(), AMOUNT).send().wait();

    // Try to transfer more than available public balance
    await expect(
      token
        .withWallet(alice)
        .methods.transfer_to_private(alice.getAddress(), AMOUNT * 2n)
        .send()
        .wait(),
    ).rejects.toThrow(/attempt to subtract with underflow/);

    // Check total supply stayed the same
    const totalSupply = await token.methods.total_supply().simulate();
    expect(totalSupply).toBe(AMOUNT * 2n);

    // Public balance should be reduced by transferred amount
    const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
    expect(alicePublicBalance).toBe(AMOUNT);
  }, 300_000);

  it.skip('mint in public, prepare partial note and finalize it', async () => {
    await token.withWallet(alice);

    await token.methods.mint_to_public(alice.getAddress(), AMOUNT).send().wait();

    // alice has tokens in public
    expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(AMOUNT);
    expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(0n);
    // bob has 0 tokens
    expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(0n);
    expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(0n);

    expect(await token.methods.total_supply().simulate()).toBe(AMOUNT);

    // alice prepares partial note for bob
    await token.methods.prepare_private_balance_increase(bob.getAddress(), alice.getAddress()).send().wait();

    // alice still has tokens in public
    expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(AMOUNT);

    // TODO: i removed the event, so I need anoter way to figure out the hiding point slot to finalize the note
    // read bob's encrypted logs
    // const bobEncryptedEvents = await bob.getPrivateEvents<PreparePrivateBalanceIncrease>(
    //     TokenContract.events.PreparePrivateBalanceIncrease,
    //     1,
    //     100 // todo: add a default value for limit?
    // )
    // get the latest event
    // const latestEvent = bobEncryptedEvents[bobEncryptedEvents.length - 1]
    // finalize partial note passing the hiding point slot
    // await token.methods.finalize_transfer_to_private(AMOUNT, latestEvent.hiding_point_slot).send().wait();

    // alice now has no tokens
    // expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(0n);
    // // bob has tokens in private
    // expect(await token.methods.balance_of_public(bob.getAddress()).simulate()).toBe(0n);
    // expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(AMOUNT);
    // // total supply is still the same
    // expect(await token.methods.total_supply().simulate()).toBe(AMOUNT);
  }, 300_000);

  it('public transfer with authwitness', async () => {
    await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), AMOUNT).send().wait();

    const nonce = Fr.random();
    const action = token
      .withWallet(carl)
      .methods.transfer_in_public(alice.getAddress(), bob.getAddress(), AMOUNT, nonce);

    await alice
      .setPublicAuthWit(
        {
          caller: carl.getAddress(),
          action,
        },
        true,
      )
      .send()
      .wait();

    await action.send().wait();

    expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(0n);
    expect(await token.methods.balance_of_public(bob.getAddress()).simulate()).toBe(AMOUNT);
  }, 300_000);

  it('private transfer with authwitness', async () => {
    // setup balances
    await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), AMOUNT).send().wait();
    await token.withWallet(alice).methods.transfer_to_private(alice.getAddress(), AMOUNT).send().wait();

    expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(AMOUNT);

    // prepare action
    const nonce = Fr.random();
    const action = token
      .withWallet(carl)
      .methods.transfer_in_private(alice.getAddress(), bob.getAddress(), AMOUNT, nonce);

    const witness = await alice.createAuthWit({
      caller: carl.getAddress(),
      action,
    });

    const validity = await alice.lookupValidity(alice.getAddress(), {
      caller: carl.getAddress(),
      action,
    });
    expect(validity.isValidInPrivate).toBeTruthy();
    expect(validity.isValidInPublic).toBeFalsy();

    // dev: This grants carl access to alice's private notes
    carl.setScopes([carl.getAddress(), alice.getAddress()]);

    await action.send().wait();

    expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(0n);
    expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(AMOUNT);
  }, 300_000);
});

describe.only('Multi PXE', () => {
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

    alicePXE = await startPXE(0);
    bobPXE = await startPXE(1);

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
    token = (await deployToken(alice, alice.getAddress())) as TokenContract;

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
    // await alicePXE.registerAccount(bobWallet.getSecretKey(), bob.getCompleteAddress().partialAddress);
    // alicePXE.registerSender(bob.getAddress());

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
    // 4th element of items is randomness, so we slice the first 3
    // dev: why the second element is always 0?
    expect(note.note.items.slice(0, 3)).toStrictEqual([new Fr(amount), new Fr(0), new Fr(owner.toBigInt())]);
  };

  const expectBalances = async (address: AztecAddress, publicBalance: bigint, privateBalance: bigint) => {
    logger.info('checking balances for', address.toString());
    expect(await token.methods.balance_of_public(address).simulate()).toBe(publicBalance);
    expect(await token.methods.balance_of_private(address).simulate()).toBe(privateBalance);
  };

  const wad = (n: number = 1) => AMOUNT * BigInt(n);

  it('transfers', async () => {
    // mint initial amount
    await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), wad(10)).send().wait();

    let events, notes;

    // move public 5 tokens to private
    const aliceShieldTx = await token.methods.transfer_to_private(alice.getAddress(), wad(5)).send().wait();
    // await token.methods.sync_notes().simulate({})

    // assert balances
    await expectBalances(alice.getAddress(), wad(5), wad(5));

    // retrieve notes from last tx
    notes = await alice.getNotes({ txHash: aliceShieldTx.txHash });
    expect(notes.length).toBe(1);
    expectNote(notes[0], wad(5), alice.getAddress());

    // `transfer_to_private` does not emit an event
    events = await alice.getPrivateEvents<Transfer>(TokenContract.events.Transfer, aliceShieldTx.blockNumber!, 2);
    expect(events.length).toBe(0);

    // `transfer_to_private`

    // transfer some private tokens to bob
    const fundBobTx = await token.withWallet(alice).methods.transfer_to_private(bob.getAddress(), wad(5)).send().wait();

    await token.withWallet(alice).methods.sync_notes().simulate({});
    await token.withWallet(bob).methods.sync_notes().simulate({});

    notes = await alice.getNotes({ txHash: fundBobTx.txHash });
    // console.log(notes)
    expect(notes.length).toBe(0);

    notes = await bob.getNotes({ txHash: fundBobTx.txHash });
    // console.log(notes)
    expect(notes.length).toBe(1);
    expectNote(notes[0], wad(5), bob.getAddress());

    events = await bob.getPrivateEvents<Transfer>(TokenContract.events.Transfer, fundBobTx.blockNumber!, 2);
    expect(events.length).toBe(0);

    // assert balances
    await expectBalances(alice.getAddress(), wad(0), wad(5));
    await expectBalances(bob.getAddress(), wad(0), wad(0));

    // `transfer`

    // This will emit an event encrypted by alice to bob, and also create a note with bob as owner
    const fundBobTx2 = await token.withWallet(alice).methods.transfer(bob.getAddress(), wad(5)).send().wait({
      debug: true,
    });

    // dev: i think this tells PXE to sync notes from token contract
    await token.withWallet(alice).methods.sync_notes().simulate({});
    await token.withWallet(bob).methods.sync_notes().simulate({});

    // Alice shouldn't have any notes because it not a sender/registered account in her PXE
    notes = await alice.getNotes({ txHash: fundBobTx2.txHash });
    // console.log(notes)
    expect(notes.length).toBe(0);
    // expectNote(notes[0], wad(5), alice.getAddress())

    // Bob should have a note with himself as owner
    // Q: why noteTypeId is always `Selector<0x00000000>`?
    notes = await bob.getNotes({ txHash: fundBobTx2.txHash });
    // console.log(notes)
    expect(notes.length).toBe(1);
    expectNote(notes[0], wad(5), bob.getAddress());

    events = await bob.getPrivateEvents<Transfer>(TokenContract.events.Transfer, fundBobTx2.blockNumber!, 2);
    expect(events.length).toBe(1);
    // Q: how do I cast `from` and `to` to AztecAddres?
    expect(events[0]).toEqual({
      from: alice.getAddress().toBigInt(),
      to: bob.getAddress().toBigInt(),
      amount: wad(5),
    });

    // assert alice's balances again
    // dev: ahhh `transfer` actually takes the amount from the sender's PUBLIC balance
    expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(wad(0));
    expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(wad(0));

    // assert bob's balances
    // dev: both bob's balance are still 0, although he has a note with 5 tokens
    // const transfer2Tx = await token.withWallet(bob).methods.transfer_to_private(bob.getAddress(), wad(5)).send().wait({
    //   debug: true
    // })
    // console.log(transfer2Tx)

    expect(await token.withWallet(bob).methods.balance_of_public(bob.getAddress()).simulate()).toBe(0n);
    expect(await token.withWallet(bob).methods.balance_of_private(bob.getAddress()).simulate()).toBe(wad(10));
  }, 300_000);

  it('escrow', async () => {
    let events, notes;

    // this is here because the note is created in the constructor
    await escrow.withWallet(alice).methods.sync_notes().simulate({});
    await escrow.withWallet(bob).methods.sync_notes().simulate({});

    // alice should have no notes
    notes = await alice.getNotes({ contractAddress: escrow.address });
    expect(notes.length).toBe(0);
    // expectAddressNote(notes[0], bob.getAddress(), bob.getAddress());

    // bob should have a note with himself as owner, encrypted by alice
    notes = await bob.getNotes({ contractAddress: escrow.address });
    expect(notes.length).toBe(1);
    expectAddressNote(notes[0], bob.getAddress(), bob.getAddress());

    // mint initial amount
    await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), wad(10)).send().wait();

    await token.methods.transfer_to_private(alice.getAddress(), wad(5)).send().wait();
    await token.withWallet(alice).methods.sync_notes().simulate({});

    // assert balances
    await expectBalances(alice.getAddress(), wad(5), wad(5));
    await expectBalances(bob.getAddress(), wad(0), wad(0));

    // Transfer both in private and public
    const fundEscrowTx = await token
      .withWallet(alice)
      .methods.transfer_in_private(alice.getAddress(), escrow.address, wad(5), 0)
      .send()
      .wait({
        debug: true,
      });

    const fundEscrowTx2 = await token
      .withWallet(alice)
      .methods.transfer_in_public(alice.getAddress(), escrow.address, wad(5), 0)
      .send()
      .wait({
        debug: true,
      });

    // console.log(fundEscrowTx.debugInfo)
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
    console.log(withdrawTx.debugInfo);
  }, 300_000);
});
