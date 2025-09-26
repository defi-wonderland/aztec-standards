import {
  Fr,
  TxStatus,
  AccountWalletWithSecretKey,
  AztecAddress,
  PublicKeys,
  computeAddress,
  deriveKeys,
} from '@aztec/aztec.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { EscrowContract, EscrowContractArtifact } from '../../../artifacts/Escrow.js';
import { TokenContract } from '../../../artifacts/Token.js';
import { ClawbackLogicContract } from '../../../artifacts/ClawbackLogic.js';
import { setupPXE, deployTokenWithMinter } from '../../ts/test/utils.js';

const ESCROW_AMOUNT = 1000n;
const PARTIAL_AMOUNT = 500n;

// Helper function to generate master secret keys for escrow
function generateMasterSecretKeys(): [Fr, Fr, Fr, Fr] {
  return [Fr.random(), Fr.random(), Fr.random(), Fr.random()];
}

// Helper function to compute escrow address from keys
function computeEscrowAddress(keys: [Fr, Fr, Fr, Fr]): { address: AztecAddress; publicKeys: PublicKeys } {
  const [nsk_m, ivsk_m, ovsk_m, tsk_m] = keys;
  const derivedKeys = deriveKeys(nsk_m, ivsk_m, ovsk_m, tsk_m);
  const publicKeys = derivedKeys.publicKeys;
  const address = computeAddress(publicKeys, EscrowContractArtifact);
  return { address, publicKeys };
}

// Helper function to deploy escrow with salt
async function deployEscrowWithSalt(
  deployer: AccountWalletWithSecretKey,
  salt: Fr,
  publicKeys: PublicKeys,
): Promise<EscrowContract> {
  const escrow = await EscrowContract.deployWithPublicKeys(publicKeys, deployer)
    .send({ contractAddressSalt: salt })
    .deployed();
  return escrow;
}

// Helper to wait for time to pass (simulate deadline)
async function waitForBlockTime(seconds: number) {
  // In a real test environment, you'd use time manipulation tools
  // For this example, we'll use a small delay to simulate time passing
  await new Promise((resolve) => setTimeout(resolve, seconds * 100)); // Speed up for tests
}

const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const managers = await getInitialTestAccountsManagers(pxe);
  const wallets = await Promise.all(managers.map((acc) => acc.register()));

  return { pxe, store, wallets };
};

describe('Clawback Escrow - Complete Flow Tests', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;
  let wallets: AccountWalletWithSecretKey[];

  let alice: AccountWalletWithSecretKey; // Escrow owner/creator
  let bob: AccountWalletWithSecretKey; // Recipient
  let charlie: AccountWalletWithSecretKey; // Third party observer

  let token: TokenContract;
  let logicContract: ClawbackLogicContract;

  beforeAll(async () => {
    ({ pxe, store, wallets } = await setupTestSuite());
    [alice, bob, charlie] = wallets;
  }, 100_000);

  beforeEach(async () => {
    // Deploy token contract with Alice as minter
    token = (await deployTokenWithMinter(alice, {})) as TokenContract;

    // Deploy Logic contract
    logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('End-to-End Clawback Flow', () => {
    it('should demonstrate complete clawback escrow flow: Alice creates -> Bob discovers -> Bob claims', async () => {
      // Step 1: Alice creates a clawback escrow for Bob
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      // Fund the escrow
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Set deadline 1 hour from now
      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600;

      console.log('Step 1: Alice creates clawback escrow...');

      // Alice creates the clawback escrow - this shares keys with Bob
      const createTx = await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          deadline,
        )
        .send()
        .wait();

      expect(createTx.status).toBe(TxStatus.SUCCESS);

      console.log('Step 2: Bob discovers the escrow (keys shared privately)...');

      // Step 2: Bob discovers escrow and verifies keys (implicit through successful claim)
      // In a real implementation, Bob would:
      // 1. Listen to private logs from LogicContract
      // 2. Decrypt EscrowDetailsLogContent
      // 3. Verify the keys correspond to the escrow address
      // 4. Use keys to read escrow balance

      console.log('Step 3: Bob claims before deadline...');

      // Step 3: Bob can claim before deadline
      const initialBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();

      const claimTx = await logicContract
        .withWallet(bob)
        .methods.claim(escrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      expect(claimTx.status).toBe(TxStatus.SUCCESS);

      // Verify Bob received the tokens
      const finalBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();
      expect(finalBobBalance).toBe(initialBobBalance + ESCROW_AMOUNT);

      console.log('✅ Complete flow successful: Alice → Bob transfer via clawback escrow');
    }, 150_000);

    it('should allow Alice to clawback after deadline when Bob hasnt claimed', async () => {
      // Setup escrow with short deadline for testing
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Set deadline in the past to simulate expired escrow
      const pastTime = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago

      console.log('Step 1: Alice creates escrow with past deadline...');

      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          pastTime,
        )
        .send()
        .wait();

      // Bob should not be able to claim after deadline
      console.log('Step 2: Bob attempts to claim after deadline (should fail)...');

      await expect(
        logicContract.withWallet(bob).methods.claim(escrow.address, token.address, ESCROW_AMOUNT).send().wait(),
      ).rejects.toThrow(/deadline has passed/);

      console.log('Step 3: Alice claws back after deadline...');

      // Alice should be able to clawback after deadline
      const initialAliceBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();

      const clawbackTx = await logicContract
        .withWallet(alice)
        .methods.clawback(escrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      expect(clawbackTx.status).toBe(TxStatus.SUCCESS);

      // Verify Alice got the tokens back
      const finalAliceBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();
      expect(finalAliceBalance).toBe(initialAliceBalance + ESCROW_AMOUNT);

      console.log('✅ Clawback successful: Alice recovered tokens after deadline');
    }, 150_000);

    it('should prevent Alice from clawback before deadline', async () => {
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Set deadline in the future
      const futureTime = Math.floor(Date.now() / 1000) + 7200; // 2 hours from now

      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          futureTime,
        )
        .send()
        .wait();

      // Alice should not be able to clawback before deadline
      await expect(
        logicContract.withWallet(alice).methods.clawback(escrow.address, token.address, ESCROW_AMOUNT).send().wait(),
      ).rejects.toThrow(/deadline has not passed/);

      console.log('✅ Alice correctly prevented from clawback before deadline');
    }, 120_000);

    it('should prevent Bob from claiming after deadline', async () => {
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Set deadline in the past
      const pastTime = Math.floor(Date.now() / 1000) - 1800; // 30 minutes ago

      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          pastTime,
        )
        .send()
        .wait();

      // Bob should not be able to claim after deadline
      await expect(
        logicContract.withWallet(bob).methods.claim(escrow.address, token.address, ESCROW_AMOUNT).send().wait(),
      ).rejects.toThrow(/deadline has passed/);

      console.log('✅ Bob correctly prevented from claiming after deadline');
    }, 120_000);
  });

  describe('Multiple Participants and Complex Scenarios', () => {
    it('should handle multiple simultaneous escrows between different parties', async () => {
      // Create multiple escrows: Alice->Bob, Alice->Charlie, Bob->Charlie

      const scenarios = [
        { from: alice, to: bob, amount: ESCROW_AMOUNT },
        { from: alice, to: charlie, amount: PARTIAL_AMOUNT },
        { from: bob, to: charlie, amount: ESCROW_AMOUNT / 4n },
      ];

      const escrowDetails = [];

      // Mint tokens to Bob for the third scenario
      await token
        .withWallet(alice)
        .methods.mint_to_private(bob.getAddress(), bob.getAddress(), ESCROW_AMOUNT)
        .send()
        .wait();

      console.log('Setting up multiple escrows...');

      for (let i = 0; i < scenarios.length; i++) {
        const scenario = scenarios[i];
        const keys = generateMasterSecretKeys();
        const { publicKeys } = computeEscrowAddress(keys);
        const salt = new Fr(logicContract.address.toBigInt());
        const escrow = await deployEscrowWithSalt(scenario.from, salt, publicKeys);

        // Fund the escrow
        await token
          .withWallet(scenario.from)
          .methods.mint_to_private(escrow.address, escrow.address, scenario.amount)
          .send()
          .wait();

        const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

        await logicContract
          .withWallet(scenario.from)
          .methods.create_clawback(
            escrow.address,
            keys,
            scenario.to.getAddress(),
            scenario.from.getAddress(),
            token.address,
            scenario.amount,
            deadline,
          )
          .send()
          .wait();

        escrowDetails.push({
          escrow: escrow.address,
          keys,
          from: scenario.from,
          to: scenario.to,
          amount: scenario.amount,
        });
      }

      console.log('All recipients claiming their escrows...');

      // All recipients claim their escrows
      for (const details of escrowDetails) {
        const initialBalance = await token.methods.balance_of_private(details.to.getAddress()).simulate();

        await logicContract
          .withWallet(details.to)
          .methods.claim(details.escrow, token.address, details.amount)
          .send()
          .wait();

        const finalBalance = await token.methods.balance_of_private(details.to.getAddress()).simulate();
        expect(finalBalance).toBe(initialBalance + details.amount);
      }

      console.log('✅ Multiple escrow scenario completed successfully');
    }, 300_000);

    it('should maintain privacy between different escrow participants', async () => {
      // Alice creates escrow for Bob
      const aliceBobKeys = generateMasterSecretKeys();
      const { publicKeys: aliceBobPublicKeys } = computeEscrowAddress(aliceBobKeys);
      const salt = new Fr(logicContract.address.toBigInt());
      const aliceBobEscrow = await deployEscrowWithSalt(alice, salt, aliceBobPublicKeys);

      // Alice creates different escrow for Charlie
      const aliceCharlieKeys = generateMasterSecretKeys();
      const { publicKeys: aliceCharliePublicKeys } = computeEscrowAddress(aliceCharlieKeys);
      const aliceCharlieEscrow = await deployEscrowWithSalt(alice, salt, aliceCharliePublicKeys);

      // Fund both escrows
      await token
        .withWallet(alice)
        .methods.mint_to_private(aliceBobEscrow.address, aliceBobEscrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      await token
        .withWallet(alice)
        .methods.mint_to_private(aliceCharlieEscrow.address, aliceCharlieEscrow.address, PARTIAL_AMOUNT)
        .send()
        .wait();

      const deadline = Math.floor(Date.now() / 1000) + 3600;

      // Alice creates both escrows
      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          aliceBobEscrow.address,
          aliceBobKeys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          deadline,
        )
        .send()
        .wait();

      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          aliceCharlieEscrow.address,
          aliceCharlieKeys,
          charlie.getAddress(),
          alice.getAddress(),
          token.address,
          PARTIAL_AMOUNT,
          deadline,
        )
        .send()
        .wait();

      // Bob should not be able to claim from Charlie's escrow (wrong keys/parameters)
      await expect(
        logicContract
          .withWallet(bob)
          .methods.claim(aliceCharlieEscrow.address, token.address, PARTIAL_AMOUNT)
          .send()
          .wait(),
      ).rejects.toThrow(/matching clawback note not found/);

      // Charlie should not be able to claim from Bob's escrow
      await expect(
        logicContract
          .withWallet(charlie)
          .methods.claim(aliceBobEscrow.address, token.address, ESCROW_AMOUNT)
          .send()
          .wait(),
      ).rejects.toThrow(/matching clawback note not found/);

      // But each should be able to claim from their own escrow
      const bobInitial = await token.methods.balance_of_private(bob.getAddress()).simulate();
      const charlieInitial = await token.methods.balance_of_private(charlie.getAddress()).simulate();

      await logicContract
        .withWallet(bob)
        .methods.claim(aliceBobEscrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      await logicContract
        .withWallet(charlie)
        .methods.claim(aliceCharlieEscrow.address, token.address, PARTIAL_AMOUNT)
        .send()
        .wait();

      const bobFinal = await token.methods.balance_of_private(bob.getAddress()).simulate();
      const charlieFinal = await token.methods.balance_of_private(charlie.getAddress()).simulate();

      expect(bobFinal).toBe(bobInitial + ESCROW_AMOUNT);
      expect(charlieFinal).toBe(charlieInitial + PARTIAL_AMOUNT);

      console.log('✅ Privacy maintained between different escrow participants');
    }, 240_000);
  });

  describe('Escrow Discovery and Key Verification', () => {
    it('should emit encrypted escrow details that only recipients can use', async () => {
      const keys = generateMasterSecretKeys();
      const { address: expectedEscrowAddress, publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      // Verify the escrow address matches the computed address from keys
      expect(escrow.address).toEqual(expectedEscrowAddress);

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      const deadline = Math.floor(Date.now() / 1000) + 3600;

      // When Alice creates the escrow, EscrowDetailsLogContent is emitted privately to Bob
      const createTx = await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          deadline,
        )
        .send()
        .wait();

      expect(createTx.status).toBe(TxStatus.SUCCESS);

      // The fact that Bob can successfully claim proves he received and can use the keys
      const claimTx = await logicContract
        .withWallet(bob)
        .methods.claim(escrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      expect(claimTx.status).toBe(TxStatus.SUCCESS);

      console.log('✅ Escrow discovery and key verification successful');
    }, 150_000);

    it('should prevent duplicate escrow creation with same address', async () => {
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      const deadline = Math.floor(Date.now() / 1000) + 3600;

      // First creation should succeed
      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          deadline,
        )
        .send()
        .wait();

      // Second creation with same escrow address should fail due to nullifier
      await expect(
        logicContract
          .withWallet(alice)
          .methods.create_clawback(
            escrow.address,
            keys,
            bob.getAddress(),
            alice.getAddress(),
            token.address,
            ESCROW_AMOUNT,
            deadline,
          )
          .send()
          .wait(),
      ).rejects.toThrow(); // Should fail due to duplicate nullifier

      console.log('✅ Duplicate escrow creation prevented');
    }, 150_000);
  });

  describe('Error Cases and Security', () => {
    it('should reject invalid escrow parameters', async () => {
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      const deadline = Math.floor(Date.now() / 1000) + 3600;

      // Test zero amount
      await expect(
        logicContract
          .withWallet(alice)
          .methods.create_clawback(
            escrow.address,
            keys,
            bob.getAddress(),
            alice.getAddress(),
            token.address,
            0n,
            deadline,
          )
          .send()
          .wait(),
      ).rejects.toThrow();

      // Test zero deadline (past timestamp)
      await expect(
        logicContract
          .withWallet(alice)
          .methods.create_clawback(
            escrow.address,
            keys,
            bob.getAddress(),
            alice.getAddress(),
            token.address,
            ESCROW_AMOUNT,
            0,
          )
          .send()
          .wait(),
      ).rejects.toThrow();

      console.log('✅ Invalid parameters correctly rejected');
    }, 120_000);

    it('should handle escrow with insufficient balance gracefully', async () => {
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      // Fund escrow with less than claimed amount
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, PARTIAL_AMOUNT)
        .send()
        .wait();

      const deadline = Math.floor(Date.now() / 1000) + 3600;

      // Create clawback for more than available
      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT, // More than funded
          deadline,
        )
        .send()
        .wait();

      // Claim should fail due to insufficient balance
      await expect(
        logicContract.withWallet(bob).methods.claim(escrow.address, token.address, ESCROW_AMOUNT).send().wait(),
      ).rejects.toThrow(); // Should fail due to insufficient balance in escrow

      console.log('✅ Insufficient balance handled gracefully');
    }, 120_000);
  });
});
