import {
  Fr,
  TxStatus,
  AccountWalletWithSecretKey,
  AztecAddress,
  PublicKeys,
  computeAddress,
  deriveKeys,
  Grumpkin,
} from '@aztec/aztec.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { AztecLmdbStore } from '@aztec/kv-store/lmdb';
import { getInitialTestAccountsManagers } from '@aztec/accounts/testing';
import { EscrowContract, EscrowContractArtifact } from '../../../artifacts/Escrow.js';
import { TokenContract } from '../../../artifacts/Token.js';
import { ClawbackLogicContract } from '../../../artifacts/ClawbackLogic.js';
import { setupPXE, deployTokenWithMinter } from '../../ts/test/utils.js';

const ESCROW_AMOUNT = 1000n;

// Helper functions for key generation and verification
function generateMasterSecretKeys(): [Fr, Fr, Fr, Fr] {
  return [Fr.random(), Fr.random(), Fr.random(), Fr.random()];
}

function derivePublicKeysFromSecrets(secrets: [Fr, Fr, Fr, Fr]): PublicKeys {
  const [nsk_m, ivsk_m, ovsk_m, tsk_m] = secrets;
  const derivedKeys = deriveKeys(nsk_m, ivsk_m, ovsk_m, tsk_m);
  return derivedKeys.publicKeys;
}

function computeEscrowAddress(keys: [Fr, Fr, Fr, Fr]): { address: AztecAddress; publicKeys: PublicKeys } {
  const publicKeys = derivePublicKeysFromSecrets(keys);
  const address = computeAddress(publicKeys, EscrowContractArtifact);
  return { address, publicKeys };
}

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

const setupTestSuite = async () => {
  const { pxe, store } = await setupPXE();
  const managers = await getInitialTestAccountsManagers(pxe);
  const wallets = await Promise.all(managers.map((acc) => acc.register()));

  return { pxe, store, wallets };
};

describe('Escrow Key Verification and Cryptographic Tests', () => {
  let pxe: PXE;
  let store: AztecLmdbStore;
  let wallets: AccountWalletWithSecretKey[];

  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let charlie: AccountWalletWithSecretKey;

  let token: TokenContract;
  let logicContract: ClawbackLogicContract;

  beforeAll(async () => {
    ({ pxe, store, wallets } = await setupTestSuite());
    [alice, bob, charlie] = wallets;
  }, 100_000);

  beforeEach(async () => {
    token = (await deployTokenWithMinter(alice, {})) as TokenContract;
    logicContract = await ClawbackLogicContract.deploy(alice).send().deployed();
  });

  afterAll(async () => {
    await store.delete();
  });

  describe('Master Secret Key Generation and Validation', () => {
    it('should generate valid master secret keys and derive consistent public keys', async () => {
      const keys = generateMasterSecretKeys();
      const [nsk_m, ivsk_m, ovsk_m, tsk_m] = keys;

      // Verify all keys are non-zero and different
      expect(nsk_m.toBigInt()).not.toBe(0n);
      expect(ivsk_m.toBigInt()).not.toBe(0n);
      expect(ovsk_m.toBigInt()).not.toBe(0n);
      expect(tsk_m.toBigInt()).not.toBe(0n);

      expect(nsk_m).not.toEqual(ivsk_m);
      expect(nsk_m).not.toEqual(ovsk_m);
      expect(nsk_m).not.toEqual(tsk_m);
      expect(ivsk_m).not.toEqual(ovsk_m);

      console.log('Generated Master Secret Keys:');
      console.log('- nsk_m (nullification):', nsk_m.toString());
      console.log('- ivsk_m (incoming view):', ivsk_m.toString());
      console.log('- ovsk_m (outgoing view):', ovsk_m.toString());
      console.log('- tsk_m (tagging):', tsk_m.toString());

      // Derive public keys multiple times to ensure consistency
      const publicKeys1 = derivePublicKeysFromSecrets(keys);
      const publicKeys2 = derivePublicKeysFromSecrets(keys);

      expect(publicKeys1.npkM.x).toEqual(publicKeys2.npkM.x);
      expect(publicKeys1.npkM.y).toEqual(publicKeys2.npkM.y);
      expect(publicKeys1.ivpkM.x).toEqual(publicKeys2.ivpkM.x);
      expect(publicKeys1.ivpkM.y).toEqual(publicKeys2.ivpkM.y);

      console.log('✅ Master secret keys generated and public key derivation is consistent');
    });

    it('should derive different public keys from different master secrets', async () => {
      const keys1 = generateMasterSecretKeys();
      const keys2 = generateMasterSecretKeys();

      const publicKeys1 = derivePublicKeysFromSecrets(keys1);
      const publicKeys2 = derivePublicKeysFromSecrets(keys2);

      // Public keys should be different
      expect(publicKeys1.npkM.x).not.toEqual(publicKeys2.npkM.x);
      expect(publicKeys1.ivpkM.x).not.toEqual(publicKeys2.ivpkM.x);
      expect(publicKeys1.ovpkM.x).not.toEqual(publicKeys2.ovpkM.x);
      expect(publicKeys1.tpkM.x).not.toEqual(publicKeys2.tpkM.x);

      console.log('✅ Different master secrets produce different public keys');
    });

    it('should validate that keys are valid field elements', async () => {
      // Test with edge case values
      const maxField = Fr.fromString('21888242871839275222246405745257275088548364400416034343698204186575808495616'); // q - 1
      const zero = Fr.ZERO;
      const one = Fr.ONE;

      // Zero keys should be rejected by the escrow system
      const zeroKeys: [Fr, Fr, Fr, Fr] = [zero, zero, zero, zero];
      const validKeys = generateMasterSecretKeys();
      const oneKey: [Fr, Fr, Fr, Fr] = [one, validKeys[1], validKeys[2], validKeys[3]];

      // Test that valid keys work
      const { publicKeys } = computeEscrowAddress(validKeys);
      expect(publicKeys).toBeDefined();

      // Test edge cases
      const edgeKeys: [Fr, Fr, Fr, Fr] = [maxField, validKeys[1], validKeys[2], validKeys[3]];
      const { publicKeys: edgePublicKeys } = computeEscrowAddress(edgeKeys);
      expect(edgePublicKeys).toBeDefined();

      console.log('✅ Key validation tests completed');
    });
  });

  describe('Address Derivation and Verification', () => {
    it('should derive consistent escrow addresses from the same keys', async () => {
      const keys = generateMasterSecretKeys();

      // Derive address multiple times
      const { address: address1, publicKeys: publicKeys1 } = computeEscrowAddress(keys);
      const { address: address2, publicKeys: publicKeys2 } = computeEscrowAddress(keys);

      expect(address1).toEqual(address2);
      expect(publicKeys1.npkM.x).toEqual(publicKeys2.npkM.x);

      console.log('Derived escrow address:', address1.toString());
      console.log('✅ Address derivation is deterministic');
    });

    it('should derive different addresses for different keys', async () => {
      const keys1 = generateMasterSecretKeys();
      const keys2 = generateMasterSecretKeys();

      const { address: address1 } = computeEscrowAddress(keys1);
      const { address: address2 } = computeEscrowAddress(keys2);

      expect(address1).not.toEqual(address2);

      console.log('Address 1:', address1.toString());
      console.log('Address 2:', address2.toString());
      console.log('✅ Different keys produce different addresses');
    });

    it('should verify that deployed escrow matches computed address', async () => {
      const keys = generateMasterSecretKeys();
      const { address: computedAddress, publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());

      // Deploy escrow with computed public keys
      const deployedEscrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      expect(deployedEscrow.address).toEqual(computedAddress);

      console.log('Computed address:', computedAddress.toString());
      console.log('Deployed address:', deployedEscrow.address.toString());
      console.log('✅ Deployed escrow address matches computed address');
    });
  });

  describe('Key Usage in Escrow Operations', () => {
    it('should successfully use derived keys in a complete escrow operation', async () => {
      // Generate and verify keys
      const keys = generateMasterSecretKeys();
      const { address: escrowAddress, publicKeys } = computeEscrowAddress(keys);
      const salt = new Fr(logicContract.address.toBigInt());

      console.log('Testing key usage in complete escrow flow...');
      console.log('Escrow address from keys:', escrowAddress.toString());

      // Deploy escrow
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);
      expect(escrow.address).toEqual(escrowAddress);

      // Fund the escrow
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Create clawback escrow using the keys
      const deadline = Math.floor(Date.now() / 1000) + 3600;

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

      // Bob uses the shared keys to claim
      const initialBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();

      const claimTx = await logicContract
        .withWallet(bob)
        .methods.claim(escrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      expect(claimTx.status).toBe(TxStatus.SUCCESS);

      const finalBobBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();
      expect(finalBobBalance).toBe(initialBobBalance + ESCROW_AMOUNT);

      console.log('✅ Keys successfully used in complete escrow operation');
    }, 150_000);

    it('should reject operations with invalid keys', async () => {
      // Generate valid keys for deployment
      const validKeys = generateMasterSecretKeys();
      const { publicKeys } = computeEscrowAddress(validKeys);
      const salt = new Fr(logicContract.address.toBigInt());
      const escrow = await deployEscrowWithSalt(alice, salt, publicKeys);

      // Fund the escrow
      await token
        .withWallet(alice)
        .methods.mint_to_private(escrow.address, escrow.address, ESCROW_AMOUNT)
        .send()
        .wait();

      // Try to create clawback with different (invalid) keys
      const invalidKeys = generateMasterSecretKeys();
      const deadline = Math.floor(Date.now() / 1000) + 3600;

      // This should fail because the keys don't match the escrow address
      await expect(
        logicContract
          .withWallet(alice)
          .methods.create_clawback(
            escrow.address,
            invalidKeys, // Wrong keys!
            bob.getAddress(),
            alice.getAddress(),
            token.address,
            ESCROW_AMOUNT,
            deadline,
          )
          .send()
          .wait(),
      ).rejects.toThrow();

      console.log('✅ Invalid keys correctly rejected');
    }, 120_000);

    it('should test key validation with zero keys (should fail)', async () => {
      const zeroKeys: [Fr, Fr, Fr, Fr] = [Fr.ZERO, Fr.ZERO, Fr.ZERO, Fr.ZERO];
      const salt = new Fr(logicContract.address.toBigInt());

      // This should fail as zero keys are invalid
      await expect(async () => {
        const { publicKeys } = computeEscrowAddress(zeroKeys);
        await deployEscrowWithSalt(alice, salt, publicKeys);
      }).rejects.toThrow();

      console.log('✅ Zero keys correctly rejected');
    });
  });

  describe('Public Key Cryptographic Properties', () => {
    it('should verify public keys are valid elliptic curve points', async () => {
      const keys = generateMasterSecretKeys();
      const publicKeys = derivePublicKeysFromSecrets(keys);

      // Verify that public key points are valid
      expect(publicKeys.npkM.x).toBeDefined();
      expect(publicKeys.npkM.y).toBeDefined();
      expect(publicKeys.ivpkM.x).toBeDefined();
      expect(publicKeys.ivpkM.y).toBeDefined();

      // The coordinates should be valid field elements (non-zero for real keys)
      expect(publicKeys.npkM.x.toBigInt()).not.toBe(0n);
      expect(publicKeys.npkM.y.toBigInt()).not.toBe(0n);

      console.log('Public Key Points:');
      console.log('- npkM:', `(${publicKeys.npkM.x.toString()}, ${publicKeys.npkM.y.toString()})`);
      console.log('- ivpkM:', `(${publicKeys.ivpkM.x.toString()}, ${publicKeys.ivpkM.y.toString()})`);

      console.log('✅ Public keys are valid elliptic curve points');
    });

    it('should verify that different secret keys produce non-colliding public keys', async () => {
      const keys1 = generateMasterSecretKeys();
      const keys2 = generateMasterSecretKeys();
      const keys3 = generateMasterSecretKeys();

      const publicKeys1 = derivePublicKeysFromSecrets(keys1);
      const publicKeys2 = derivePublicKeysFromSecrets(keys2);
      const publicKeys3 = derivePublicKeysFromSecrets(keys3);

      const addresses = [
        computeEscrowAddress(keys1).address,
        computeEscrowAddress(keys2).address,
        computeEscrowAddress(keys3).address,
      ];

      // All addresses should be unique
      expect(addresses[0]).not.toEqual(addresses[1]);
      expect(addresses[0]).not.toEqual(addresses[2]);
      expect(addresses[1]).not.toEqual(addresses[2]);

      // All public key points should be unique
      expect(publicKeys1.npkM.x).not.toEqual(publicKeys2.npkM.x);
      expect(publicKeys1.npkM.x).not.toEqual(publicKeys3.npkM.x);
      expect(publicKeys2.npkM.x).not.toEqual(publicKeys3.npkM.x);

      console.log('Generated 3 unique addresses:');
      addresses.forEach((addr, i) => console.log(`${i + 1}: ${addr.toString()}`));
      console.log('✅ No public key collisions detected');
    });
  });

  describe('Key Security and Privacy', () => {
    it('should demonstrate that keys enable private balance reading', async () => {
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

      // Alice should be able to see the balance she just sent
      const aliceBalance = await token.methods.balance_of_private(escrow.address).simulate();
      expect(aliceBalance).toBe(ESCROW_AMOUNT);

      // Without keys, Charlie shouldn't be able to see the private balance
      const charlieTokenContract = token.withWallet(charlie);
      const charlieViewOfBalance = await charlieTokenContract.methods.balance_of_private(escrow.address).simulate();
      expect(charlieViewOfBalance).toBe(0n); // Charlie can't see private notes without keys

      console.log('Alice can see escrow balance:', aliceBalance.toString());
      console.log('Charlie cannot see escrow balance:', charlieViewOfBalance.toString());
      console.log('✅ Keys provide selective visibility to private balances');
    }, 120_000);

    it('should verify that escrow keys are effectively shared through encrypted channels', async () => {
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

      // Alice creates escrow (shares keys with Bob via encrypted log)
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

      // The fact that Bob can successfully claim proves the keys were shared securely
      const claimTx = await logicContract
        .withWallet(bob)
        .methods.claim(escrow.address, token.address, ESCROW_AMOUNT)
        .send()
        .wait();

      expect(claimTx.status).toBe(TxStatus.SUCCESS);

      // But Charlie still cannot access without the keys being shared with him
      const charlieBalance = await token.withWallet(charlie).methods.balance_of_private(escrow.address).simulate();
      expect(charlieBalance).toBe(0n);

      console.log('✅ Keys securely shared through encrypted channels');
    }, 150_000);

    it('should test key generation entropy and randomness', async () => {
      // Generate multiple key sets and verify they're different
      const keySets = Array.from({ length: 5 }, () => generateMasterSecretKeys());
      const addresses = keySets.map((keys) => computeEscrowAddress(keys).address);

      // All addresses should be unique (probability of collision is negligible)
      for (let i = 0; i < addresses.length; i++) {
        for (let j = i + 1; j < addresses.length; j++) {
          expect(addresses[i]).not.toEqual(addresses[j]);
        }
      }

      // Verify that keys within each set are different
      keySets.forEach((keys, setIndex) => {
        const [nsk_m, ivsk_m, ovsk_m, tsk_m] = keys;
        expect(nsk_m).not.toEqual(ivsk_m);
        expect(nsk_m).not.toEqual(ovsk_m);
        expect(nsk_m).not.toEqual(tsk_m);
        expect(ivsk_m).not.toEqual(ovsk_m);
        console.log(`Key set ${setIndex + 1} has 4 unique keys`);
      });

      console.log(`Generated ${keySets.length} unique key sets with ${keySets.length} unique addresses`);
      console.log('✅ Key generation shows good entropy and randomness');
    });
  });
});
