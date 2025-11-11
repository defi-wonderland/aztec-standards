# Token Contract Invariants

<p style="background:#fff3cd; color:#856404; padding:0.5em 1em; border-left:4px solid #ffecb5;">
  <strong>Important:</strong> These invariants are described but *not* tested using standard tools (eg property-based fuzzed tests, formal verification), as not tool has reached maturity yet.
</p>

Note:

- Trail of Bits reusable properties for ERC20, for reference <https://github.com/crytic/properties/blob/main/PROPERTIES.md#erc20>
- Zero address or self transfers are not considered in the AIP20 and, as such, don't have invariants around them.

## Invariants

### INV-1: No user balance greater than total Supply

```markdown
  total_supply = sum(all_public_balances) + sum(all_private_balances)
```

There is no balance greater than total supply, and the sum of all balances is always equal to total supply.

----

### INV-2: Total Supply Immutability During Transfers

```markdown
  for all transfer operations:
  total_supply_before = total_supply_after
```

----

### INV-3: No transfer more than balance

```markdown
  for all transfer operations:
    balance_sender_before >= amount
```

----

### INV-4: Transfer of zero amount should not break accounting

```markdown
  balance_sender_after = balance_sender_before
  balance_recipient_after = balance_recipient_before
```

----

### INV-5: Transfer should update accounting correctly

```markdown
  balance_sender_after = balance_sender_before - amount
  balance_recipient_after = balance_recipient_before + amount
```

> precondition: sender != recipient

### INV-5b: Transfer to self should not break accounting

```markdown
  for any transfered amount to self:
  balance_self_after = balance_self_before
```

----

### INV-6: Burn should update accounting correctly

```markdown
  balance_sender_after = balance_sender_before - amount
  total_supply_after = total_supply_before - amount
```

----

### INV-7: Mint should update accounting correctly

```markdown
  balance_recipient_after = balance_recipient_before + amount
  total_supply_after = total_supply_before + amount
```

----

### INV-8: Commitment Single-Use

Each partial note/commitment can be used at most once

----

### INV-9: Private - Public Transfer Conservation

```markdown
For any transfer between privacy domains:
  (sender_private + sender_public + recipient_private + recipient_public)_before =
  (sender_private + sender_public + recipient_private + recipient_public)_after
```
