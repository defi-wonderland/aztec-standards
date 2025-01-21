import { TokenContractArtifact, TokenContract } from "../../../artifacts/Token.js"
import { AccountWallet, CompleteAddress, ContractDeployer, createLogger, Fr, PXE, waitForPXE, TxStatus, createPXEClient, getContractInstanceFromDeployParams, Logger, Tx, SentTx, FieldsOf, TxReceipt, Contract } from "@aztec/aztec.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing"
import { deployInitialTestAccounts } from '@aztec/accounts/testing';

const setupSandbox = async () => {
    const { PXE_URL = 'http://localhost:8080' } = process.env;
    // TODO: implement reading the DelegationNote from an isolated PXE
    // 8080: cd ~/.aztec && docker-compose -f ./docker-compose.sandbox.yml up
    // 8081: aztec start --port 8081 --pxe --pxe.nodeUrl http://host.docker.internal:8080/
    // const DELEGATEE_PXE_URL = 'http://localhost:8081';

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

    let logger: Logger;

    beforeAll(async () => {
        logger = createLogger('aztec:aztec-starter');
        logger.info("Aztec-Starter tests running.")

        pxe = await setupSandbox();
        // deployInitialTestAccounts(pxe); // NOTE: run at least once in sandbox to circumvent issue #9384

        wallets = await getInitialTestAccountsWallets(pxe);
        accounts = wallets.map(w => w.getCompleteAddress())

        alice = wallets[0];
        bob = wallets[1];
        carl = wallets[2];
    })

    it("deploys the contract", async () => {
        const salt = Fr.random();
        // const VotingContractArtifact = EasyPrivateVotingContractArtifact
        const [deployerWallet, adminWallet] = wallets; // using first account as deployer and second as contract admin
        const adminAddress = adminWallet.getCompleteAddress().address;

        const deploymentData = getContractInstanceFromDeployParams(TokenContractArtifact,
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
        const salt = Fr.random();
        const contract = await Contract.deploy(alice, TokenContractArtifact, ["PrivateToken", "PT", 18]).send().deployed();
        // const contract = await TokenContract.deploy(wallets[0], )
        console.log("contract deployed", contract.address)
        return contract;
    }

    it("mints", async () => {
        const contract = await deployToken();

        await contract.withWallet(alice)
        const tx =await contract.methods.mint_to_public(bob.getAddress(), 1e18).send().wait();
        const balance = await contract.methods.balance_of_public(bob.getAddress()).simulate();
        expect(balance).toBe(BigInt(1e18));
    }, 300_000)

    it("transfers tokens between public accounts", async () => {
        const contract = await deployToken();
        
        // First mint 2 tokens to alice
        await contract.withWallet(alice).methods.mint_to_public(alice.getAddress(), 2e18).send().wait();
        
        // Transfer 1 token from alice to bob
        await contract.withWallet(alice).methods.transfer_in_public(alice.getAddress(), bob.getAddress(), 1e18, 0).send().wait();

        // Check balances are correct
        const aliceBalance = await contract.methods.balance_of_public(alice.getAddress()).simulate();
        const bobBalance = await contract.methods.balance_of_public(bob.getAddress()).simulate();
        
        expect(aliceBalance).toBe(BigInt(1e18));
        expect(bobBalance).toBe(BigInt(1e18));
    }, 300_000)

    it("burns public tokens", async () => {
        const contract = await deployToken();
        
        // First mint 2 tokens to alice
        await contract.withWallet(alice).methods.mint_to_public(alice.getAddress(), 2e18).send().wait();
        
        // Burn 1 token from alice
        await contract.withWallet(alice).methods.burn_public(alice.getAddress(), 1e18, 0).send().wait();

        // Check balance and total supply are reduced
        const aliceBalance = await contract.methods.balance_of_public(alice.getAddress()).simulate();
        const totalSupply = await contract.methods.total_supply().simulate();
        
        expect(aliceBalance).toBe(BigInt(1e18));
        expect(totalSupply).toBe(BigInt(1e18));
    }, 300_000)

    it("transfers tokens from private to public balance", async () => {
        const contract = await deployToken();
        
        // First mint to private 23 tokens to alice
        await contract.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(), 
            2e18
        ).send().wait();
        
        // Transfer 1 token from alice's private balance to public balance
        await contract.withWallet(alice).methods.transfer_to_public(
            alice.getAddress(),
            alice.getAddress(),
            1e18, 0
        ).send().wait();

        // Check public balance is correct
        const alicePublicBalance = await contract.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(BigInt(1e18));

        // Check total supply hasn't changed
        const totalSupply = await contract.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(2e18));
    }, 300_000)

    it("fails when transferring more tokens than available in private balance", async () => {
        const contract = await deployToken();
        
        // Mint 1 token privately to alice
        await contract.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(), 
            1e18
        ).send().wait();
        
        // This fails because of the nonce check
        await expect(
            contract.withWallet(alice).methods.transfer_to_public(
                alice.getAddress(),
                alice.getAddress(),
                2e18,
                BigInt(1)
            ).send().wait()
        ).rejects.toThrow(/invalid nonce/);

        // Try to transfer 2 tokens from private to public balance
        await expect(
            contract.withWallet(alice).methods.transfer_to_public(
                alice.getAddress(),
                alice.getAddress(),
                2e18,
                BigInt(0)
            ).send().wait()
        ).rejects.toThrow();
    }, 300_000)

    it("can transfer tokens between private balances", async () => {
        const contract = await deployToken();
        
        // Mint 2 tokens privately to alice
        await contract.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(),
            2e18
        ).send().wait();

        // Transfer 1 token from alice to bob's private balance
        await contract.withWallet(alice).methods.transfer(
            bob.getAddress(),
            1e18
        ).send().wait();

        // Try to transfer more than available balance
        await expect(
            contract.withWallet(alice).methods.transfer(
                bob.getAddress(),
                2e18
            ).send().wait()
        ).rejects.toThrow(/Balance too low/);

        // Check total supply hasn't changed
        const totalSupply = await contract.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(2e18));
    }, 300_000)

    it("can mint tokens to private balance", async () => {
        const contract = await deployToken();
        
        // Mint 2 tokens privately to alice
        await contract.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(),
            2e18
        ).send().wait();

        // Check total supply increased
        const totalSupply = await contract.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(2e18));

        // Public balance should be 0 since we minted privately
        const alicePublicBalance = await contract.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(BigInt(0));
    }, 300_000)

    it("can burn tokens from private balance", async () => {
        const contract = await deployToken();
        
        // Mint 2 tokens privately to alice
        await contract.withWallet(alice).methods.mint_to_private(
            alice.getAddress(),
            alice.getAddress(),
            2e18
        ).send().wait();

        // Burn 1 token from alice's private balance
        await contract.withWallet(alice).methods.burn_private(
            alice.getAddress(),
            1e18,
            0
        ).send().wait();

        // Try to burn more than available balance
        await expect(
            contract.withWallet(alice).methods.burn_private(
                alice.getAddress(),
                2e18,
                0
            ).send().wait()
        ).rejects.toThrow(/Balance too low/);

        // Check total supply decreased
        const totalSupply = await contract.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(1e18));

        // Public balance should still be 0
        const alicePublicBalance = await contract.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(BigInt(0));
    }, 300_000)

    it("can transfer tokens from public to private balance", async () => {
        const contract = await deployToken();
        
        // Mint 2 tokens publicly to alice
        await contract.withWallet(alice).methods.mint_to_public(
            alice.getAddress(),
            2e18
        ).send().wait();

        // Transfer 1 token from alice's public balance to private balance
        await contract.withWallet(alice).methods.transfer_to_private(
            alice.getAddress(),
            1e18
        ).send().wait();

        // Try to transfer more than available public balance
        // await expect(
        //     contract.withWallet(alice).methods.transfer_to_private(
        //         alice.getAddress(),
        //         2e18
        //     ).send().wait()
        // ).rejects.toThrow(/Balance too low/);

        // Check total supply stayed the same
        const totalSupply = await contract.methods.total_supply().simulate();
        expect(totalSupply).toBe(BigInt(2e18));

        // Public balance should be reduced by transferred amount
        const alicePublicBalance = await contract.methods.balance_of_public(alice.getAddress()).simulate();
        expect(alicePublicBalance).toBe(BigInt(1e18));
    }, 300_000)


});