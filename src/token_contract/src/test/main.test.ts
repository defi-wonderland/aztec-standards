import { TokenContractArtifact, TokenContract } from "../../../artifacts/Token.js"
import { AccountWallet, CompleteAddress, ContractDeployer, createLogger, Fr, PXE, waitForPXE, TxStatus, createPXEClient, getContractInstanceFromDeployParams, Logger } from "@aztec/aztec.js";
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

    it("Deploys the contract", async () => {
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
        const contract = await TokenContract.deploy(wallets[0], "PrivateToken", "PT", 18).send().deployed();
        return contract;
    }

    it("it mints", async () => {
        const candidate = new Fr(1)
        const delegatee = accounts[1].address
        const random = new Fr(2)

        const contract = await deployToken();

        await contract.withWallet(alice)
        const tx =await contract.methods.mint_to_public(bob.getAddress(), 1e18).send().wait();
        const balance = await contract.methods.balance_of_public(bob.getAddress()).simulate();
        expect(balance).toBe(BigInt(1e18));
    }, 300_000)

    it("transfers tokens between public accounts", async () => {
        const contract = await deployToken();
        
        // First mint some tokens to alice
        await contract.withWallet(alice).methods.mint_to_public(alice.getAddress(), 2e18).send().wait();
        
        // Transfer 1 token from alice to bob
        await contract.withWallet(alice).methods.transfer_in_public(alice.getAddress(), bob.getAddress(), 1e18, 0).send().wait();

        // Check balances are correct
        const aliceBalance = await contract.methods.balance_of_public(alice.getAddress()).simulate();
        const bobBalance = await contract.methods.balance_of_public(bob.getAddress()).simulate();
        
        expect(aliceBalance).toBe(BigInt(1e18));
        expect(bobBalance).toBe(BigInt(1e18));
    }, 300_000)

});