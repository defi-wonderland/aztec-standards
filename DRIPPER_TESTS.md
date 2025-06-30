
# Dripper Contract Tests

This document describes the test suite created for the Dripper contract, which provides a simple faucet for minting tokens into private or public balances.

## Test Structure

### Noir Tests (src/dripper/src/test/)

The Noir tests are organized into the following modules:

#### 1. Utils Module (`utils.nr`)
- **Purpose**: Provides common utilities and setup functions for testing
- **Key Functions**:
  - `setup_dripper_and_token()`: Sets up test environment with both token and dripper contracts
  - `deploy_token_with_minter()`: Deploys a token contract with a specified minter
  - `deploy_dripper()`: Deploys the dripper contract
  - `check_public_balance()`: Verifies public token balances
  - `check_private_balance()`: Verifies private token balances
  - `check_total_supply()`: Verifies total token supply

#### 2. Public Dripping Tests (`drip_to_public.nr`)
- **`drip_to_public_success()`**: Tests that Alice can successfully mint tokens to her public balance
- **`drip_to_public_multiple_users()`**: Tests that multiple users can drip tokens independently
- **`drip_to_public_large_amount()`**: Tests dripping large amounts of tokens

#### 3. Private Dripping Tests (`drip_to_private.nr`)
- **`drip_to_private_success()`**: Tests that Alice can successfully mint tokens to her private balance
- **`drip_to_private_multiple_users()`**: Tests that multiple users can drip tokens privately
- **`drip_to_private_large_amount()`**: Tests dripping large amounts of tokens privately

### JavaScript Tests (src/ts/test/dripper.test.ts)

The JavaScript integration tests provide end-to-end testing of the Dripper contract:

#### Test Setup
- Uses the Aztec testing framework with PXE (Private eXecution Environment)
- Creates test accounts (Alice, Bob, Carl) using Schnorr account contracts
- Deploys both Token and Dripper contracts before each test

#### Test Categories

##### 1. Public Dripping Tests (`drip_to_public`)
- **Basic functionality**: Alice mints tokens to public balance and verifies correct amounts
- **Multiple users**: Both Alice and Bob can drip tokens independently
- **Large amounts**: Tests handling of large token amounts (1,000,000 tokens)
- **Multiple drips**: Alice can drip multiple times, with balances accumulating correctly

##### 2. Private Dripping Tests (`drip_to_private`)
- **Basic functionality**: Alice mints tokens to private balance and verifies correct amounts
- **Multiple users**: Both Alice and Bob can drip tokens privately and independently
- **Large amounts**: Tests handling of large token amounts privately
- **Multiple drips**: Alice can drip privately multiple times

##### 3. Mixed Dripping Tests (`mixed dripping`)
- **Public and private**: Alice can drip to both public and private balances in the same test

## Test Scenarios Covered

### Core Functionality
1. **Token Minting**: Verifies that the dripper correctly mints tokens using the underlying token contract
2. **Balance Verification**: Ensures tokens appear in the correct balance type (public vs private)
3. **Supply Tracking**: Confirms that total supply increases correctly with each drip

### Edge Cases
1. **Large Amounts**: Tests with 1,000,000 tokens to ensure no overflow issues
2. **Multiple Users**: Verifies that different users can use the dripper independently
3. **Multiple Drips**: Ensures users can drip multiple times and balances accumulate correctly

### Privacy Features
1. **Public Balance**: Tokens minted to public balances are visible and verifiable
2. **Private Balance**: Tokens minted to private balances maintain privacy while still being verifiable by the owner
3. **Balance Separation**: Public and private balances are maintained separately

## Key Test Assertions

### For Public Dripping
- Alice's public balance increases by the drip amount
- Alice's private balance remains 0
- Total supply increases by the drip amount
- Multiple users can drip independently without affecting each other

### For Private Dripping
- Alice's private balance increases by the drip amount
- Alice's public balance remains 0
- Total supply increases by the drip amount
- Private balances are maintained separately for different users

### For Mixed Scenarios
- Both public and private balances can be increased independently
- Total supply reflects the sum of all minted tokens

## Running the Tests

### Noir Tests
```bash
yarn test:nr
```

### JavaScript Tests
```bash
yarn test:js
```

### All Tests
```bash
yarn test
```

## Notes

- The tests assume that the Dripper contract has appropriate minting permissions on the token contract
- Private balance tests include proper randomness mocking for note creation
- All tests use a standard drip amount of 1000 tokens unless testing large amounts
- The test environment uses dummy accounts for efficiency in Noir tests
- JavaScript tests use full account contracts for more realistic integration testing

