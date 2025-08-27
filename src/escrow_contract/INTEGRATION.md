# Aztec Escrow Integration Guide

This comprehensive guide provides developers with everything needed to integrate the Aztec Escrow Standard into their applications. Whether building custom Logic contracts, integrating existing escrow patterns, or creating new escrow-based features, this guide covers implementation patterns, best practices, and practical examples.

## Quick Start

### Prerequisites

- Aztec development environment v1.1.2
- Understanding of Noir smart contract development
- Familiarity with Aztec's privacy model and note system
- Basic knowledge of TypeScript for integration testing

### Basic Integration Steps

1. **Import the Escrow Standard**
2. **Implement or Choose a Logic Contract**  
3. **Generate Escrow Keys and Deploy**
4. **Implement Client-Side Integration**
5. **Handle Escrow Discovery and Execution**

## Building Custom Logic Contracts

### Implementation Template

Every Logic contract should follow this basic structure:

```noir
mod test;

use aztec::macros::aztec;

#[aztec]
pub contract YourLogicContract {
    // Import base escrow library
    use dep::escrow_contract::logic::base::{_check_escrow, _share_escrow, _withdraw};
    
    // Import or define custom note types
    use dep::escrow_contract::types::your_custom_note::YourCustomNote;
    
    // Storage for escrow state
    #[storage]
    struct Storage<Context> {
        escrow_notes: PrivateSet<YourCustomNote, Context>,
    }
    
    // Required: Escrow creation function
    #[private]
    fn create_escrow(/* your parameters */) {
        // 1. Validate escrow using base library
        _check_escrow(&mut context, escrow, keys, context.this_address());
        
        // 2. Prevent duplicates with nullifier
        // 3. Share keys with participants
        // 4. Create and store custom notes
        // 5. Implement your business logic
    }
    
    // Required: Execution function(s)
    #[private] 
    fn execute_condition(/* your parameters */) {
        // 1. Find and validate relevant notes
        // 2. Check your custom conditions
        // 3. Execute withdrawal using base library
        _withdraw(&mut context, escrow, token, amount, recipient);
    }
}
```

### Key Derivation and Verification

#### Address Computation Pattern

All escrow addresses must be deterministically computed from master secret keys:

```typescript
import { deriveKeys, computeAddress } from '@aztec/aztec.js';
import { EscrowContractArtifact } from './artifacts/Escrow.js';

function computeEscrowAddress(keys: [Fr, Fr, Fr, Fr]): { address: AztecAddress; publicKeys: PublicKeys } {
    const [nsk_m, ivsk_m, ovsk_m, tsk_m] = keys;
    const derivedKeys = deriveKeys(nsk_m, ivsk_m, ovsk_m, tsk_m);
    const publicKeys = derivedKeys.publicKeys;
    const address = computeAddress(publicKeys, EscrowContractArtifact);
    return { address, publicKeys };
}
```

#### Key Validation in Noir

```noir
#[contract_library_method]
pub fn validate_and_share_keys(
    context: &mut PrivateContext,
    escrow: AztecAddress,
    keys: [Field; 4],
    recipient: AztecAddress,
) {
    // Validate escrow parameters
    _check_escrow(context, escrow, keys, context.this_address());
    
    // Share only necessary keys with recipient
    _share_escrow(context, recipient, escrow, keys);
}
```

### Note Management Patterns

#### Custom Note Design

Design notes that capture your escrow's specific requirements:

```noir
use aztec::{
    context::PrivateContext,
    keys::getters::{get_nsk_app, get_public_keys},
    macros::notes::custom_note,
    note::note_interface::NoteHash,
    oracle::random::random,
    protocol_types::{
        address::AztecAddress,
        constants::{GENERATOR_INDEX__NOTE_HASH, GENERATOR_INDEX__NOTE_NULLIFIER},
        hash::poseidon2_hash_with_separator,
        traits::{Hash, Serialize, ToField},
    },
};

#[custom_note]
#[derive(Eq, Serialize)]
pub struct VestingNote {
    escrow: AztecAddress,
    beneficiary: AztecAddress,
    token: AztecAddress,
    total_amount: u128,
    released_amount: u128,
    start_time: u64,
    duration: u64,
    randomness: Field,
}

impl VestingNote {
    pub fn new(
        escrow: AztecAddress,
        beneficiary: AztecAddress,
        token: AztecAddress,
        total_amount: u128,
        start_time: u64,
        duration: u64,
    ) -> Self {
        let randomness = unsafe { random() };
        Self {
            escrow,
            beneficiary,
            token,
            total_amount,
            released_amount: 0,
            start_time,
            duration,
            randomness,
        }
    }
    
    pub fn calculate_vested_amount(&self, current_time: u64) -> u128 {
        if current_time <= self.start_time {
            return 0;
        }
        
        if current_time >= self.start_time + self.duration {
            return self.total_amount;
        }
        
        let elapsed = current_time - self.start_time;
        (self.total_amount * elapsed as u128) / self.duration as u128
    }
}

// Implement required NoteHash trait
impl NoteHash for VestingNote {
    fn compute_note_hash(self, storage_slot: Field) -> Field {
        let serialized = [
            self.escrow.to_field(),
            self.beneficiary.to_field(),
            self.token.to_field(),
            self.total_amount as Field,
            self.released_amount as Field,
            self.start_time as Field,
            self.duration as Field,
            self.randomness,
            storage_slot,
        ];
        
        poseidon2_hash_with_separator(serialized, GENERATOR_INDEX__NOTE_HASH)
    }

    fn compute_nullifier(
        self,
        context: &mut PrivateContext,
        note_hash_for_nullify: Field,
    ) -> Field {
        let owner_npk_m = get_public_keys(self.beneficiary).npk_m;
        let owner_npk_m_hash = owner_npk_m.hash();
        let secret = context.request_nsk_app(owner_npk_m_hash);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret],
            GENERATOR_INDEX__NOTE_NULLIFIER,
        )
    }

    unconstrained fn compute_nullifier_unconstrained(self, note_hash_for_nullify: Field) -> Field {
        let owner_npk_m = get_public_keys(self.beneficiary).npk_m;
        let owner_npk_m_hash = owner_npk_m.hash();
        let secret = get_nsk_app(owner_npk_m_hash);
        poseidon2_hash_with_separator(
            [note_hash_for_nullify, secret],
            GENERATOR_INDEX__NOTE_NULLIFIER,
        )
    }
}
```

#### Efficient Note Search

Implement gas-efficient note discovery patterns:

```noir
fn find_vesting_note(
    storage: &mut Storage<PrivateContext>,
    escrow: AztecAddress,
    beneficiary: AztecAddress,
) -> VestingNote {
    let options = NoteGetterOptions::new()
        .set_limit(32) // Prevent unbounded gas usage
        .set_offset(0);
        
    let notes = storage.vesting_notes.pop_notes(options);
    
    let mut found_note = VestingNote::new(
        AztecAddress::from_field(0),
        AztecAddress::from_field(0),
        AztecAddress::from_field(0),
        0,
        0,
        0,
    );
    let mut note_found = false;
    
    // Use constant-time loop to avoid timing attacks
    for i in 0..options.limit {
        if i < notes.len() {
            let note = notes.get_unchecked(i);
            let matches = (note.escrow == escrow) & (note.beneficiary == beneficiary);
            
            // Conditionally update found_note without branching
            found_note = VestingNote {
                escrow: if matches { note.escrow } else { found_note.escrow },
                beneficiary: if matches { note.beneficiary } else { found_note.beneficiary },
                token: if matches { note.token } else { found_note.token },
                total_amount: if matches { note.total_amount } else { found_note.total_amount },
                released_amount: if matches { note.released_amount } else { found_note.released_amount },
                start_time: if matches { note.start_time } else { found_note.start_time },
                duration: if matches { note.duration } else { found_note.duration },
                randomness: if matches { note.randomness } else { found_note.randomness },
            };
            
            note_found = note_found | matches;
        }
    }
    
    assert(note_found, "VestingNote not found");
    found_note
}
```

### Testing Strategies

#### Unit Testing Framework

```noir
mod test {
    use super::*;
    use aztec::test::helpers::{TestEnvironment, advance_block_by};
    
    #[test]
    fn test_vesting_note_calculation() {
        let note = VestingNote::new(
            AztecAddress::from_field(1),
            AztecAddress::from_field(2),
            AztecAddress::from_field(3),
            1000,
            100, // start_time
            200  // duration (100 + 200 = 300 end_time)
        );
        
        // At start time
        assert_eq(note.calculate_vested_amount(100), 0);
        
        // At 25% through vesting
        assert_eq(note.calculate_vested_amount(150), 250);
        
        // At 50% through vesting
        assert_eq(note.calculate_vested_amount(200), 500);
        
        // After vesting ends
        assert_eq(note.calculate_vested_amount(400), 1000);
    }
    
    #[test]
    fn test_escrow_creation_and_execution() {
        let env = TestEnvironment::new();
        let (alice, bob) = (env.accounts[0], env.accounts[1]);
        
        // Generate escrow keys
        let keys = [
            env.random_field(),
            env.random_field(), 
            env.random_field(),
            env.random_field(),
        ];
        
        let escrow_address = compute_escrow_address(keys);
        
        // Test escrow creation
        let logic_contract = VestingLogicContract::deploy(alice);
        
        logic_contract.create_vesting(
            escrow_address,
            keys,
            bob,
            env.token_address,
            1000,
            env.current_timestamp(),
            86400, // 1 day vesting
        ).call(alice);
        
        // Advance time and test release
        env.advance_block_by(43200); // 12 hours
        
        logic_contract.release(
            escrow_address,
            env.token_address,
        ).call(bob);
        
        // Verify 50% released
        let bob_balance = env.get_private_balance(bob, env.token_address);
        assert_eq(bob_balance, 500);
    }
}
```

#### Integration Testing

```typescript
import { describe, beforeAll, it, expect } from '@jest/globals';
import { Fr, TxStatus } from '@aztec/aztec.js';

describe('Custom Logic Integration Tests', () => {
    let pxe: PXE;
    let wallets: AccountWalletWithSecretKey[];
    let logic: YourLogicContract;
    let token: TokenContract;

    beforeAll(async () => {
        ({ pxe, wallets } = await setupIntegrationTest());
        [alice, bob] = wallets;
        
        // Deploy contracts
        logic = await YourLogicContract.deploy(alice).send().deployed();
        token = await deployTokenWithMinter(alice, {});
    });

    describe('End-to-End Escrow Flow', () => {
        it('should create, fund, and execute escrow', async () => {
            // 1. Generate escrow keys
            const keys = generateMasterSecretKeys();
            const { address: escrowAddress, publicKeys } = computeEscrowAddress(keys);

            // 2. Deploy escrow with Logic contract as salt
            const salt = new Fr(logic.address.toBigInt());
            const escrow = await EscrowContract.deployWithPublicKeys(publicKeys, alice)
                .send({ contractAddressSalt: salt })
                .deployed();

            expect(escrow.address).toEqual(escrowAddress);

            // 3. Create escrow through Logic contract
            const createTx = await logic.methods
                .create_escrow(escrowAddress, keys, bob.address, /* other params */)
                .send()
                .wait();

            expect(createTx.status).toBe(TxStatus.SUCCESS);

            // 4. Fund escrow
            const fundTx = await token.methods
                .transfer_private_to_private(alice.address, escrowAddress, 1000n, 0)
                .send()
                .wait();

            expect(fundTx.status).toBe(TxStatus.SUCCESS);

            // 5. Execute escrow condition
            const executeTx = await logic.methods
                .execute_condition(escrowAddress, /* params */)
                .send()
                .wait();

            expect(executeTx.status).toBe(TxStatus.SUCCESS);

            // 6. Verify final balances
            const finalBalance = await token.methods.balance_of(bob.address).simulate();
            expect(finalBalance).toBeGreaterThan(0n);
        });
    });
});
```

## Client-Side Integration

### Escrow Discovery

#### Event Monitoring

```typescript
class EscrowDiscoveryService {
    constructor(private pxe: PXE, private logicContractAddress: AztecAddress) {}

    async monitorEscrowEvents(fromBlock: number = 0): Promise<EscrowEvent[]> {
        const events = await this.pxe.getPrivateLogs(this.logicContractAddress, fromBlock);
        const escrowEvents: EscrowEvent[] = [];

        for (const event of events) {
            try {
                const escrowDetails = this.parseEscrowDetails(event);
                if (escrowDetails) {
                    escrowEvents.push({
                        escrowAddress: escrowDetails.escrow,
                        keys: escrowDetails.keys,
                        blockNumber: event.blockNumber,
                        txHash: event.txHash,
                    });
                }
            } catch (error) {
                // Skip invalid events
                continue;
            }
        }

        return escrowEvents;
    }

    private parseEscrowDetails(event: any): EscrowDetailsLogContent | null {
        try {
            // Parse encrypted private log content
            const decrypted = this.decryptPrivateLog(event);
            return EscrowDetailsLogContent.fromBuffer(decrypted);
        } catch {
            return null;
        }
    }
}
```

#### Key Management

```typescript
class EscrowKeyManager {
    private keyStore: Map<string, [Fr, Fr, Fr, Fr]> = new Map();

    storeKeys(escrowAddress: AztecAddress, keys: [Fr, Fr, Fr, Fr]): void {
        this.keyStore.set(escrowAddress.toString(), keys);
    }

    getKeys(escrowAddress: AztecAddress): [Fr, Fr, Fr, Fr] | null {
        return this.keyStore.get(escrowAddress.toString()) || null;
    }

    // Only share necessary keys with recipients
    getRecipientKeys(escrowAddress: AztecAddress): [Fr, Fr] | null {
        const keys = this.getKeys(escrowAddress);
        if (!keys) return null;
        
        return [keys[0], keys[1]]; // nsk_m, ivsk_m only
    }

    clearKeys(escrowAddress: AztecAddress): void {
        this.keyStore.delete(escrowAddress.toString());
    }
}
```

### User Interface Patterns

#### Escrow Creation Flow

```typescript
interface CreateEscrowParams {
    recipient: AztecAddress;
    token: AztecAddress;
    amount: bigint;
    deadline: number;
}

class EscrowUI {
    async createEscrow(params: CreateEscrowParams): Promise<{ escrowAddress: AztecAddress; txHash: string }> {
        // 1. Generate secure keys
        const keys = generateMasterSecretKeys();
        const { address: escrowAddress, publicKeys } = computeEscrowAddress(keys);

        // 2. Deploy escrow contract
        const salt = new Fr(this.logicContract.address.toBigInt());
        const escrow = await EscrowContract.deployWithPublicKeys(publicKeys, this.wallet)
            .send({ contractAddressSalt: salt })
            .deployed();

        // 3. Create escrow through Logic contract
        const createTx = await this.logicContract.methods
            .create_clawback(
                escrowAddress,
                keys,
                params.recipient,
                this.wallet.address,
                params.token,
                params.amount,
                params.deadline
            )
            .send()
            .wait();

        if (createTx.status !== TxStatus.SUCCESS) {
            throw new Error('Failed to create escrow');
        }

        // 4. Fund escrow
        await this.fundEscrow(escrowAddress, params.token, params.amount);

        // 5. Store keys securely
        this.keyManager.storeKeys(escrowAddress, keys);

        return {
            escrowAddress,
            txHash: createTx.txHash.toString()
        };
    }

    private async fundEscrow(escrowAddress: AztecAddress, token: AztecAddress, amount: bigint): Promise<void> {
        const tokenContract = TokenContract.at(token, this.wallet);
        
        const fundTx = await tokenContract.methods
            .transfer_private_to_private(this.wallet.address, escrowAddress, amount, 0)
            .send()
            .wait();

        if (fundTx.status !== TxStatus.SUCCESS) {
            throw new Error('Failed to fund escrow');
        }
    }
}
```

#### Recipient Claiming Flow

```typescript
class RecipientUI {
    async claimEscrow(escrowAddress: AztecAddress, token: AztecAddress, amount: bigint): Promise<string> {
        // Verify we have the necessary keys
        const keys = this.keyManager.getRecipientKeys(escrowAddress);
        if (!keys) {
            throw new Error('No keys available for this escrow');
        }

        // Check escrow balance before claiming
        const balance = await this.getEscrowBalance(escrowAddress, token);
        if (balance < amount) {
            throw new Error('Insufficient escrow balance');
        }

        // Execute claim
        const claimTx = await this.logicContract.methods
            .claim(escrowAddress, token, amount)
            .send()
            .wait();

        if (claimTx.status !== TxStatus.SUCCESS) {
            throw new Error(`Claim failed: ${claimTx.error}`);
        }

        return claimTx.txHash.toString();
    }

    private async getEscrowBalance(escrowAddress: AztecAddress, token: AztecAddress): Promise<bigint> {
        const tokenContract = TokenContract.at(token, this.wallet);
        return await tokenContract.methods.balance_of(escrowAddress).simulate();
    }
}
```

## Advanced Integration Patterns

### Multi-Token Escrows

```noir
#[custom_note]
#[derive(Eq, Serialize)]
pub struct MultiTokenEscrowNote {
    escrow: AztecAddress,
    recipient: AztecAddress,
    owner: AztecAddress,
    tokens: [AztecAddress; MAX_TOKENS],
    amounts: [u128; MAX_TOKENS],
    token_count: u32,
    deadline: u64,
    randomness: Field,
}

impl MultiTokenEscrowNote {
    pub fn add_token(&mut self, token: AztecAddress, amount: u128) -> bool {
        if self.token_count >= MAX_TOKENS as u32 {
            return false;
        }
        
        let index = self.token_count as comptime_int;
        self.tokens[index] = token;
        self.amounts[index] = amount;
        self.token_count += 1;
        true
    }
}
```

### Conditional Release Patterns

```noir
#[private]
fn conditional_release(
    escrow: AztecAddress,
    condition_proof: Field,
    oracle_signature: Field,
) {
    let note = find_conditional_note(escrow);
    
    // Verify condition proof
    assert(verify_condition_proof(condition_proof, note.condition), "Invalid condition proof");
    
    // Verify oracle signature if required
    if note.requires_oracle {
        assert(verify_oracle_signature(oracle_signature, condition_proof), "Invalid oracle signature");
    }
    
    // Execute release
    _withdraw(&mut context, escrow, note.token, note.amount, note.recipient);
}
```

### Batch Operations

```noir
#[private]
fn batch_create_escrows(
    escrows: [AztecAddress; MAX_BATCH_SIZE],
    keys_array: [[Field; 4]; MAX_BATCH_SIZE],
    recipients: [AztecAddress; MAX_BATCH_SIZE],
    amounts: [u128; MAX_BATCH_SIZE],
    batch_size: u32,
) {
    for i in 0..MAX_BATCH_SIZE {
        if i < batch_size {
            create_single_escrow(escrows[i], keys_array[i], recipients[i], amounts[i]);
        }
    }
}
```

### Cross-Chain Integration

```typescript
class CrossChainEscrowBridge {
    async createCrossChainEscrow(
        sourceChain: string,
        targetChain: string,
        bridgeParams: CrossChainParams
    ): Promise<CrossChainEscrowResult> {
        // 1. Create escrow on source chain
        const sourceEscrow = await this.createSourceChainEscrow(bridgeParams);
        
        // 2. Generate proof of escrow creation
        const proof = await this.generateCrossChainProof(sourceEscrow);
        
        // 3. Create corresponding escrow on target chain
        const targetEscrow = await this.createTargetChainEscrow(proof, bridgeParams);
        
        return {
            sourceEscrow: sourceEscrow.address,
            targetEscrow: targetEscrow.address,
            bridgeProof: proof
        };
    }
}
```

## Migration and Upgrade Patterns

### Contract Migration

```typescript
class EscrowMigrationService {
    async migrateToNewLogicContract(
        oldLogicContract: AztecAddress,
        newLogicContract: AztecAddress,
        escrows: AztecAddress[]
    ): Promise<MigrationResult[]> {
        const results: MigrationResult[] = [];
        
        for (const escrowAddress of escrows) {
            try {
                // 1. Extract parameters from old escrow
                const oldParams = await this.extractEscrowParams(oldLogicContract, escrowAddress);
                
                // 2. Create new escrow with updated logic
                const newEscrow = await this.createMigratedEscrow(newLogicContract, oldParams);
                
                // 3. Transfer tokens from old to new escrow
                await this.transferEscrowFunds(escrowAddress, newEscrow.address, oldParams.amount);
                
                results.push({
                    oldEscrow: escrowAddress,
                    newEscrow: newEscrow.address,
                    status: 'success'
                });
            } catch (error) {
                results.push({
                    oldEscrow: escrowAddress,
                    newEscrow: null,
                    status: 'failed',
                    error: error.message
                });
            }
        }
        
        return results;
    }
}
```

### Data Migration

```typescript
interface MigrationData {
    escrowAddress: AztecAddress;
    keys: [Fr, Fr, Fr, Fr];
    participants: AztecAddress[];
    tokens: TokenInfo[];
    conditions: EscrowConditions;
    metadata: EscrowMetadata;
}

class DataMigrationHelper {
    async exportEscrowData(logicContract: AztecAddress): Promise<MigrationData[]> {
        // Export all escrow data for migration
        const events = await this.pxe.getPrivateLogs(logicContract, 0);
        const migrationData: MigrationData[] = [];
        
        for (const event of events) {
            const data = await this.parseEscrowEvent(event);
            if (data) {
                migrationData.push(data);
            }
        }
        
        return migrationData;
    }
    
    async importEscrowData(newLogicContract: AztecAddress, migrationData: MigrationData[]): Promise<void> {
        for (const data of migrationData) {
            await this.recreateEscrow(newLogicContract, data);
        }
    }
}
```

## Performance Optimization

### Gas Optimization Strategies

```noir
// Use constant-time operations to prevent timing attacks
fn optimized_note_search(storage: &mut Storage<PrivateContext>) -> YourNote {
    let options = NoteGetterOptions::new().set_limit(16); // Smaller limit for gas efficiency
    let notes = storage.your_notes.pop_notes(options);
    
    // Pre-allocate result to avoid dynamic memory allocation
    let mut result = YourNote::empty();
    let mut found = false;
    
    // Unrolled loop for better gas efficiency
    if notes.len() > 0 { 
        let note = notes.get_unchecked(0);
        let matches = check_note_matches(note);
        result = conditional_select(matches, note, result);
        found = found | matches;
    }
    
    if notes.len() > 1 {
        let note = notes.get_unchecked(1);
        let matches = check_note_matches(note);
        result = conditional_select(matches, note, result);
        found = found | matches;
    }
    
    // Continue for remaining slots...
    
    assert(found, "Note not found");
    result
}
```

### Batching Strategies

```typescript
class BatchProcessor {
    private batchSize = 10;
    private pendingOperations: EscrowOperation[] = [];
    
    async queueOperation(operation: EscrowOperation): Promise<void> {
        this.pendingOperations.push(operation);
        
        if (this.pendingOperations.length >= this.batchSize) {
            await this.processBatch();
        }
    }
    
    private async processBatch(): Promise<void> {
        if (this.pendingOperations.length === 0) return;
        
        const batch = this.pendingOperations.splice(0, this.batchSize);
        
        try {
            await this.executeBatchTransaction(batch);
        } catch (error) {
            // Re-queue failed operations for retry
            this.pendingOperations.unshift(...batch);
            throw error;
        }
    }
}
```

## Error Handling and Recovery

### Comprehensive Error Handling

```typescript
class EscrowErrorHandler {
    async handleEscrowOperation<T>(
        operation: () => Promise<T>,
        context: EscrowOperationContext
    ): Promise<T> {
        try {
            return await operation();
        } catch (error) {
            return await this.handleError(error, context);
        }
    }
    
    private async handleError(error: any, context: EscrowOperationContext): Promise<never> {
        // Log error with context
        console.error('Escrow operation failed:', {
            operation: context.operation,
            escrowAddress: context.escrowAddress,
            error: error.message,
            timestamp: new Date().toISOString()
        });
        
        // Attempt recovery based on error type
        if (error.message.includes('deadline has passed')) {
            throw new EscrowDeadlineError(context.escrowAddress, context.deadline);
        }
        
        if (error.message.includes('insufficient balance')) {
            throw new InsufficientEscrowBalanceError(context.escrowAddress, context.requestedAmount);
        }
        
        if (error.message.includes('unauthorized')) {
            throw new UnauthorizedEscrowAccessError(context.escrowAddress, context.caller);
        }
        
        // Generic error
        throw new EscrowOperationError(context.escrowAddress, error.message);
    }
}
```

### Recovery Mechanisms

```typescript
class EscrowRecoveryService {
    async recoverStuckEscrow(
        escrowAddress: AztecAddress,
        recoveryProof: RecoveryProof
    ): Promise<RecoveryResult> {
        // Validate recovery proof
        if (!await this.validateRecoveryProof(recoveryProof)) {
            throw new Error('Invalid recovery proof');
        }
        
        // Attempt different recovery strategies
        const strategies = [
            () => this.recoverViaTimelock(escrowAddress),
            () => this.recoverViaMultisig(escrowAddress, recoveryProof),
            () => this.recoverViaEmergencyExit(escrowAddress)
        ];
        
        for (const strategy of strategies) {
            try {
                const result = await strategy();
                if (result.success) {
                    return result;
                }
            } catch (error) {
                // Try next strategy
                continue;
            }
        }
        
        throw new Error('All recovery strategies failed');
    }
}
```

This integration guide provides comprehensive patterns and examples for building robust, secure, and efficient integrations with the Aztec Escrow Standard. Use these patterns as starting points and adapt them to your specific use cases while maintaining the security and privacy guarantees of the system.