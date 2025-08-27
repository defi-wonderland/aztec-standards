# Clawback Logic Contract

A comprehensive implementation of time-based clawback escrows using the Aztec Escrow Standard. This contract demonstrates how to build privacy-preserving conditional transfers with deadline-based access control, serving as both a production-ready solution and a reference implementation for custom escrow logic.

## Overview

The Clawback Logic contract implements a "time-locked" escrow pattern where:
- **Before deadline**: Recipients can claim escrowed tokens
- **After deadline**: Original owners can clawback unclaimed tokens
- **Full privacy**: All participants, amounts, and deadlines remain confidential

This creates a trust-minimized mechanism for conditional payments, refundable deposits, time-limited offers, and similar use cases where reversal rights are needed.

## Architecture

The clawback system consists of three coordinated components:

```
┌─────────────────────┐    Creates & Controls    ┌─────────────────────┐
│ ClawbackLogic       │ ─────────────────────────► │ Escrow Contract     │
│ Contract            │                            │ (Token Holder)      │
│                     │                            │                     │
│ • Policy enforcement│◄─── Withdrawal Requests ──│ • Private balances  │
│ • Time validation   │                            │ • Transfer execution│
│ • Note management   │                            │ • Access control    │
│ • Key sharing       │                            │                     │
└─────────────────────┘                            └─────────────────────┘
         ▲
         │ ClawbackNotes
         ▼
┌─────────────────────┐                            ┌─────────────────────┐
│ Recipient (Bob)     │                            │ Owner (Alice)       │
│                     │                            │                     │
│ • Claim before      │                            │ • Clawback after    │
│   deadline          │                            │   deadline          │
│ • Receives escrow   │                            │ • Creates escrow    │
│   keys              │                            │ • Manages terms     │
└─────────────────────┘                            └─────────────────────┘
```

### Key Components

1. **ClawbackLogic Contract**: Manages escrow lifecycle and enforces time-based conditions
2. **Escrow Contract**: Holds private token balances and executes authorized withdrawals  
3. **ClawbackNote**: Private notes storing escrow parameters and participant permissions
4. **Base Library**: Reusable functions for key validation, sharing, and withdrawals

## Clawback Mechanism

### Timeline Enforcement

The contract uses Aztec's anchor block timestamps to enforce deadline-based access:

```
Escrow Created          Deadline Reached          
      │                        │                  
      ▼                        ▼                  
   ┌─────────────────────────┬───────────────────►
   │   RECIPIENT PERIOD      │   OWNER PERIOD    
   │   (Bob can claim)       │  (Alice can claw) 
   └─────────────────────────┴───────────────────►
                             
Timeline: ──────────────────────────────────────►
```

- **Creation**: Owner deposits tokens and sets deadline
- **Recipient Period**: Before deadline, only recipient can withdraw
- **Owner Period**: After deadline, only owner can clawback remaining tokens
- **Mutual Exclusivity**: Only one party can succeed - first withdrawal nullifies the notes

### Deadline Validation

```noir
let current_timestamp = context.get_block_header().global_variables.timestamp;

// For recipient claims
assert(
    current_timestamp < deadline,
    "ClawbackLogic: deadline has passed, tokens can only be clawed back by owner"
);

// For owner clawbacks  
assert(
    current_timestamp >= deadline,
    "ClawbackLogic: deadline has not passed, recipient can still claim tokens"
);
```

## API Reference

### Core Functions

#### `create_clawback`
Establishes a new time-locked escrow with clawback rights.

```noir
#[private]
fn create_clawback(
    escrow: AztecAddress,
    keys: [Field; 4],
    recipient: AztecAddress,
    owner: AztecAddress,
    token: AztecAddress,
    amount: u128,
    deadline: u64,
)
```

**Parameters:**
- `escrow`: Computed address of escrow contract instance
- `keys`: Master secret keys `[nsk_m, ivsk_m, ovsk_m, tsk_m]`
- `recipient`: Address authorized to claim before deadline
- `owner`: Address authorized to clawback after deadline  
- `token`: Contract address of escrowed token
- `amount`: Quantity of tokens in escrow
- `deadline`: Unix timestamp when clawback becomes available

**Process:**
1. **Validation**: Verifies escrow address and instance data via `_check_escrow()`
2. **Duplication Prevention**: Pushes randomized nullifier to prevent duplicate creation
3. **Key Sharing**: Distributes necessary keys to recipient via `_share_escrow()`
4. **Note Creation**: Creates ClawbackNotes for both recipient and owner with escrow terms
5. **Privacy**: All details encrypted and visible only to designated participants

**Security Features:**
- Unpredictable nullifiers prevent front-running attacks
- Key validation ensures escrow contract authenticity
- Separate notes for recipient and owner enable independent discovery

#### `claim`
Allows recipients to withdraw tokens before the deadline expires.

```noir
#[private]
fn claim(escrow: AztecAddress, token: AztecAddress, amount: u128)
```

**Parameters:**
- `escrow`: Address of the escrow contract holding tokens
- `token`: Address of the token contract to withdraw
- `amount`: Exact amount to claim (must match escrow amount)

**Access Control:**
- Only callable by the designated recipient address
- Only executable before deadline timestamp
- Requires matching ClawbackNote with caller as recipient

**Process:**
1. **Note Discovery**: Searches through caller's ClawbackNotes for matching escrow
2. **Validation**: Confirms caller is authorized recipient and deadline hasn't passed
3. **Nullification**: Consumes the ClawbackNote to prevent reuse
4. **Withdrawal**: Executes token transfer via `_withdraw()` to recipient
5. **Cleanup**: Note consumption prevents owner from later clawback attempts

#### `clawback`  
Allows owners to reclaim tokens after the deadline has passed.

```noir
#[private]
fn clawback(escrow: AztecAddress, token: AztecAddress, amount: u128)
```

**Parameters:**
- `escrow`: Address of the escrow contract holding tokens
- `token`: Address of the token contract to clawback
- `amount`: Exact amount to reclaim (must match escrow amount)

**Access Control:**
- Only callable by the original owner address
- Only executable after deadline timestamp
- Requires matching ClawbackNote with caller as owner

**Process:**
1. **Note Discovery**: Locates ClawbackNote matching escrow with caller as owner
2. **Validation**: Confirms caller is authorized owner and deadline has passed
3. **Nullification**: Consumes the ClawbackNote to prevent reuse
4. **Withdrawal**: Executes token transfer via `_withdraw()` back to owner
5. **Finalization**: Completes escrow lifecycle with token return

## Implementation Details

### Storage Architecture

```noir
#[storage]
struct Storage<Context> {
    /// Private set containing ClawbackNotes for all active escrows
    /// Each escrow generates two notes: one for recipient, one for owner
    clawback_notes: PrivateSet<ClawbackNote, Context>,
}
```

### ClawbackNote Structure

```noir
pub struct ClawbackNote {
    escrow: AztecAddress,      // Escrow contract holding tokens
    recipient: AztecAddress,   // Who can claim before deadline  
    owner: AztecAddress,       // Who can clawback after deadline
    token: AztecAddress,       // Token contract address
    amount: u128,              // Quantity of tokens
    deadline: u64,             // Unix timestamp for access transition
    randomness: Field,         // Privacy protection
}
```

**Privacy Features:**
- **Encrypted Storage**: Notes are encrypted to their intended recipients
- **Random Values**: Prevents brute-force attacks on note discovery
- **Selective Sharing**: Each participant only sees their relevant notes
- **Address Obfuscation**: Contract addresses hidden from external observers

### Note Management Pattern

The contract uses a **dual-note strategy** for maximum privacy and flexibility:

1. **Recipient Note**: Encrypted to recipient, enables claim operations
2. **Owner Note**: Encrypted to owner, enables clawback operations  
3. **Independent Discovery**: Each party finds their notes without coordination
4. **Mutual Exclusion**: First successful withdrawal nullifies both notes

### Search and Validation

```noir
// Efficient note search with gas optimization
let options = NoteGetterOptions::new().set_limit(32);
let notes = storage.clawback_notes.pop_notes(options);

// Linear search through owned notes
for i in 0..options.limit {
    if i < notes.len() {
        let note = notes.get_unchecked(i);
        if (note.get_escrow() == escrow) 
            & (note.get_recipient() == caller)  // or owner for clawback
            & (note.get_token() == token) 
            & (note.get_amount() == amount) {
            found_note = note;
            note_found = true;
        }
    }
}
```

## Usage Examples

### Basic Clawback Escrow

```typescript
// 1. Setup: Owner creates 7-day clawback escrow
const deadline = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60); // 7 days
await clawbackLogic.methods
  .create_clawback(escrowAddress, keys, recipientAddress, ownerAddress, tokenAddress, 1000n, deadline)
  .send().wait();

// 2. Funding: Owner transfers tokens to escrow  
await token.methods
  .transfer_private_to_private(ownerAddress, escrowAddress, 1000n, nonce)
  .send().wait();

// 3a. Success Path: Recipient claims within deadline
await clawbackLogic.methods
  .claim(escrowAddress, tokenAddress, 1000n)
  .send().wait();

// 3b. Fallback Path: Owner claws back after deadline  
await clawbackLogic.methods
  .clawback(escrowAddress, tokenAddress, 1000n) 
  .send().wait();
```

### Escrow Discovery Pattern

```typescript
// Recipient monitors for escrow notifications
const events = await pxe.getPrivateLogs(clawbackLogicAddress, fromBlock);
for (const event of events) {
  if (isEscrowDetailsEvent(event)) {
    const escrowDetails = parseEscrowDetails(event);
    console.log(`New escrow: ${escrowDetails.escrow}, deadline: ${escrowDetails.deadline}`);
  }
}
```

### Multi-Escrow Management

```typescript
// Owner creates multiple escrows with different terms
const escrows = [
  { recipient: bob, amount: 1000n, deadline: deadline1 },
  { recipient: charlie, amount: 2000n, deadline: deadline2 },  
  { recipient: dave, amount: 500n, deadline: deadline3 },
];

for (const escrowConfig of escrows) {
  const keys = generateMasterSecretKeys();
  const { address: escrowAddress } = computeEscrowAddress(keys);
  
  await clawbackLogic.methods.create_clawback(
    escrowAddress, keys, escrowConfig.recipient, owner,
    tokenAddress, escrowConfig.amount, escrowConfig.deadline
  ).send().wait();
}
```

## Security Considerations

### Time-Based Attacks

**Issue**: Block timestamp manipulation
**Mitigation**: Uses anchor block timestamps which are consensus-validated and harder to manipulate

**Issue**: Deadline precision  
**Mitigation**: Consider reasonable buffer periods for deadline-sensitive operations

### Note Management Security

**Issue**: Note replay attacks
**Mitigation**: Notes are properly nullified after use, preventing double-spending

**Issue**: Note discovery attacks
**Mitigation**: Random values in notes prevent brute-force discovery of escrow details

### Access Control Validation

**Issue**: Unauthorized withdrawals
**Mitigation**: Multiple validation layers:
- Escrow contract validates Logic contract as caller via salt
- Logic contract validates participant addresses via ClawbackNotes
- Timestamp validation ensures deadline enforcement

**Issue**: Front-running attacks
**Mitigation**: Nullifiers use unpredictable randomness to prevent front-running

### Key Management Risks  

**Issue**: Over-sharing of master keys
**Mitigation**: Base library only shares necessary keys (nsk_m, ivsk_m), withholds sensitive keys (ovsk_m, tsk_m)

**Issue**: Key validation bypasses
**Mitigation**: `_check_escrow()` validates escrow address derivation and contract instance integrity

## Advanced Patterns

### Conditional Clawbacks

Extend the pattern with additional conditions:

```noir
// Example: Clawback only if recipient hasn't performed specific action
fn conditional_clawback(escrow: AztecAddress, token: AztecAddress, amount: u128, condition_proof: Field) {
    // Validate deadline has passed
    let current_timestamp = context.get_block_header().global_variables.timestamp;
    assert(current_timestamp >= found_note.get_deadline(), "Deadline not reached");
    
    // Validate additional condition 
    assert(verify_condition(condition_proof), "Condition not met for clawback");
    
    _withdraw(context, escrow, token, amount, owner);
}
```

### Partial Claims

Support incremental withdrawals:

```noir
// Modified ClawbackNote with claimed_amount tracking
struct PartialClawbackNote {
    escrow: AztecAddress,
    recipient: AztecAddress, 
    owner: AztecAddress,
    token: AztecAddress,
    total_amount: u128,
    claimed_amount: u128,  // Track partial claims
    deadline: u64,
    randomness: Field,
}
```

### Multi-Token Escrows

Extend to support multiple token types:

```noir
struct MultiTokenClawbackNote {
    escrow: AztecAddress,
    recipient: AztecAddress,
    owner: AztecAddress,
    tokens: [AztecAddress; MAX_TOKENS],
    amounts: [u128; MAX_TOKENS], 
    token_count: u32,
    deadline: u64,
    randomness: Field,
}
```

## Testing Strategy

### Unit Tests
- Key validation and escrow creation
- Deadline enforcement under various scenarios
- Note lifecycle and nullification  
- Access control for claim/clawback functions
- Error handling for invalid inputs

### Integration Tests  
- End-to-end escrow workflows
- Multi-participant scenarios
- Time progression and deadline effects
- Cross-contract interactions with token standards
- Event emission and discovery patterns

### Edge Cases
- Boundary conditions around deadlines
- Zero amounts and invalid addresses
- Duplicate escrow creation attempts
- Note discovery with large note sets
- Gas limit considerations for note operations

## Performance Optimizations

### Gas Efficiency
- **Fixed Loop Bounds**: Uses `NoteGetterOptions.set_limit(32)` to prevent unbounded gas consumption
- **Early Termination**: Breaks loops once matching notes are found
- **Minimal State**: Leverages stateless escrow contracts to reduce storage costs

### Note Management
- **Batching**: Consider batching multiple escrows in single transaction
- **Pruning**: Remove expired notes to reduce search space
- **Indexing**: Use structured note organization for faster lookups

## Deployment Guide

### Prerequisites
1. Deployed Escrow contract artifact
2. ClawbackLogic contract with correct imports
3. Token contracts for testing
4. PXE connection for private operations

### Deployment Steps

```typescript
// 1. Deploy ClawbackLogic contract
const clawbackLogic = await ClawbackLogicContract.deploy(deployer).send().deployed();

// 2. Generate escrow keys and compute address
const keys = generateMasterSecretKeys();
const { address: escrowAddress, publicKeys } = computeEscrowAddress(keys);

// 3. Deploy Escrow with ClawbackLogic as salt
const salt = new Fr(clawbackLogic.address.toBigInt());
const escrow = await EscrowContract.deployWithPublicKeys(publicKeys, deployer)
  .send({ contractAddressSalt: salt })
  .deployed();

// 4. Verify deployment
console.log('ClawbackLogic:', clawbackLogic.address);
console.log('Escrow:', escrow.address);
console.log('Salt verification:', await pxe.getContractInstance(escrow.address));
```

## Migration and Upgrades

### Contract Upgrades
- ClawbackLogic contracts are not upgradeable - deploy new versions for changes
- Existing escrows continue operating with original Logic contract
- Gradual migration by creating new escrows with updated Logic contract

### Data Migration  
- ClawbackNotes are private and non-transferable between contract versions
- Export escrow parameters from old contract events if needed for new versions
- Consider grace periods for users to complete existing escrows before deprecation

## Integration Examples

See the comprehensive integration examples in [INTEGRATION.md](../escrow_contract/INTEGRATION.md) and refer to the test suite in `test/clawback.test.ts` for detailed usage patterns.

This implementation provides a robust foundation for time-based conditional transfers while maintaining Aztec's privacy guarantees. The modular design enables easy customization for specific use cases while preserving security and efficiency.