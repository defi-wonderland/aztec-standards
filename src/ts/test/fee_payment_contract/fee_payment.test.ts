import { FPCContractArtifact, FPCContract } from '../../../artifacts/FPC.js';
import { TokenContractArtifact, TokenContract } from '../../../artifacts/Token.js';
import {
  AccountWallet,
  ContractDeployer,
  Fr,
  PXE,
  TxStatus,
  getContractInstanceFromDeployParams,
  Contract,
  AccountWalletWithSecretKey,
  AztecAddress,
} from '@aztec/aztec.js';
import { getInitialTestAccountsWallets } from '@aztec/accounts/testing';
import { AMOUNT, createPXE } from '../utils.js';
import { FPCPayment } from './payment_methods.js';

// Helper function to deploy the Fee Payment Contract
async function deployFeePaymentContract(deployer: AccountWallet, acceptedAsset: AztecAddress, admin: AztecAddress) {
  const contract = await Contract.deploy(
    deployer,
    FPCContractArtifact,
    [acceptedAsset, admin],
  )
    .send()
    .deployed();
  return contract;
}

// Helper function to deploy the Token Contract
async function deployTokenWithMinter(deployer: AccountWallet) {
  const contract = await Contract.deploy(
    deployer,
    TokenContractArtifact,
    ['PrivateToken', 'PT', 18, deployer.getAddress()],
    'constructor_with_minter',
  )
    .send()
    .deployed();
  return contract;
}

describe('Fee Payment Contract', () => {
  let alicePxe: PXE;
  let bobPxe: PXE;

  let aliceWallet: AccountWalletWithSecretKey;
  let bobWallet: AccountWalletWithSecretKey;

  let alice: AccountWallet;
  let bob: AccountWallet;

  let token: TokenContract;
  let feePayment: FPCContract;

  // Set up pixies and wallets
  beforeAll(async () => {
    alicePxe = await createPXE(0);
    bobPxe = await createPXE(1);

    const aliceWallets = await getInitialTestAccountsWallets(alicePxe);
    const bobWallets = await getInitialTestAccountsWallets(bobPxe);

    aliceWallet = aliceWallets[0];
    bobWallet = bobWallets[1];
    alice = aliceWallets[0];
    bob = bobWallets[1];

  });

  beforeEach(async () => {
    // Deploy Token with Alice as minter 
    token = (await deployTokenWithMinter(alice)) as TokenContract;
    await bobPxe.registerContract(token);

    // Deploy FPC
    feePayment = (await deployFeePaymentContract(alice, token.address, alice.getAddress())) as FPCContract;
    await bobPxe.registerContract(feePayment);

    await alicePxe.registerAccount(bobWallet.getSecretKey(), bob.getCompleteAddress().partialAddress);
    await alicePxe.registerSender(bob.getAddress());

    await bobPxe.registerAccount(aliceWallet.getSecretKey(), alice.getCompleteAddress().partialAddress);
    await bobPxe.registerSender(alice.getAddress());

  });

  it('deploys the fee payment contract', async () => {
    const salt = Fr.random();

    // Get contract deployment instance
    const deploymentData = await getContractInstanceFromDeployParams(FPCContractArtifact, {
      constructorArgs: [token.address, alice.getAddress()],
      salt,
      deployer: alice.getAddress(),
    });

    // Deploy FPC
    const deployer = new ContractDeployer(FPCContractArtifact, alice);
    const tx = deployer.deploy(token.address, alice.getAddress()).send({ contractAddressSalt: salt });
    const receipt = await tx.getReceipt();
    expect(receipt).toEqual(expect.objectContaining({ status: TxStatus.PENDING, error: '' }));

    const receiptAfterMined = await tx.wait({ wallet: alice });
    const contractMetadata = await alicePxe.getContractMetadata(deploymentData.address);

    // Expect metadata to be defined
    expect(contractMetadata).toBeDefined();

    // Expect contract to be publicly deployed
    expect(contractMetadata.isContractPubliclyDeployed).toBeTruthy();

    // Expect deployment tx to be successful
    expect(receiptAfterMined).toEqual(expect.objectContaining({ status: TxStatus.SUCCESS }));

    // Expect deployment address to match the pre-computed one
    expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address);
  }, 300_000);

  it('gets the accepted asset', async () => {
    // Fetch accepted asset
    const acceptedAsset = await feePayment.withWallet(alice).methods.get_accepted_asset().simulate();

    // Expect configured asset to match the deployed token
    expect(acceptedAsset.toString()).toBe(token.address.toString());
  }, 300_000);

  it('allows admin to pull funds', async () => {
    // Publicly mint tokens to FPC
    await token.withWallet(alice).methods.mint_to_public(feePayment.address, AMOUNT).send().wait();
    // Expect FPC's balance to increase by the mint amount
    expect(await token.methods.balance_of_public(feePayment.address).simulate()).toBe(AMOUNT);

    // Alice (admin) pulls funds to Bob
    await feePayment.withWallet(alice).methods.pull_funds(bob.getAddress()).send().wait();

    // Expect FPC balance to be zero 
    expect(await token.methods.balance_of_public(feePayment.address).simulate()).toBe(0n);

    // Expect Bob's balance to be the full amount
    expect(await token.methods.balance_of_public(bob.getAddress()).simulate()).toBe(AMOUNT);
  }, 300_000);

  // NOTE: being skipped
  it.skip('processes fee payment with fee_entrypoint_public', async () => {
    const amount = 999999999999999999n;

    // Publicly mint tokens to Alice
    await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), amount).send().wait();

    // Expect Alice's balance to be the full amount
    expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(amount);

    const baseFee = await alice.getCurrentBaseFees();
    console.log("Base fee:", baseFee);

    // Prepare `transfer_public_to_public` call with `fee_entrypoint_public` sponsorship
    // NOTE: fails with `Not enough balance for fee payer to pay for transaction (got 0 needs 6230070240)` since 
    // the FPC does not have any fee juice.
    const tx = await token.withWallet(alice).methods.transfer_public_to_public(alice.getAddress(), bob.getAddress(), 100, 0).send({
      fee: {
        gasSettings: {
          maxFeesPerGas: baseFee
        },
        paymentMethod: new FPCPayment(feePayment, token, alice, false) // flag indicating if the payload should be for a private sponsorship
      }
    }).wait();

    const fee = tx.transactionFee!;
    console.log("Transaction fee:", fee);

    const alice_bal = await token.methods.balance_of_public(alice.getAddress()).simulate();
    const fpc_bal = await token.methods.balance_of_public(feePayment.address).simulate();
    console.log("Alice balance:", alice_bal);
    console.log("FPC balance:", fpc_bal);

  }, 300_000);

  // NOTE: being skipped
  it.skip('processes fee payment with fee_entrypoint_private', async () => {
    const amount = 999999999999999999n;

    // Privately mint tokens to Alice
    await token.withWallet(alice).methods.mint_to_private(alice.getAddress(), alice.getAddress(), amount).send().wait();

    // Expect Alice's private balance to be the full amount
    expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(amount);

    const baseFee = await alice.getCurrentBaseFees();
    console.log("Base fee:", baseFee);

    // Prepare `transfer_private_to_private` call with `fee_entrypoint_private` sponsorship
    // NOTE: fails with `Not enough balance for fee payer to pay for transaction (got 0 needs 6230070240)` since 
    // the FPC does not have any fee juice.
    const tx = await token.withWallet(alice).methods.transfer_private_to_private(alice.getAddress(), bob.getAddress(), 100, 0).send({
      fee: {
        gasSettings: {
          maxFeesPerGas: baseFee
        },
        paymentMethod: new FPCPayment(feePayment, token, alice, true) // true means use private sponsorship
      }
    }).wait();

    const fee = tx.transactionFee!;
    console.log("Transaction fee:", fee);

    const alice_bal = await token.methods.balance_of_public(alice.getAddress()).simulate();
    const fpc_bal = await token.methods.balance_of_public(feePayment.address).simulate();
    console.log("Alice balance:", alice_bal);
    console.log("FPC balance:", fpc_bal);

  }, 300_000);
});
