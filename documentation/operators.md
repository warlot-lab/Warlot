# The operator model

How a backend signing from a rotating pool of wallets acts for a user, without that user re-granting
anything when a key changes.

## The problem it replaces

The system used to name **one address**, fixed at the mint with no setter, copied into every user's
delegation table at registration. So a second signing key held nothing, and a lost first key could
not be replaced without every user acting. Under key rotation that is not a delegation model at all.

## A credential is a duplicate capability, not an address

An operator is a **duplicate `AdminCap`** holding a slot in the system's operator set.

```move
entry_admin::mint_admin(system, receiver, original_cap, ctx)      // mints a duplicate, hands it over
entry_admin::enrol_operator(system, original_cap, cap_id, until_ms, may_bypass_draft, clock, ctx)
entry_admin::refresh_operator(…)                                  // moves the deadline
entry_admin::retire_operator(system, original_cap, cap_id, ctx)   // cannot abort
```

Authority follows the **slot**, not the wallet. Rotating a key is a transfer of an owned object and
writes nothing on chain: the capability moves from one wallet to another and the slot, the user's
grant and every file's policy are untouched.

Each concurrently-signing wallet needs its own duplicate, because `AdminCap` is an owned object and
the pool runs one transaction per wallet at a time. `operator::MAX_OPERATORS = 16` therefore caps
the signing pool at sixteen. It is a private constant and raising it is upgrade-compatible.

## Three independent gates

A call made on an operator credential passes three checks, granted and revoked by three different
parties. All three must pass; any one of them shuts the door.

| Gate | Checked in | Set by | Revoked by |
|---|---|---|---|
| **The slot** — is this capability enrolled, and unexpired? | `operator::authorise` | the admin, with the original capability | `retire_operator`, or letting `until_ms` lapse |
| **The account** — did this user grant the operator role, with this bit? | `permission::effective_bits` | the account owner | `revoke_operator_role` / `replace_operator_role` |
| **The file** — does this file admit operators, and by which route? | `inner_file::verify_operator` and `write_core` | the file's owner | `set_operator_policy` |

`operator::authorise` also asserts the capability is a **duplicate** (`ENotDuplicateCap`) and names
**this** system (`ECapForAnotherSystem`). The original capability is not an operator and cannot act
as one; that separation is what keeps the root key out of the hot path.

## The file's three bits

`InnerFile` carries the owner's terms for operators. Three booleans spell four states:

| `operators_allowed` | `..._may_bypass_draft` | `operators_may_draft` | Meaning |
|---|---|---|---|
| `false` | — | — | the operator does not write here |
| `true` | `true` | `false` | **direct only** — a queued write aborts |
| `true` | `false` | `true` | **queue only** — a direct write is routed into the queue |
| `true` | `true` | `true` | **either**, the operator picks with `to_draft` |
| `true` | `false` | `false` | **refused** at creation and at `set_operator_policy` |

The last row is refused rather than stored because it means exactly what `operators_allowed: false`
means, and a state with two spellings is one a reader gets wrong.

The third bit exists because two could not say what an owner needed to say. With only the first
two, `allowed: true, bypass: false` did not refuse a direct write — it **silently redirected it into
the draft queue**. So an owner clearing the bypass changed *where* the operator's output went rather
than whether it arrived, and under a rotating credential that output landed in per-wallet custody,
because a queued write takes the sender's custody rather than the owner's.

### How a write is routed

```
to_draft = true   and  operators_may_draft         →  queued
to_draft = true   and  not operators_may_draft     →  abort  EOperatorDraftsRefused
to_draft = false  and  may_bypass                  →  straight into history
to_draft = false  and  not may_bypass, may_draft   →  queued
to_draft = false  and  not may_bypass, no drafts   →  abort  EOperatorSlotCannotBypass
```

`may_bypass` is the **conjunction** of the operator's slot bit and the file's:

```move
let may_bypass = auth.auth_may_bypass_draft() && inner_file.operators_may_bypass_draft();
```

The owner wins. An admin granting bypass on a slot cannot override a file whose owner refused it.

`EOperatorSlotCannotBypass` names a reachable state that is easy to misread as impossible: a file
may legally be direct-only, and an operator whose *slot* carries no bypass then has neither route
open even though the file's own bits look ordinary. The two refusals are named separately because
they need different fixes — one is the owner's policy, the other is a slot to refresh.

## An operator can never mint a writer pass

`SubPermission` has a `create_writer_pass` bit; `grant_operator_role` does not accept it, and no
operator path reaches `check_permission_writer_pass`. Both operator creation calls hardcode
`should_include_pass = false`, and `entry_file_access::create_pass` is owner-only with no sibling.

This is structural, not an omission. A pass is bound to **one address**. The backend rotates keys,
and the whole point of the operator set is that authority follows the capability slot rather than a
wallet. An operator that could mint passes would be manufacturing exactly the single-wallet binding
the model exists to remove — and it would have to re-mint per file per key.

## Operator-created files are born open

`create_file_as_operator` and `initialize_project_file_as_operator` take **no** policy arguments.
The file they create admits its creator on both routes.

`create_inner_file` and `can_init_db` mean *"make me a file you will maintain"*, and one the
operator cannot write to is not what that grant asked for. The owner narrows it afterwards with
`set_operator_policy`, which is the escape hatch rather than the starting point. A call that let the
operator name its own policy would be the one place `operators_allowed`'s stated guarantee — that
the bits are the owner's and nobody else's — was not true.

## Revocation, and which lever actually works

Per-capability revocation is **weak under rotation** and should not be relied on.
`entry_file_access::revoke_pass(file, cap_id)` bans one capability on one file, so banning a backend
from a file that way needs every id in the pool, and does not cover one enrolled tomorrow. It is
still the right shape — the deny list is keyed by `ID` and blind to what an id names, which is what
lets it cover passes and capabilities with one mechanism — but it is not the lever you want.

| To stop | Use | Scope |
|---|---|---|
| all operators on one file | `set_operator_policy(allowed: false)` | one file, credential-blind |
| operator drafts on one file | `set_operator_policy(…, may_draft: false)` | one file |
| all operators on one account | `revoke_operator_role` | the account |
| one bit account-wide | `replace_operator_role` with it false | the account |
| one wallet everywhere | `retire_operator` | the system — cannot abort |
| the whole pool | `retire_operator` per slot | the system |

## The lifecycle nobody automated

Per rotating wallet the admin must `mint_admin` (needs the **original** capability), transfer the
duplicate to the wallet, `enrol_operator` with an `until_ms`, and then **`refresh_operator` before
it expires**. `operator::authorise` aborts `EOperatorExpired` once a slot lapses, taking that wallet
out of service silently from the contract's side.

Nothing schedules the refresh. See [upgrades.md](upgrades.md) section 4 and
[deployment.md](deployment.md).
