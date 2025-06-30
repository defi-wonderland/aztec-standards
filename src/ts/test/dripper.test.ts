
import {
  ContractDeployer,
  Fr,
  TxStatus,
  getContractInstanceFromDeployParams,
  Contract,
  AccountWalletWithSecretKey,
  Wallet,
  AccountManager,
} from '@aztec/aztec.js';
import { AMOUNT, deployTokenWithMinter, expectTokenBalances, setupPXE } from './utils.js';
import { PXE } from '@aztec/stdlib/interfaces/client';
import { getInitialTestAccounts } from '@aztec/accounts/testing';
import { TokenContractArtifact, TokenContract } from '../../artifacts/Token.js';
import { DripperContractArtifact, DripperContract } from '../../artifacts/Dripper.js';
import { SchnorrAccountContract } from '@aztec/accounts/schnorr';
import { deriveSigningKey } from '@aztec/stdlib/keys';

const setupTestSuite = async () => {
  const pxe = await setupPXE();
  const managers = await Promise.all(
    (await getInitialTestAccounts()).map(async (acc) => {
      return await AccountManager.create(
        pxe,
        acc.secret,
        new SchnorrAccountContract(deriveSigningKey(acc.secret)),
        acc.salt,
      );
    }),
  );
  const wallets = await Promise.all(managers.map((acc) => acc.register()));
  const [deployer] = wallets;

  return { pxe, deployer, wallets };
};

/**
 * Deploys the Dripper contract.
 * @param deployer - The wallet to deploy the contract with.
 * @returns A deployed contract instance.
 */
async function deployDripper(deployer: Wallet) {
  const contract = await Contract.deploy(
    deployer,
    DripperContractArtifact,
    [],
    'constructor',
  )
    .send()
    .deployed();
  return contract as DripperContract;
}

describe('Dripper - Single PXE', () => {
  let pxe: PXE;

  let wallets: AccountWalletWithSecretKey[];
  let deployer: AccountWalletWithSecretKey;

  let alice: AccountWalletWithSecretKey;
  let bob: AccountWalletWithSecretKey;
  let carl: AccountWalletWithSecretKey;

  let token: TokenContract;
  let dripper: DripperContract;

  beforeAll(async () => {
    ({ pxe, deployer, wallets } = await setupTestSuite());

    [alice, bob, carl] = wallets;
  });

  beforeEach(async () => {
    // Deploy token contract with alice as minter
    token = (await deployTokenWithMinter(alice, {})) as TokenContract;
    
    // Deploy dripper contract
    dripper = await deployDripper(alice);
    
    // Note: In a real scenario, the dripper would need to be set as minter
    // For this test, we'll assume the dripper has minting permissions
  });

  describe('drip_to_public', () => {
    it('should mint tokens to Alice public balance', async () => {
      const dripAmount = 1000n;
      
      // Alice calls drip_to_public
      await dripper
        .withWallet(alice)
        .methods.drip_to_public(token.address, dripAmount)
        .send()
        .wait();

      // Check Alice's public balance
      const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      expect(alicePublicBalance).toBe(dripAmount);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(dripAmount);

      // Check Alice's private balance is still 0
      const alicePrivateBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();
      expect(alicePrivateBalance).toBe(0n);
    }, 300_000);

    it('should allow multiple users to drip tokens', async () => {
      const dripAmount = 1000n;
      
      // Alice drips tokens
      await dripper
        .withWallet(alice)
        .methods.drip_to_public(token.address, dripAmount)
        .send()
        .wait();

      // Bob drips tokens
      await dripper
        .withWallet(bob)
        .methods.drip_to_public(token.address, dripAmount)
        .send()
        .wait();

      // Check balances
      const aliceBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      const bobBalance = await token.methods.balance_of_public(bob.getAddress()).simulate();
      
      expect(aliceBalance).toBe(dripAmount);
      expect(bobBalance).toBe(dripAmount);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(dripAmount * 2n);
    }, 300_000);

    it('should handle large amounts', async () => {
      const largeDripAmount = 1_000_000n;
      
      // Alice drips a large amount
      await dripper
        .withWallet(alice)
        .methods.drip_to_public(token.address, largeDripAmount)
        .send()
        .wait();

      // Check Alice's balance
      const aliceBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      expect(aliceBalance).toBe(largeDripAmount);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(largeDripAmount);
    }, 300_000);

    it('should allow Alice to drip multiple times', async () => {
      const dripAmount = 500n;
      
      // Alice drips tokens twice
      await dripper
        .withWallet(alice)
        .methods.drip_to_public(token.address, dripAmount)
        .send()
        .wait();

      await dripper
        .withWallet(alice)
        .methods.drip_to_public(token.address, dripAmount)
        .send()
        .wait();

      // Check Alice's balance (should be sum of both drips)
      const aliceBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      expect(aliceBalance).toBe(dripAmount * 2n);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(dripAmount * 2n);
    }, 300_000);
  });

  describe('drip_to_private', () => {
    it('should mint tokens to Alice private balance', async () => {
      const dripAmount = 1000n;
      
      // Alice calls drip_to_private
      await dripper
        .withWallet(alice)
        .methods.drip_to_private(token.address, dripAmount)
        .send()
        .wait();

      // Check Alice's private balance
      const alicePrivateBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();
      expect(alicePrivateBalance).toBe(dripAmount);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(dripAmount);

      // Check Alice's public balance is still 0
      const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      expect(alicePublicBalance).toBe(0n);
    }, 300_000);

    it('should allow multiple users to drip tokens privately', async () => {
      const dripAmount = 1000n;
      
      // Alice drips tokens privately
      await dripper
        .withWallet(alice)
        .methods.drip_to_private(token.address, dripAmount)
        .send()
        .wait();

      // Bob drips tokens privately
      await dripper
        .withWallet(bob)
        .methods.drip_to_private(token.address, dripAmount)
        .send()
        .wait();

      // Check private balances
      const alicePrivateBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();
      const bobPrivateBalance = await token.methods.balance_of_private(bob.getAddress()).simulate();
      
      expect(alicePrivateBalance).toBe(dripAmount);
      expect(bobPrivateBalance).toBe(dripAmount);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(dripAmount * 2n);

      // Check public balances are still 0
      const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      const bobPublicBalance = await token.methods.balance_of_public(bob.getAddress()).simulate();
      expect(alicePublicBalance).toBe(0n);
      expect(bobPublicBalance).toBe(0n);
    }, 300_000);

    it('should handle large amounts privately', async () => {
      const largeDripAmount = 1_000_000n;
      
      // Alice drips a large amount privately
      await dripper
        .withWallet(alice)
        .methods.drip_to_private(token.address, largeDripAmount)
        .send()
        .wait();

      // Check Alice's private balance
      const alicePrivateBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();
      expect(alicePrivateBalance).toBe(largeDripAmount);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(largeDripAmount);

      // Check public balance is still 0
      const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      expect(alicePublicBalance).toBe(0n);
    }, 300_000);

    it('should allow Alice to drip privately multiple times', async () => {
      const dripAmount = 500n;
      
      // Alice drips tokens privately twice
      await dripper
        .withWallet(alice)
        .methods.drip_to_private(token.address, dripAmount)
        .send()
        .wait();

      await dripper
        .withWallet(alice)
        .methods.drip_to_private(token.address, dripAmount)
        .send()
        .wait();

      // Check Alice's private balance (should be sum of both drips)
      const alicePrivateBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();
      expect(alicePrivateBalance).toBe(dripAmount * 2n);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(dripAmount * 2n);

      // Check public balance is still 0
      const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      expect(alicePublicBalance).toBe(0n);
    }, 300_000);
  });

  describe('mixed dripping', () => {
    it('should allow Alice to drip to both public and private balances', async () => {
      const dripAmount = 1000n;
      
      // Alice drips to public
      await dripper
        .withWallet(alice)
        .methods.drip_to_public(token.address, dripAmount)
        .send()
        .wait();

      // Alice drips to private
      await dripper
        .withWallet(alice)
        .methods.drip_to_private(token.address, dripAmount)
        .send()
        .wait();

      // Check both balances
      const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
      const alicePrivateBalance = await token.methods.balance_of_private(alice.getAddress()).simulate();
      
      expect(alicePublicBalance).toBe(dripAmount);
      expect(alicePrivateBalance).toBe(dripAmount);

      // Check total supply
      const totalSupply = await token.methods.total_supply().simulate();
      expect(totalSupply).toBe(dripAmount * 2n);
    }, 300_000);
  });
});
