# Timestamp verification in private circuits

## Overview

In private circuits, timestamps are challenging to use since circuits are timeless, and proofs cannot depend on when they are generated. Aztec’s PrivateContext does not include a timestamp variable due to the transaction lifecycle: proving → broadcasting → inclusion on-chain.

However, many DeFi applications require time-based logic, such as vesting schedules. The usual alternative block numbers may not be suitable in all cases.

## Solution

To verify timestamps privately:

- Users optimistically input the timestamp in the circuit.
- A call to a public function is enqueued to check its validity against the execution timestamp.
- If incorrect, the transaction and state changes (private and public) revert.
- To prevent privacy leaks, this intermediary contract TimeCheck is used:
  - Instead of `ContractA(private)` → `ContractA(public)`,
  - Transaction flows as `ContractA(private)` → `TimeCheck(private)` → `TimeCheck(public)`.

This prevents observers from linking the timestamp check to a specific contract, ensuring confidentiality.
