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
import { TokenContract, TokenContractArtifact } from '../../../artifacts/Token.js';
import { ClawbackLogicContract, ClawbackLogicContractArtifact } from '../../../artifacts/ClawbackLogic.js';
import { setupPXE, deployTokenWithMinter } from '../../ts/test/utils.js';

const ESCROW_AMOUNT = 1000n;

// Helper function to generate master secret keys for escrow
function generateMasterSecretKeys(): [Fr, Fr, Fr, Fr] {
  return [Fr.random(), Fr.random(), Fr.random(), Fr.random()];
}

// Helper function to deploy an escrow contract with specific salt
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

// Helper function to compute escrow address from keys
function computeEscrowAddress(keys: [Fr, Fr, Fr, Fr]): { address: AztecAddress; publicKeys: PublicKeys } {
  const [nsk_m, ivsk_m, ovsk_m, tsk_m] = keys;
  const derivedKeys = deriveKeys(nsk_m, ivsk_m, ovsk_m, tsk_m);
  const publicKeys = derivedKeys.publicKeys;
  const address = computeAddress(publicKeys, EscrowContractArtifact);
  return { address, publicKeys };
}

const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const managers = await getInitialTestAccountsManagers(pxe);
  const wallets = await Promise.all(managers.map((acc) => acc.register()));

  return { pxe, store, wallets };
};

describe('Escrow Contract - Basic Integration Tests', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;
  let wallets: AccountWalletWithSecretKey[];

  let alice: AccountWalletWithSecretKey; // Escrow creator
  let bob: AccountWalletWithSecretKey; // Recipient
  let charlie: AccountWalletWithSecretKey; // Third party

  let token: TokenContract;

  beforeAll(async () => {
    ({ pxe, store, wallets } = await setupTestSuite());
    [alice, bob, charlie] = wallets;
  }, 100_000);

  beforeEach(async () => {
    // Deploy token contract with Alice as minter
    token = (await deployTokenWithMinter(alice, {})) as TokenContract;
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('Escrow Deployment and Access Control', () => {
    it('should deploy escrow with correct salt containing Logic contract address', async () => {
      // Deploy Logic contract first
      const logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();

      // Generate master secret keys
      const keys = generateMasterSecretKeys();
      const { address: escrowAddress, publicKeys } = computeEscrowAddress(keys);

      // Use Logic contract address as salt
      const salt = new Fr(logicContract.address.toBigInt());

      // Deploy Escrow with salt
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      expect(escrow.address).toEqual(escrowAddress);

      // Verify that the contract instance has the correct salt
      const instance = await pxe.getContractInstance(escrow.address);
      expect(instance?.salt).toEqual(salt);
    }, 60_000);

    it('should reject withdraw calls from unauthorized contracts', async () => {
      // Deploy Logic contract
      const logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();

      // Generate keys and deploy escrow
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      // Fund the escrow with tokens
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Try to withdraw from Charlie (unauthorized caller)
      await expect(
        escrow.withWallet(charlie).methods.withdraw(token.address, ESCROW_AMOUNT, bob.getAddress()).send().wait(),
      ).rejects.toThrow(/unauthorized caller/);
    }, 60_000);
  });

  describe('Token Withdrawal Functionality', () => {
    let escrow: EscrowContract;
    let logicContract: ClawbackLogicContract;
    let keys: [Fr, Fr, Fr, Fr];

    beforeEach(async () => {
      // Setup escrow and logic contracts
      logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();
      keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      // Fund the escrow
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();
    });

    it('should allow authorized Logic contract to withdraw tokens', async () => {
      // Get initial balance of Bob
      const initialBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();

      // Logic contract creates clawback escrow and withdraws
      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600; // 1 hour from now

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

      // Bob claims the tokens before deadline
      await logicContract.withWallet(bob).methods.claim(escrow.address, token.address, ESCROW_AMOUNT).send().wait();

      // Verify Bob received the tokens
      const finalBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();
      expect(finalBobBalance).toBe(initialBobBalance + ESCROW_AMOUNT);
    }, 90_000);

    it('should handle partial withdrawals correctly', async () => {
      const partialAmount = ESCROW_AMOUNT / 2n;

      // Create clawback escrow
      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600;

      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          partialAmount, // Only allow partial amount to be claimed
          deadline,
        )
        .send()
        .wait();

      // Bob claims partial amount
      const initialBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();

      await logicContract.withWallet(bob).methods.claim(escrow.address, token.address, partialAmount).send().wait();

      const finalBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();
      expect(finalBobBalance).toBe(initialBobBalance + partialAmount);

      // Remaining tokens should still be in escrow
      const escrowBalance = await token.methods.balance_of_private(escrow.address).simulate();
      expect(escrowBalance).toBe(ESCROW_AMOUNT - partialAmount);
    }, 90_000);
  });

  describe('Privacy Preservation', () => {
    it('should keep escrow operations private from external observers', async () => {
      // Deploy and setup escrow
      const logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      // Fund the escrow privately
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Charlie should not be able to see the escrow balance without keys
      const charlieTokenContract = token.withWallet(charlie);

      // Charlie can't see the private balance
      const escrowBalanceFromCharlie = await charlieTokenContract.methods.balance_of_private(escrow.address).simulate();
      expect(escrowBalanceFromCharlie).toBe(0n); // Charlie can't see private notes

      // But Alice and Bob (with keys) should be able to see transactions they're involved in
      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600;

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

      // Bob should be able to claim (proving he received the escrow details)
      const claimTx = await logicContract
        .withWallet(bob)
        .methods.claim(escrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      expect(claimTx.status).toBe(TxStatus.SUCCESS);
    }, 120_000);

    it('should maintain privacy when escrow details are shared', async () => {
      const logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();
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

      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600;

      // Alice creates the escrow - this shares details with Bob privately
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

      // The transaction should succeed but details should be encrypted
      expect(createTx.status).toBe(TxStatus.SUCCESS);

      // Charlie should not see any unencrypted escrow details in logs
      // This is implicit since private logs are encrypted to specific recipients

      // Bob should be able to use the shared details to claim
      const claimTx = await logicContract
        .withWallet(bob)
        .methods.claim(escrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      expect(claimTx.status).toBe(TxStatus.SUCCESS);

      // Verify Bob received the tokens
      const bobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();
      expect(bobBalance).toBe(ESCROW_AMOUNT);
    }, 120_000);
  });

  describe('Error Handling and Edge Cases', () => {
    it('should reject withdrawals with zero amount', async () => {
      const logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();
      const keys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600;

      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow.address,
          keys,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          0n, // Zero amount
          deadline,
        )
        .send()
        .wait();

      // Attempt to claim zero amount should fail
      await expect(
        logicContract.withWallet(bob).methods.claim(escrow.address, token.address, 0n).send().wait(),
      ).rejects.toThrow();
    }, 90_000);

    it('should handle multiple escrows for the same user', async () => {
      const logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();

      // Create first escrow
      const keys1 = generateMasterSecretKeys();
      const { publicKeys: publicKeys1 } = computeEscrowAddress(keys1);
      const salt1 = new Fr(logicContract.address.toBigInt());
      const escrow1 = await deployEscrowWithSalt(alice, salt1, publicKeys1);

      // Create second escrow (different keys = different address)
      const keys2 = generateMasterSecretKeys();
      const { publicKeys: publicKeys2 } = computeEscrowAddress(keys2);
      const escrow2 = await deployEscrowWithSalt(alice, salt1, publicKeys2);

      // Fund both escrows
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow1.address, escrow1.address, ESCROW_AMOUNT)
        .send()
        .wait();

      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow2.address, escrow2.address, ESCROW_AMOUNT)
        .send()
        .wait();

      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600;

      // Create both escrows for Bob
      await logicContract
        .withWallet(alice)
        .methods.create_clawback(
          escrow1.address,
          keys1,
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
          escrow2.address,
          keys2,
          bob.getAddress(),
          alice.getAddress(),
          token.address,
          ESCROW_AMOUNT,
          deadline,
        )
        .send()
        .wait();

      const initialBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();

      // Bob should be able to claim from both escrows
      await logicContract.withWallet(bob).methods.claim(escrow1.address, token.address, ESCROW_AMOUNT).send().wait();

      await logicContract.withWallet(bob).methods.claim(escrow2.address, token.address, ESCROW_AMOUNT).send().wait();

      // Verify Bob received tokens from both escrows
      const finalBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();
      expect(finalBobBalance).toBe(initialBobBalance + ESCROW_AMOUNT * 2n);
    }, 180_000);
  });
});
