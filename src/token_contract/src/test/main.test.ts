import { TokenContractArtifact, TokenContract, PreparePrivateBalanceIncrease } from "../../../artifacts/Token.js"
import { AccountWallet, CompleteAddress, ContractDeployer, createLogger, Fr, PXE, waitForPXE, TxStatus, createPXEClient, getContractInstanceFromDeployParams, Logger, Tx, SentTx, FieldsOf, TxReceipt, Contract, computeAuthWitMessageHash, computeInnerAuthWitHash } from "@aztec/aztec.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing"
import { deployInitialTestAccounts } from '@aztec/accounts/testing';

const setupSandbox = async () => {
    const { PXE_URL = 'http://localhost:8080' } = process.env;
    const pxe = createPXEClient(PXE_URL);
    await waitForPXE(pxe);
    return pxe;
};

describe("Token", () => {
    let pxe: PXE;
    let wallets: AccountWallet[] = [];
    let accounts: CompleteAddress[] = [];

    let alice: AccountWallet;
    let bob: AccountWallet;
    let carl: AccountWallet;

    let token: TokenContract;

    const AMOUNT = 1000

    let logger: Logger;

    beforeAll(async () => {
        logger = createLogger('aztec:aztec-starter');
        logger.info("Aztec-Starter tests running.")

        pxe = await setupSandbox();

        wallets = await getInitialTestAccountsWallets(pxe);
        accounts = wallets.map(w => w.getCompleteAddress())

        alice = wallets[0];
        bob = wallets[1];
        carl = wallets[2];
    })

    beforeEach(async () => {
        token = await deployToken() as TokenContract;

    })

    it("deploys the contract", async () => {
        const salt = Fr.random();
        const [deployerWallet] = wallets; // using first account as deployer

        const deploymentData = await getContractInstanceFromDeployParams(TokenContractArtifact,
            {
                constructorArgs: [
                    "PrivateToken", "PT", 18
                ],
                salt,
                deployer: deployerWallet.getAddress()
            });
        const deployer = new ContractDeployer(TokenContractArtifact, deployerWallet);
        const tx = deployer.deploy("PrivateToken", "PT", 18).send({ contractAddressSalt: salt })
        const receipt = await tx.getReceipt();

        expect(receipt).toEqual(
            expect.objectContaining({
                status: TxStatus.PENDING,
                error: ''
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

        expect(receiptAfterMined.contract.instance.address).toEqual(deploymentData.address)
    }, 300_000)

    async function deployToken() {
        const contract = await Contract.deploy(alice, TokenContractArtifact, ["PrivateToken", "PT", 18]).send().deployed();
        return contract;
    }

    it("mints", async () => {

        await token.withWallet(alice)
        const tx = await token.methods.mint_to_public(bob.getAddress(), AMOUNT).send().wait();
        const balance = await token.methods.balance_of_public(bob.getAddress()).simulate();
        expect(balance).toBe(BigInt(AMOUNT));
    }, 300_000)

    it("transfers tokens between public accounts", async () => {
        
        
        // First mint 2 tokens to alice
        await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), AMOUNT * 2).send().wait();
        
        // Transfer 1 token from alice to bob
        await token.withWallet(alice).methods.transfer_in_public(alice.getAddress(), bob.getAddress(), AMOUNT, 0).send().wait();

        // Check balances are correct
        const aliceBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
        const bobBalance = await token.methods.balance_of_public(bob.getAddress()).simulate();
        
        expect(aliceBalance).toBe(BigInt(AMOUNT));
        expect(bobBalance).toBe(BigInt(AMOUNT));
    }, 300_000)

    it("burns public tokens", async () => {
        
        
        // First mint 2 tokens to alice
        await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), AMOUNT * 2).send().wait();
        
        // Burn 1 token from alice
        await token.withWallet(alice).methods.burn_public(alice.getAddress(), AMOUNT, 0).send().wait();

        // Check balance and total supply are reduced
        const aliceBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
        const totalSupply = await token.methods.total_supply().simulate();
        
        expect(aliceBalance).toBe(BigInt(AMOUNT));
        expect(totalSupply).toBe(BigInt(AMOUNT));
    }, 300_000)

    it("transfers tokens from private to public balance", async () => {
        
        
        // First mint to private 2 tokens to alice
        await token.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(), 
            AMOUNT * 2
        ).send().wait();
        
        // Transfer 1 token from alice's private balance to public balance
        await token.withWallet(alice).methods.transfer_to_public(
            alice.getAddress(),
            alice.getAddress(),
            AMOUNT, 0
        ).send().wait();

        // Check public balance is correct
        const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(BigInt(AMOUNT));

        // Check total supply hasn't changed
        const totalSupply = await token.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(AMOUNT * 2));
    }, 300_000)

    it("fails when using an invalid nonce", async () => {

        // Mint 1 token privately to alice
        await token.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(), 
            AMOUNT
        ).send().wait();
        
        // This fails because of the nonce check
        await expect(
            token.withWallet(alice).methods.transfer_to_public(
                alice.getAddress(),
                alice.getAddress(),
                AMOUNT * 2,
                BigInt(1)
            ).send().wait()
        ).rejects.toThrow(/invalid nonce/);
    }, 300_000)

    it("fails when transferring more tokens than available in private balance", async () => {
           
        // Mint 1 token privately to alice
        await token.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(), 
            AMOUNT
        ).send().wait();
        
        // Try to transfer 2 tokens from private to public balance
        await expect(
            token.withWallet(alice).methods.transfer_to_public(
                alice.getAddress(),
                alice.getAddress(),
                AMOUNT + 1,
                BigInt(0)
            ).send().wait()
        ).rejects.toThrow();
    }, 300_000)

    it("can transfer tokens between private balances", async () => {
        
        
        // Mint 2 tokens privately to alice
        await token.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(),
            AMOUNT * 2
        ).send().wait();

        // Transfer 1 token from alice to bob's private balance
        await token.withWallet(alice).methods.transfer(
            bob.getAddress(),
            AMOUNT
        ).send().wait();

        // Try to transfer more than available balance
        await expect(
            token.withWallet(alice).methods.transfer(
                bob.getAddress(),
                AMOUNT + 1
            ).send().wait()
        ).rejects.toThrow(/Balance too low/);

        // Check total supply hasn't changed
        const totalSupply = await token.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(AMOUNT * 2));
    }, 300_000)

    it("can mint tokens to private balance", async () => {
        
        
        // Mint 2 tokens privately to alice
        await token.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(),
            AMOUNT * 2
        ).send().wait();

        // Check total supply increased
        const totalSupply = await token.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(AMOUNT * 2));

        // Public balance should be 0 since we minted privately
        const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(0n);
    }, 300_000)

    it("can burn tokens from private balance", async () => {
        
        
        // Mint 2 tokens privately to alice
        await token.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(),
            AMOUNT * 2
        ).send().wait();

        // Burn 1 token from alice's private balance
        await token.withWallet(alice).methods.burn_private(alice.getAddress(),AMOUNT,0).send().wait();

        // Try to burn more than available balance
        await expect(
            token.withWallet(alice).methods.burn_private(
                alice.getAddress(),
                AMOUNT * 2,
                0
            ).send().wait()
        ).rejects.toThrow(/Balance too low/);

        // Check total supply decreased
        const totalSupply = await token.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(AMOUNT));

        // Public balance should still be 0
        const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(0n);
    }, 300_000)

    it("can transfer tokens from public to private balance", async () => {
        
        
        // Mint 2 tokens publicly to alice
        await token.withWallet(alice).methods.mint_to_public(
            alice.getAddress(),
            AMOUNT * 2
        ).send().wait();

        // Transfer 1 token from alice's public balance to private balance
        await token.withWallet(alice).methods.transfer_to_private(
            alice.getAddress(),
            AMOUNT
        ).send().wait();

        // Try to transfer more than available public balance
        await expect(
            token.withWallet(alice).methods.transfer_to_private(
                alice.getAddress(),
                AMOUNT * 2
            ).send().wait()
        ).rejects.toThrow(/attempt to subtract with underflow/);

        // Check total supply stayed the same
        const totalSupply = await token.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(AMOUNT * 2));

        // Public balance should be reduced by transferred amount
        const alicePublicBalance = await token.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(BigInt(AMOUNT));
    }, 300_000)

    
    it("mint in public, prepare partial note and finalize it", async () => {
        
        await token.withWallet(alice)

        await token.methods.mint_to_public(alice.getAddress(), AMOUNT).send().wait();

        // alice has tokens in public
        expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(BigInt(AMOUNT));
        expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(0n);
        // bob has 0 tokens
        expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(0n);
        expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(0n);

        expect(await token.methods.total_supply().simulate()).toBe(BigInt(AMOUNT));

        // alice prepares partial note for bob
        await token.methods.prepare_private_balance_increase(bob.getAddress(), alice.getAddress()).send().wait()
        // alice still has tokens in public
        expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(BigInt(AMOUNT));
        // read bob's encrypted logs
        const bobEncryptedEvents = await bob.getPrivateEvents<PreparePrivateBalanceIncrease>(
            TokenContract.events.PreparePrivateBalanceIncrease,
            1,
            100 // todo: add a default value for limit?
        )
        // get the latest event
        const latestEvent = bobEncryptedEvents[bobEncryptedEvents.length - 1]
        // finalize partial note passing the hiding point slot
        await token.methods.finalize_transfer_to_private(AMOUNT, latestEvent.hiding_point_slot).send().wait();
        // alice now has no tokens
        expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(BigInt(0n));
        // bob has tokens in private
        expect(await token.methods.balance_of_public(bob.getAddress()).simulate()).toBe(0n);
        expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(BigInt(AMOUNT));
        // total supply is still the same
        expect(await token.methods.total_supply().simulate()).toBe(BigInt(AMOUNT));
    }, 300_000)

    it("public transfer with authwitness", async () => {
        

        await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), AMOUNT).send().wait();

        const nonce = Fr.random()
        const action = token.withWallet(carl).methods.transfer_in_public(alice.getAddress(), bob.getAddress(), AMOUNT, nonce)

        await alice.setPublicAuthWit({
            caller: carl.getAddress(),
            action
        }, true).send().wait()

        await action.send().wait()

        expect(await token.methods.balance_of_public(alice.getAddress()).simulate()).toBe(0n);
        expect(await token.methods.balance_of_public(bob.getAddress()).simulate()).toBe(BigInt(AMOUNT));
    }, 300_000)

    it("private transfer with authwitness", async () => {
        // deploy token contract
        

        // setup balances
        await token.withWallet(alice).methods.mint_to_public(alice.getAddress(), AMOUNT).send().wait();
        await token.withWallet(alice).methods.transfer_to_private(alice.getAddress(), AMOUNT).send().wait();

        expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(BigInt(AMOUNT));

        // prepare action
        const nonce = Fr.random()
        const action = token.withWallet(carl).methods.transfer_in_private(alice.getAddress(), bob.getAddress(), AMOUNT, nonce)

        const witness = await alice.createAuthWit({
            caller: carl.getAddress(),
            action
        })
        // await carl.addAuthWitness(witness)

        const validity = await alice.lookupValidity(alice.getAddress(), {
            caller: carl.getAddress(),
            action
        })
        expect(validity.isValidInPrivate).toBeTruthy()
        expect(validity.isValidInPublic).toBeFalsy()

        // dev: This grants carl access to alice's private notes
        carl.setScopes([carl.getAddress(), alice.getAddress()])

        await action.send().wait()

        expect(await token.methods.balance_of_private(alice.getAddress()).simulate()).toBe(0n);
        expect(await token.methods.balance_of_private(bob.getAddress()).simulate()).toBe(BigInt(AMOUNT));
    }, 300_000)

});