# The event stream, for someone building on it

Fifty-three event types across eight modules. This is the orientation; the field-by-field reference
is each package's `docs/events.md`, and `docs/event-schema.json` beside it carries one decoded
example per type.

The short version: **one filter returns everything, removals are announced as well as creations, and
`vector<u8>` arrives base64.** Those three sentences are most of what will otherwise cost you an
afternoon.

---

## One filter, and it is the only one that works

Every event type is declared in a module under `sources/events/`, and nowhere else. Both usable
filters match on the module an event type is **defined** in, so that one rule is what lets a single
subscription return the protocol's whole history — however many domain modules announce into it.

```graphql
{ events(filter: { type: "<PACKAGE-ID>" }) { nodes { contents { json } } } }
```

```
# gRPC, LedgerService.ListEvents
EventFilter { terms { event_type { event_type: "<PACKAGE-ID>" } } }
```

One subscription, one cursor. A consumer that wants a single type narrows to
`<PACKAGE-ID>::storage_events::BlobRenewed`.

This is enforced rather than conventional: `scripts/check-events.sh` refuses any `event::emit`
outside `sources/events/`, and refuses any emitter with no call site. An event declared in a domain
module would still be emitted and still be indexed by a package filter — but it would sit outside the
surface `docs/events.md` describes, so a consumer that had built against that document would silently
miss it.

**`suix_queryEvents` is gone.** JSON-RPC on public fullnodes returns `-32601 Method not found` on
both mainnet and testnet, checked 2026-08-26. Any consumer still on it is not deprecated, it is dead.

### Where the events live

| Module | Types | Covers |
|---|---|---|
| `system_events` | 9 | systems, their fees and tiers, the version, admin capabilities, operator slots |
| `identity_events` | 12 | registration, migration, wallets, both kinds of delegation |
| `storage_events` | 11 | configs, custody, renewal, adoption, compaction receipts, withdrawal |
| `innerfile_events` | 6 | file creation, the operator policy, the head, retirements, the fallback |
| `draft_events` | 3 | proposals pinned, merged and deleted |
| `pass_events` | 5 | writer passes minted, destroyed and revoked; writers denied and undenied |
| `product_events` | 4 | project holders, projects, databases, file-set roots |
| `treasury_events` | 3 | vault deposits, payouts, accepted coin types |

---

## Five things about the payloads

### 1. `vector<u8>` is a base64 string

It does **not** follow the `vector<T>` rule. It comes back as base64 — not an array of numbers, and
not hex. A 32-byte commit of `00112233445566778899aabbccddeeff` twice reads back as
`"ABEiM0RVZneImaq7zN3u/wARIjNEVWZ3iJmqu8zd7v8="`.

This is the encoding that silently breaks a decoder, because base64 of 32 bytes is a plausible-looking
string. It affects every `commit` field, `previous_commit` on `HeadAdvanced`, both root fields on
`ProjectCreated` and `ProjectFileSetRootChanged`, and on `LayoutRegistered` both roots **plus every
element of** `paths` and `content_hashes` — a `vector<vector<u8>>` is a JSON array of base64 strings.
`vector<u16>` and `vector<ID>` are unaffected and are still arrays.

The rest of the table, and the whole encoding note, is recorded in `docs/events.md`, verified against
live Sui mainnet GraphQL on 2026-08-26 and confirmed on a published testnet package across six events
and five transactions. The other one that catches people: **`u64` arrives as a string**, because the
value can exceed 2^53.

If you are recomputing a root to compare against one from the stream, decode first. See
[commitments.md](commitments.md).

### 2. You cannot filter on a payload field

Only sender, module, type and time are matchable. Under delegation the acting `sender` differs from
the record's `owner`, and `owner` is a payload field — so ***"every event for owner X"* cannot be
expressed as a chain-side filter at all.** Read the stream whole and join locally. This is not a gap
to work around; it is why the protocol is designed to be read whole.

### 3. Every removal is announced, not only every creation

Withdrawal, revocation, eviction, user removal, fallback removal and pass destruction all emit. A
consumer that replays from genesis and only ever adds rows reconstructs a state that never existed.

Two places this matters more than it looks:

- **Every `BlobConfig` exit runs through one private `destroy`**, so `BlobWithdrawn` fires however the
  config was consumed — an owner's withdrawal, or a revision leaving a file's rollback window.
- **`RevisionRetired` carries `released`**, which says which of two things happened. `true`: the
  content was handed back and the config destroyed. `false`: the config is still alive because a
  draft's author or the file's own fallback still holds a claim on it. The event exists precisely so
  the party who owns that config can find it and act.

### 4. Two events have more than one cause

- **`BlobConfigOwnershipOfferCancelled`** fires when an owner cancels an offer, *and* whenever custody
  moves at all with an offer standing — because any move of `owner` voids one. A consumer that wants
  to tell them apart reads what accompanies the row in the same transaction: a cancellation stands
  alone, a voiding sits beside a `BlobConfigOwnerChanged`.
- **`OperatorRoleGranted` and `PermissionGranted`** are each emitted by both the grant and the
  replacement, because both leave the delegation holding exactly the bits in the payload. Take the
  latest row as the state; there is no separate "replaced" event.

### 5. Aggregates are the value *after* the change, where the chain still keeps one

`total_draft`, a vault balance, the remaining `cycle_limit` — these are carried post-change. Where the
chain no longer keeps a count at all — the registered-user count, a file's deny count, a user's
adopted-config total — the count is not in the payload either, because a value the chain does not hold
is one the emitter would have had to compute purely to announce it. Accumulate those from the deltas.

Timestamps follow the same rule: an event carries a time field only where that time is itself
on-chain state — a config's `uploaded_on`, a file's `created_at_ms`, a queue's `last_modified`, a
denial's deadline. Everything else takes the transaction's wall clock from the event envelope, which
carries it already.

---

## Five events carry no `system_id`

`WriterPassDestroyed` carries `file_id` and nothing above it: a pass names a file, its holder destroys
it alone, and there is no `SystemConfig` on that path.

The four `product_events` carry `holder_id` instead. Attributing a project to a system means joining
`holder_id` back to its `ProjectHolderCreated` row, and that row's `admin` to a registration.

Everything else names its system, because `mint_system` supports concurrent systems and an event
without one cannot be attributed.

---

## What to subscribe to, by job

### Keeping storage alive

`BlobStored` gives you the working set: it is the **only** announcement of the blob-to-config mapping,
and `config_id` is what renewal addresses — an indexer holding only blob object ids cannot construct a
renewal call from its own records. It also carries `epoch_set`, `cycle_limit` and `end_epoch`, the
earliest expiry across the blobs the config holds, which is the epoch by which it must be renewed.

`BlobWithdrawn` takes rows out. Those two maintain the set.

You do **not** need to track custody to renew. `renew_blob` addresses the config and takes no
capability, no allowlist and no owner check, so a change of `owner` changes nothing about your job —
and a standing offer changes nothing either.

Your own work comes back as `BlobRenewed` per blob extended, `RenewCycleSpent` once per call that did
work, and `RenewSkipped` where it did not, with a reason code: `0` the mandate is spent, `1` the blob
is already paid past the target, `2` its storage has already lapsed. The cycle is charged **after** the
extension and only if at least one blob moved — charging up front would let any address exhaust
another user's mandate for the price of gas.

### Following a file

`InnerFileCreated` opens it, with the window depth, the operator policy and the first commit.
`HeadAdvanced` carries the new head, the one it displaced and the window depth after — and because the
window is newest-first and bounded at `track_back_length`, a FIFO of that depth fed from the stream
alone tells you which config the next overflowing write must pass as `evicted`. `RevisionRetired`
closes each one out.

Then `DraftPinned` / `DraftMerged` / `DraftDeleted` for proposals, `RootChangeSet` / `RootChangeRemoved`
for the fallback, and `FileOperatorPolicySet` for the terms.

### Watching custody

`BlobStored` (the `owner` field, not `stored_by`), then `BlobConfigOwnershipOffered`,
`BlobConfigOwnershipAccepted`, `BlobConfigOwnershipOfferCancelled`, `BlobConfigOwnerChanged` and
`BlobWithdrawn`. Note that `owner` and `stored_by` differ on every delegated write, and that a queued
draft is stored under the **sender**, not the file's owner. See [custody.md](custody.md).

### Reconstructing who may act for whom

This one needs three joins, and one thing the stream cannot tell you.

1. **The slots** — `SystemOperatorEnrolled`, `SystemOperatorRefreshed`, `SystemOperatorRetired`.
2. **The account's grant** — `OperatorRoleGranted`, `OperatorRoleRevoked`, and the address-keyed
   `PermissionGranted` / `PermissionRevoked` beside them. The two are ORed, and neither can be
   subtracted from the other.
3. **The file's terms** — `FileOperatorPolicySet`, plus the three bits on `InnerFileCreated`.

What the stream cannot say is **which wallet holds a slot**. A backend key is a capability *id* with a
slot on the system, not an address; moving the capability to another wallet raises no event, because
nothing on chain changes. Following that means following the capability object itself. See
[operators.md](operators.md).

### Auditing a compaction

`LayoutRegistered` is the whole receipt and it is the one event that has to survive the deletion of
what it describes. The object keeps two 32-byte roots; the event keeps the members they commit to —
every path, every content hash, every superseded config id. That division is what makes the receipt
constant-size on chain and still enumerable afterwards.

The order the caller submitted is the order the root was folded in, so the lists in the payload are
canonical and a consumer recomputing either commitment has nothing left to infer.

---

## What holds the contract together

`scripts/check-events.sh` runs in CI and fails the build when an emitter has no call site, when
`event::emit` appears outside `sources/events/`, when an event module imports anything internal, when
an `assert!` aborts with a bare integer, when `docs/events.md` or `docs/event-schema.json` stops
matching the events the code declares — **field order included**, because a consumer decoding
positionally gets a silently wrong answer from a reordered list rather than an error — or when the two
packages differ.

Beyond that, `tests/support/replay.move` rebuilds an off-chain view from the stream alone and
`tests/regression/rebuild_tests.move` compares it against chain state field by field. The replay
asserts it consumed every event raised in each transaction, so adding an event and not teaching the
replay about it fails the build rather than being silently dropped.

Which is to say: if this document and the stream disagree, that is a bug in CI as well as in the
document.
