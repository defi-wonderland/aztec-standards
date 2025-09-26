# Aztec Escrow Standard

The Aztec Escrow Standard provides a privacy-preserving, trust-minimized framework for conditional token transfers on the Aztec Network. This standard enables fully private escrows where terms, participants, and asset details remain hidden from external observers while maintaining verifiable execution conditions.

## Overview

Traditional escrows on public blockchains expose critical information like participant identities, asset amounts, and contract terms. Aztec's privacy-first architecture enables true confidential escrows, but this creates unique challenges around key management, asset discovery, and conditional execution.

The Aztec Escrow Standard solves these challenges through a **two-contract architecture**:

1. **Escrow Contract**: A minimal, standardized contract that holds private balances and executes withdrawals
2. **Logic Contract**: Application-specific contracts that manage escrow policies, participant permissions, and conditional logic

This separation provides maximum flexibility while maintaining security and enabling efficient key sharing patterns.

## Architecture

### Two-Contract Model

```
┌─────────────────┐    Controls    ┌─────────────────┐
│  Logic Contract │ ────────────► │ Escrow Contract │
│                 │                │                 │
│ • Policy logic  │                │ • Holds tokens  │
│ • Key sharing   │                │ • Withdrawals   │
│ • Access control│                │ • Minimal API   │
│ • Notifications │                │                 │
└─────────────────┘                └─────────────────┘
         ▲                                   ▲
         │                                   │
    ┌────▼────┐                         ┌───▼────┐
    │ Creator │                         │Recipient│
    │ (Alice) │                         │  (Bob)  │
    └─────────┘                         └────────┘
```

### Key Components

#### Escrow Contract (`src/escrow_contract`)
- **Purpose**: Minimal contract that holds private token balances
- **Functions**: Only `withdraw()` and `withdraw_nft()` 
- **Access Control**: Only callable by the Logic contract address encoded in its deployment salt
- **State**: Stateless - no storage, no initialization required

#### Logic Contract (Application-Specific)
- **Purpose**: Implements specific escrow policies and manages the escrow lifecycle
- **Responsibilities**:
  - Key validation and sharing
  - Participant authorization
  - Conditional logic enforcement
  - Escrow discovery and notifications
- **Examples**: Clawback escrows, vesting schedules, milestone payments

#### Base Library (`src/escrow_contract/src/logic/base.nr`)
- **Purpose**: Reusable library methods for Logic contract implementations
- **Functions**: `_check_escrow()`, `_share_escrow()`, `_withdraw()`, `_withdraw_nft()`

## Security Model

### Privacy Guarantees

1. **Participant Privacy**: All participant addresses are encrypted in private notes
2. **Amount Privacy**: Token amounts never appear in public state or logs  
3. **Terms Privacy**: Escrow conditions (deadlines, milestones) remain private
4. **Asset Privacy**: Token types and contract addresses are encrypted
5. **Timing Privacy**: Creation and execution times are obfuscated

### Access Control Mechanisms

1. **Salt-Based Authorization**: Escrow contract address encodes the authorized Logic contract
2. **Key Validation**: Master secret keys are verified on-chain before sharing
3. **Instance Verification**: Contract deployment metadata is validated to prevent spoofing
4. **Note-Based Permissions**: Participant roles stored in encrypted private notes

### Key Management

The system uses Aztec's four master secret keys with different security profiles:

- **nsk_m** (Nullifier Secret Key): Required for spending notes - **SHARED with recipients**
- **ivsk_m** (Incoming View Secret Key): Required for reading incoming notes - **SHARED with recipients** 
- **ovsk_m** (Outgoing View Secret Key): For viewing outgoing transactions - **NOT SHARED**
- **tsk_m** (Tagging Secret Key): For note tagging - **NOT SHARED**

Recipients only receive the minimum keys needed for their operations, following the principle of least privilege.

## Integration Guide

### For Escrow Users

1. **Choose a Logic Contract**: Select an existing Logic contract (e.g., ClawbackLogic) or deploy a custom one
2. **Generate Escrow Keys**: Create four master secret keys for the escrow instance
3. **Create Escrow**: Call the Logic contract's creation function with escrow details
4. **Fund Escrow**: Transfer tokens to the computed escrow address
5. **Monitor Events**: Recipients listen for escrow notification events
6. **Execute Conditions**: Participants call appropriate Logic contract functions when conditions are met

### For Logic Contract Developers

1. **Import Base Library**: Use `dep::escrow_contract::logic::base` for standard functions
2. **Implement Required Functions**:
   - Creation function using `_check_escrow()` and `_share_escrow()`
   - Conditional execution functions using `_withdraw()` or `_withdraw_nft()`
3. **Design Note Structure**: Create custom note types for storing escrow state
4. **Validate Conditions**: Implement business logic for escrow release conditions
5. **Handle Edge Cases**: Account for time-based conditions, multiple participants, etc.

## API Reference

### Escrow Contract Interface

#### `withdraw`
Transfers tokens from escrow to recipient's private balance.

```noir
#[private]
fn withdraw(token: AztecAddress, amount: u128, recipient: AztecAddress)
```

**Access**: Only callable by Logic contract (verified via deployment salt)
**Process**: 
1. Validates caller is authorized Logic contract
2. Calls `token.transfer_private_to_private(escrow_address, recipient, amount, 0)`

#### `withdraw_nft`
Transfers an NFT from escrow to recipient's private balance.

```noir
#[private]
fn withdraw_nft(nft: AztecAddress, token_id: Field, recipient: AztecAddress)
```

**Access**: Only callable by Logic contract
**Process**:
1. Validates caller is authorized Logic contract  
2. Calls `nft.transfer_private_to_private(escrow_address, recipient, token_id, 0)`

### Base Library Functions

#### `_check_escrow`
Validates escrow parameters and contract instance data.

```noir
#[contract_library_method]
fn _check_escrow(
    context: &mut PrivateContext,
    escrow: AztecAddress, 
    keys: [Field; 4],
    logic_contract_address: AztecAddress
)
```

**Validations**:
- Escrow address derivation from keys
- Salt contains Logic contract address
- Canonical deployer used
- Valid contract class ID
- Non-zero master secret keys

#### `_share_escrow`
Shares necessary escrow keys with participants via encrypted private logs.

```noir
#[contract_library_method]
fn _share_escrow(
    context: &mut PrivateContext,
    account: AztecAddress,
    escrow: AztecAddress,
    keys: [Field; 4]
)
```

**Security**: Only shares `nsk_m` and `ivsk_m`, excludes sensitive `ovsk_m` and `tsk_m`

#### `_withdraw` / `_withdraw_nft`
Executes withdrawals from escrow contracts.

```noir
#[contract_library_method]
fn _withdraw(
    context: &mut PrivateContext,
    escrow: AztecAddress,
    token: AztecAddress, 
    amount: u128,
    recipient: AztecAddress
)
```

## Example Usage Scenarios

### 1. Simple Payment Escrow

```noir
// Creator deposits 1000 tokens for recipient
logic_contract.create_payment(escrow_address, keys, recipient, token, 1000)

// Recipient claims tokens
logic_contract.claim_payment(escrow_address, token, 1000)
```

### 2. Time-Based Release (Clawback)

```noir
// Creator deposits with 7-day deadline
logic_contract.create_clawback(escrow_address, keys, recipient, owner, token, 1000, deadline)

// Before deadline: recipient claims
logic_contract.claim(escrow_address, token, 1000)

// After deadline: owner claws back
logic_contract.clawback(escrow_address, token, 1000)
```

### 3. Milestone-Based Vesting

```noir
// Creator sets up vesting schedule  
logic_contract.create_vesting(escrow_address, keys, recipient, token, total_amount, milestones)

// Recipient claims available amount at each milestone
logic_contract.release_vested(escrow_address, milestone_id)
```

### 4. Multi-Party Escrow

```noir
// Creator adds multiple recipients
logic_contract.create_multi_escrow(escrow_address, keys, recipients, amounts)

// Each recipient claims their allocation
logic_contract.claim_allocation(escrow_address, recipient_proof)
```

## Implementation Notes

### Address Derivation

Escrow addresses are deterministically computed from the four master secret keys:

```typescript
const keys = [nsk_m, ivsk_m, ovsk_m, tsk_m];
const derivedKeys = deriveKeys(...keys);
const escrowAddress = computeAddress(derivedKeys.publicKeys, EscrowContractArtifact);
```

### Deployment Pattern

Escrow contracts are deployed with the Logic contract address as salt:

```typescript
const salt = new Fr(logicContractAddress.toBigInt());
const escrow = await EscrowContract.deployWithPublicKeys(publicKeys, deployer)
  .send({ contractAddressSalt: salt })
  .deployed();
```

### Event Discovery

Recipients discover escrows by monitoring Logic contract events:

```typescript
// Listen for escrow sharing events
const events = await pxe.getPrivateLogs(logicContractAddress, fromBlock);
const escrowDetails = parseEscrowDetailsFromLogs(events);
```

### Testing Patterns

Comprehensive testing should cover:
- Key validation and address derivation
- Access control enforcement  
- Privacy preservation
- Edge cases and error conditions
- Integration with token standards

## Supported Standards

The escrow system integrates seamlessly with:

- **AIP-20 Token Standard**: For fungible token escrows
- **NFT Standard**: For non-fungible token escrows
- **Future Standards**: Extensible design supports new token types

## Gas Optimization

- **Minimal State**: Escrow contracts are stateless to minimize deployment costs
- **Efficient Lookups**: Note-based storage with optimized search patterns
- **Batch Operations**: Library functions designed for efficient cross-contract calls
- **Note Limits**: Careful management of note operations to stay within gas limits

## Security Auditing

When implementing or auditing escrow contracts, pay special attention to:

1. **Key Management**: Verify only necessary keys are shared
2. **Access Control**: Confirm salt-based authorization is properly implemented  
3. **Time Dependencies**: Check deadline enforcement uses anchor block timestamps
4. **Note Lifecycle**: Ensure notes are properly nullified to prevent replay attacks
5. **Cross-Contract Calls**: Validate all external contract interactions
6. **Edge Cases**: Test boundary conditions, zero amounts, expired deadlines

## Future Extensions

The standard is designed for extensibility:

- **Multi-Token Escrows**: Support for multiple token types in single escrow
- **Conditional Logic**: Complex release conditions based on external oracles
- **Delegation**: Authorized third parties for escrow management
- **Batch Processing**: Multiple escrow operations in single transaction
- **Cross-Chain Integration**: Bridge compatibility for multi-chain escrows

## Resources

- [Escrow Tech Design Document](../../documents/Escrow%20tech%20design/Escrow%20Tech%20Design%2024c9a4c092c780d092a2cb8351ed86e7.md)
- [Clawback Logic Implementation](../clawback_logic_contract/README.md)
- [Security Considerations](./SECURITY.md)
- [Integration Guide](./INTEGRATION.md)
- [AIP-20 Token Standard](../token_contract/README.md)