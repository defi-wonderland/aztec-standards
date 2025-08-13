# Token Contract

The `Token` contract implements an ERC-20-like token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public balances, offering full coverage of Aztec's confidentiality features.

This implementation provides a robust foundation for fungible tokens on Aztec, enabling developers to build applications with flexible privacy controls and seamless interoperability between private and public states.

## AIP-20: Aztec Token Standard

This contract follows the [AIP-20 Aztec Token Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737). Feel free to review and discuss the specification on the Aztec forum.

## Storage Fields

- `name: str<31>`: Token name (compressed).
- `symbol: str<31>`: Token symbol (compressed).
- `decimals: u8`: Decimal precision.
- `private_balances: Map<AztecAddress, BalanceSet>`: Private balances per account.
- `public_balances: Map<AztecAddress, u128>`: Public balances per account.
- `total_supply: u128`: Total token supply.
- `minter: AztecAddress`: Authorized minter address (if set).
- `upgrade_authority: AztecAddress`: Address allowed to perform contract upgrades (zero address if not upgradeable).

## Initializer Functions

### constructor_with_initial_supply
```rust
/// @notice Initializes the token with an initial supply
/// @dev Since this constructor doesn't set a minter address the mint functions will be disabled
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param initial_supply The initial supply of the token
/// @param to The address to mint the initial supply to
/// @param upgrade_authority The address of the upgrade authority (zero if not upgradeable)
#[public]
#[initializer]
fn constructor_with_initial_supply(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    initial_supply: u128,
    to: AztecAddress,
    upgrade_authority: AztecAddress,
) { /* ... */ }
```

### constructor_with_minter
```rust
/// @notice Initializes the token with a minter
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param minter The address of the minter
/// @param upgrade_authority The address of the upgrade authority (zero if not upgradeable)
#[public]
#[initializer]
fn constructor_with_minter(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    minter: AztecAddress,
    upgrade_authority: AztecAddress,
) { /* ... */ }
```

## View Functions

### balance_of_public
```rust
/// @notice Returns the public balance of `owner`
/// @param owner The address of the owner
/// @return The public balance of `owner`
#[public]
#[view]
fn balance_of_public(owner: AztecAddress) -> u128 { /* ... */ }
```

### total_supply
```rust
/// @notice Returns the total supply of the token
/// @return The total supply of the token
#[public]
#[view]
fn total_supply() -> u128 { /* ... */ }
```

### name
```rust
/// @notice Returns the name of the token
/// @return The name of the token
#[public]
#[view]
fn name() -> FieldCompressedString { /* ... */ }
```

### symbol
```rust
/// @notice Returns the symbol of the token
/// @return The symbol of the token
#[public]
#[view]
fn symbol() -> FieldCompressedString { /* ... */ }
```

### decimals
```rust
/// @notice Returns the decimals of the token
/// @return The decimals of the token
#[public]
#[view]
fn decimals() -> u8 { /* ... */ }
```

## Utility Functions

### balance_of_private
```rust
/// @notice Returns the private balance of `owner`
/// @param owner The address of the owner
/// @return The private balance of `owner`
#[utility]
unconstrained fn balance_of_private(owner: AztecAddress) -> u128 { /* ... */ }
```

## Public Functions

### transfer_public_to_public
```rust
/// @notice Transfers tokens from public balance to public balance
/// @dev Public call to decrease account balance and a public call to increase recipient balance
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_public(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_commitment
```rust
/// @notice Finalizes a transfer of token `amount` from public balance of `from` to a commitment of `to`
/// @dev The transfer must be prepared by calling `initialize_transfer_commitment` first and the resulting
/// `commitment` must be passed as an argument to this function
/// @param from The address of the sender
/// @param commitment The Field representing the commitment (privacy entrance)
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_commitment(
    from: AztecAddress,
    commitment: Field,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### mint_to_public
```rust
/// @notice Mints tokens to a public balance
/// @dev Increases the public balance of `to` by `amount` and the total supply
/// @param to The address of the recipient
/// @param amount The amount of tokens to mint
#[public]
fn mint_to_public(
    to: AztecAddress,
    amount: u128,
) { /* ... */ }
```

### mint_to_commitment
```rust
/// @notice Finalizes a mint to a commitment
/// @dev Finalizes a mint to a commitment and updates the total supply
/// @param commitment The Field representing the mint commitment (privacy entrance)
/// @param amount The amount of tokens to mint
#[public]
fn mint_to_commitment(
    commitment: Field,
    amount: u128,
) { /* ... */ }
```

### burn_public
```rust
/// @notice Burns tokens from a public balance
/// @dev Burns tokens from a public balance and updates the total supply
/// @param from The address of the sender
/// @param amount The amount of tokens to burn
/// @param nonce The nonce used for authwit
#[public]
fn burn_public(
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### upgrade_contract
```rust
/// @notice Upgrades the contract to a new contract class id
/// @dev Only callable by the `upgrade_authority` and effective after the upgrade delay
/// @param new_contract_class_id The new contract class id
#[public]
fn upgrade_contract(new_contract_class_id: Field) { /* ... */ }
```

## Private Functions

### transfer_private_to_public
```rust
/// @notice Transfer tokens from private balance to public balance
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_public(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_public_with_commitment
```rust
/// @notice Transfer tokens from private balance to public balance with a commitment
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, enqueues a public call, and returns a partial note
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
/// @return commitment The partial note utilized for the transfer commitment (privacy entrance)
#[private]
fn transfer_private_to_public_with_commitment(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) -> Field { /* ... */ }
```

### transfer_private_to_private
```rust
/// @notice Transfer tokens from private balance to private balance
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_commitment
```rust
/// @notice Transfer tokens from private balance to the recipient commitment (recipient must create a commitment first)
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
/// @param from The address of the sender
/// @param commitment The Field representing the commitment (privacy entrance that the recipient shares with the sender)
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_commitment(
    from: AztecAddress,
    commitment: Field,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_private
```rust
/// @notice Transfer tokens from public balance to private balance
/// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_public_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### initialize_transfer_commitment
```rust
/// @notice Initializes a transfer commitment to be used for transfers/mints
/// @dev Returns a partial note that can be used to execute transfers/mints
/// @param from The address of the sender
/// @param to The address of the recipient
/// @return commitment The partial note initialized for the transfer/mint commitment
#[private]
fn initialize_transfer_commitment(from: AztecAddress, to: AztecAddress) -> Field { /* ... */ }
```

### mint_to_private
```rust
/// @notice Mints tokens into a private balance
/// @dev Requires minter, enqueues supply update
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to mint
#[private]
fn mint_to_private(from: AztecAddress, to: AztecAddress, amount: u128) { /* ... */ }
```

### burn_private
```rust
/// @notice Burns tokens from a private balance
/// @dev Requires authwit, enqueues supply update
/// @param from The address of the sender
/// @param amount The amount of tokens to burn
/// @param nonce The nonce used for authwit
#[private]
fn burn_private(from: AztecAddress, amount: u128, nonce: Field) { /* ... */ }
```

## Tokenized Vault Security

The Token contract includes advanced tokenized vault functionality with comprehensive protection against inflation attacks and other security vulnerabilities. Understanding these security mechanisms is crucial for safe vault deployment and operations.

### Inflation Attack Overview

**What is an Inflation Attack?**

An inflation attack exploits vaults when they are empty or have very low reserves. The attack works by:

1. **First Deposit**: Attacker deposits minimal amount (e.g., 1 wei) to become the first shareholder, receiving 1 share
2. **Direct Donation**: Attacker directly transfers large amounts to the vault contract (bypassing normal deposit function)
3. **Exchange Rate Manipulation**: The vault now has many assets but only 1 share, creating an inflated exchange rate
4. **Victim Deposit**: When honest users deposit, they receive very few (or zero) shares due to rounding errors
5. **Value Extraction**: Attacker withdraws, capturing value from victim deposits

**Example Attack Scenario:**
```
1. Empty vault: 0 assets, 0 shares
2. Attacker deposits 1 wei → 1 share (1:1 rate)
3. Attacker donates 1,000,000 tokens directly → 1,000,000 assets, 1 share
4. Victim deposits 999,999 tokens → calculates to 0 shares (rounding down)
5. Attacker withdraws 1 share → gets all ~2,000,000 tokens
```

### Security Architecture

The vault implements a **three-layer defense system** against inflation attacks:

#### Layer 1: Virtual Offset (Basic Protection)
All vaults use virtual shares and assets in conversion calculations:
- **Virtual Shares**: Adds offset to total supply in calculations
- **Virtual Assets**: Adds 1 to total assets in calculations
- **Standard Vaults**: Use fixed offset of 1
- **Secure Vaults**: Use configurable offset (minimum 1,000,000)

#### Layer 2: Dead Shares (Enhanced Protection)
Secure vaults create permanent "dead shares" during deployment:
- **Permanent Shares**: Created but never spendable by anyone
- **Nullifier System**: Uses Aztec nullifiers to ensure shares cannot be recovered
- **Initial Anchor**: Provides baseline total supply that cannot be manipulated

#### Layer 3: Bootstrap Deposit (Maximum Protection)
Secure vaults require initial asset deposit during construction:
- **Mandatory Deposit**: Deployer must provide initial assets
- **Economic Protection**: Makes attacks prohibitively expensive
- **Rate Anchoring**: Establishes meaningful initial exchange rate

### Vault Types and Security Levels

#### Standard Vault (Basic Protection)
```rust
// Constructor for standard vault
constructor_with_asset(
    name: str<31>,
    symbol: str<31>, 
    decimals: u8,
    asset: AztecAddress,
    upgrade_authority: AztecAddress,
)
```

**Security Features:**
- ✅ Virtual offset of 1
- ❌ No dead shares
- ❌ No initial deposit requirement
- **Protection Level**: Basic (vulnerable to sophisticated attacks)
- **Use Case**: Testing, low-value assets, when maximum security isn't required

#### Secure Vault (Enhanced Protection) 
```rust
// Constructor for secure vault
constructor_secure_vault(
    name: str<31>,
    symbol: str<31>,
    decimals: u8, 
    asset: AztecAddress,
    security_offset: u128,        // Minimum 1,000,000
    initial_deposit: u128,        // Must be >= security_offset
    upgrade_authority: AztecAddress,
)
```

**Security Features:**
- ✅ Configurable security offset (1M - 1T)
- ✅ Permanent dead shares via nullifier system
- ✅ Mandatory initial deposit requirement
- ✅ Overflow protection in all arithmetic
- ✅ Parameter validation and bounds checking
- **Protection Level**: Maximum (resistant to all known inflation attacks)
- **Use Case**: Production, high-value assets, institutional deployments

### Security Parameters

#### Recommended Security Offset Values
- **Conservative**: `1,000,000` (1M) - Suitable for most use cases
- **Moderate**: `1,000,000,000` (1B) - Higher security for valuable assets  
- **Maximum**: `1,000,000,000,000` (1T) - Institutional-grade protection

#### Initial Deposit Guidelines
- **Minimum**: Must be >= security_offset value
- **Recommended**: 10-100x the security_offset for maximum protection
- **Considerations**: Balance security vs deployment cost

#### Security Offset Impact Analysis
```
Given security_offset = 1,000,000:
- Attack Cost: Attacker must commit ~$1M+ worth of assets
- Attack Profit: Limited by rounding and dead shares absorption
- Net Result: Attack becomes economically unfeasible
```

### Deployment Security Best Practices

#### 1. Pre-Deployment Security Review
- [ ] Choose appropriate vault type for your use case
- [ ] Calculate optimal security_offset for your asset value
- [ ] Ensure sufficient initial_deposit funding
- [ ] Verify asset contract security and compatibility

#### 2. Secure Deployment Pattern
```typescript
// Recommended secure vault deployment
const SECURITY_OFFSET = 1_000_000n; // 1M offset
const INITIAL_DEPOSIT = 10_000_000n; // 10M initial deposit

// Deploy with maximum protection
const vault = await TokenContract.deploy(
    deployer,
    TokenArtifact,
    [
        "SecureVault",           // name
        "SV",                    // symbol  
        6,                       // decimals
        assetAddress,            // underlying asset
        SECURITY_OFFSET,         // security offset
        INITIAL_DEPOSIT,         // initial deposit (deployer pays)
        upgradeAuthority         // upgrade authority
    ],
    'constructor_secure_vault'
).send().deployed();
```

#### 3. Post-Deployment Verification
```typescript
// Verify security parameters were set correctly
const securityOffset = await vault.methods.security_offset().simulate();
const deadShares = await vault.methods.dead_shares_amount().simulate();  
const isInitialized = await vault.methods.is_initialized().simulate();

assert(securityOffset >= 1_000_000n, "Security offset too low");
assert(deadShares === securityOffset, "Dead shares mismatch");
assert(isInitialized === true, "Vault not properly initialized");
```

### Security Monitoring

#### Runtime Security Checks
The vault includes built-in security monitoring:

```rust
// Emergency security validation
fn validate_security_parameters() -> bool;

// Check if vault was properly initialized
fn is_initialized() -> bool;

// View current security parameters
fn security_offset() -> u128;
fn dead_shares_amount() -> u128;
```

#### Red Flags to Monitor
- [ ] **Total supply < dead shares**: Indicates storage corruption
- [ ] **Security offset changed**: Should be immutable after deployment
- [ ] **Uninitialized vault**: Should never happen in production
- [ ] **Arithmetic overflows**: Would revert transactions

### Emergency Procedures

#### If Inflation Attack is Suspected
1. **Immediately pause new deposits** (if pause functionality exists)
2. **Analyze vault state** using view functions
3. **Calculate expected vs actual exchange rates**
4. **Contact security team** for incident response
5. **Consider migration to new secure vault** if compromise confirmed

#### Recovery Options
- **Standard Vault**: Limited options, consider migration
- **Secure Vault**: Built-in protections should prevent successful attacks
- **Community Coordination**: May require coordinated response for large vaults

### Technical Implementation Details

#### Conversion Formula (Secure Vault)
```rust
// Asset to shares conversion with security protection
shares = assets * (total_supply + security_offset) / (total_assets + 1)

// Shares to assets conversion  
assets = shares * (total_assets + 1) / (total_supply + security_offset)
```

#### Dead Shares Implementation
```rust
// Permanent dead shares via nullifier system
fn _create_permanent_dead_shares(amount: u128, deployer: AztecAddress) -> Field {
    let nullifier = pedersen_hash([
        vault_address,
        deployer,
        amount,
        block_number,
        DEAD_SHARES_IDENTIFIER
    ]);
    
    // Emit nullifier (makes it permanent and unspendable)
    push_nullifier(nullifier);
    
    // Increase total supply but create no spendable notes
    total_supply += amount;
}
```

### Audit and Testing

The vault security has been comprehensively tested:
- ✅ **Parameter validation**: All edge cases covered
- ✅ **Overflow protection**: Arithmetic safety verified
- ✅ **Attack simulation**: Multiple attack vectors tested
- ✅ **Integration testing**: Works with all vault functions
- ✅ **Gas optimization**: Efficient circuit constraints

See `/test/tokenized_vault/inflation_attack_prevention.nr` for detailed test coverage.

---

**⚠️ Security Notice**: Always use secure vaults for production deployments with valuable assets. Standard vaults are provided for compatibility but offer minimal protection against sophisticated attacks.

**💡 Best Practice**: When in doubt about security parameters, err on the side of higher security offset values. The cost of increased security is minimal compared to the potential loss from successful attacks.

