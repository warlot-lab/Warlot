# Every bound, and why it is there

A reader planning against this protocol needs these in one place. They are enforced in the module
that owns the thing being bounded, so today they are scattered across eight of them.

Every numeric limit below is a **private constant**, so raising one is an upgrade-compatible change
— see [upgrades.md](upgrades.md). What that does and does not do is at the end.

---

## What one call may carry

| Limit | Value | Where | Abort |
|---|---|---|---|
| Blobs in one adoption | **100** | `entry_upload::MAX_ADOPTION_BATCH` | `EBatchTooLarge` |
| Configs one compaction supersedes | **666** | `id_set::MAX_ID_SET`, checked in `supersede` | `ETooManySuperseded` |
| Files one layout describes | **666** | `layout::max_patches()`, and `file_set::MAX_FILE_SET` on the root | `EFileCountTooLarge`, `EFileSetTooLarge` |
| Path length | **1024 bytes** | `file_set::MAX_PATH_LENGTH` | `EPathTooLong` |

**The adoption batch** is 100 because the blobs live inline on the config the call creates, and
renewal walks all of them inside one transaction — so the bound is what keeps both the object and the
renewal call within reach. It used to bound something quite different: one shared object created and
one event emitted per blob. One config per call is the shape now, and it is not only a saving. A
quilt is a single Walrus blob, so a quilt is adopted as one config and its renewal mandate covers the
whole quilt, which is the only granularity Walrus offers — a patch cannot be extended or deleted on
its own. Blobs adopted together are bound together: one mandate, one withdrawal.

**666 is the Walrus quilt patch cap**, and the three places it appears are one bound wearing three
hats. A layout the chain cannot recompute a root over is a layout the chain cannot attest to, so the
layout's file count and the file-set root's cap have to agree. A compaction never names more
predecessors than a quilt holds patches, so the id-set cap matches too. The bound is also what keeps
the ordering pass affordable: both set constructions sort with an insertion sort, which is quadratic
in the entry count. In practice, for the superseded set, a transaction's limit on shared-object
inputs binds long before 666 does.

---

## What one object may hold

| Limit | Value | Where | Abort |
|---|---|---|---|
| Rollback window depth | **1 to 8** | `inner_file::MAX_TRACK_BACK` | `INVALIDTRACKBACKLENGTH` |
| Open drafts on a file | **`writers_length`**, chosen per file, `u8` | `inner_file::pin_draft` | `EDraftLimitReached` |
| Tier table entries | **1 to 16**, strictly ascending | `system_config::MAX_TIER_COUNT` | `EInvalidTierTable` |
| Top tier, against the horizon | strictly below `max_epochs_ahead` | `system_config::assert_tier_table` | `ETierTableExceedsHorizon` |

**The rollback window is eight** because it is a vector held inline on a shared object: every entry
is re-serialised through consensus on every write, and every entry is a revision whose content is
being paid for. Eight is past the point where a deeper history is worth either cost. The field is a
`u8` and used to accept 255.

**Open drafts are not a package constant.** `writers_length` is set per file at creation and never
changed, so the ceiling is whatever the creator chose, up to 255. A file created with `0` accepts no
draft at all. The cap was declared on the file from the beginning and enforced nowhere, which made
the queue a shared structure any pass holder could grow without limit; `pin_draft` is where it
became real.

**The tier table** is bounded at 16 for the same reason the operator set is: it lives inline on a
shared object and is scanned on every registration. It must be non-empty and strictly ascending so
that "the top tier" is unambiguous.

**The horizon rule** is the one bound that is not about cost. The longest term registers one epoch
above itself and is renewed back down to it, so that a blob on the term where the most valuable data
lives always has one epoch of extension left — Walrus refuses to extend past the horizon, and a blob
already sitting on it has nowhere to go if a renewal cycle fails or a wallet runs dry. Shorter terms
need no such margin. The defaults are `[1, 2, 7, 13, 20, 26, 52]` epochs against a horizon of 53:
by nearest epoch on a two-week mainnet epoch, roughly two weeks, one month, three months, six
months, nine months, a year and two years.

---

## What one system may hold

| Limit | Value | Where | Abort |
|---|---|---|---|
| Operator slots | **16** | `operator::MAX_OPERATORS` | `EOperatorSetFull` |
| Successors | **1** | `SystemMintCap.next_system`, an `option::fill` | `ESuccessorAlreadyMinted` |

**Sixteen operator slots caps the signing pool at sixteen wallets.** Each concurrently-signing wallet
needs its own duplicate capability, because `AdminCap` is an owned object and the pool runs one
transaction per wallet at a time. The set lives inline on a shared object and is scanned on every
delegated call, so it is bounded for the same reason the tier table is; sixteen is far past the size
of any real signing pool and keeps the scan free.

**One successor** is what keeps system minting linear, so "the next system" is always a single
answer and the chain never forks.

---

## Widths and formats

| | Value | Where |
|---|---|---|
| A commit | exactly **32 bytes** | `commit::ROOT_LENGTH`, `assert_valid_root` |
| A file-set root, and a content hash | exactly **32 bytes** | `file_set::ROOT_LENGTH` |
| An id-set root | exactly **32 bytes** | `id_set::ROOT_LENGTH` |
| A `Layout` | **95 bytes** in BCS, at any file count | measured in `layout_tests.move` |
| The package version | **1** | `version::VERSION` |

A commit is a hash and therefore constant-sized. The concatenation it replaced grew with the number
of operations and eventually exceeded the maximum size of a Sui object — at which point the commit
that would have drained the backlog could no longer be executed.

The `Layout` is constant in the file count by construction, and that is the point rather than a
coincidence: a per-file record would exceed Sui's maximum object size at roughly five thousand files,
and this one is the same 95 bytes at one file and at 666. See [commitments.md](commitments.md).

---

## Time bounds

None of these is a duration the contract picks. Each is a deadline the caller supplies, with one
rule about it.

| | Rule | Abort |
|---|---|---|
| An operator slot's `until_ms` | strictly in the future. **No maximum** | `EInvalidOperatorExpiry` |
| A delegated pass minted at file creation | strictly in the future | `EInvalidPassDuration` |
| A pass minted by `create_pass` | **unchecked** — and `0` is the sentinel for a pass the system does not decay | — |
| A denial's period | `0` denies indefinitely; anything else must be in the future | `INVALIDTIME` |

The asymmetry between the two pass routes is deliberate on the creation side and simply absent on the
other. A delegate acting on someone else's behalf during file creation is given authority with an end
date, and the future check is also what keeps the value away from the non-decaying sentinel. An owner
calling `create_pass` on their own file is choosing for themselves, and may pass `0`.

`Registry.decay_at` is set to 10,000,000,000 ms — about 116 days — past creation and is **read by
nothing**. No entry point moves it and no check consults it.

---

## What is deliberately not bounded

Knowing where a bound is not is as useful as knowing where one is.

| | What bounds it instead |
|---|---|
| Operations in one `commit::root` | the transaction carrying them. The chain never computes a commit — it checks the width of the one it is given |
| Blobs on a config after creation | nothing changes it; `blobs` is fixed when the config is built |
| Configs one account owns | nothing. There is no per-user total on chain, by design |
| Duplicate `AdminCap`s minted | nothing. Only sixteen may hold a **slot** at once |
| Projects under one holder | nothing — each is one dynamic field entry |
| Denials or revoked ids on a file | nothing — each is one dynamic field entry |
| Configs in one `self_withdraw_blobs` | the transaction's shared-object input limit. The batch call saves per-call overhead and lifts no ceiling |
| Draft indices ever issued | nothing — `available_index` only moves forward, including across deletions, so an index used once never names a different draft later |
| Coin types in a vault or a wallet | nothing — one dynamic field per type name |
| Renewal cycles on a config | the caller's `cycle_end`. A mandate of `0` can never do work; the `Option` supports an indefinite mandate and **no entry point creates one** |

The absent per-user counters are a deliberate refusal, not an oversight: totals no contract reads
belong in a database, and putting them on chain would mean paying consensus for them and keeping them
consistent for ever. See [refusals.md](refusals.md).

---

## Raising one

Every constant above is private, so an upgrade may change any of them. What that buys differs:

- **`MAX_OPERATORS`, `MAX_ADOPTION_BATCH`, `MAX_TIER_COUNT`** — raising these takes effect
  immediately, on every system.
- **`MAX_TRACK_BACK`** — raising it lets *new* files ask for a deeper window. It does not deepen an
  existing file: `track_back_length` is a stored field, fixed at creation, and a struct field cannot
  be changed by an upgrade either.
- **`MAX_FILE_SET`, `MAX_ID_SET`, `MAX_PATH_LENGTH`** — raising these changes what the chain will
  accept and **changes no root already computed**. The constructions themselves are frozen; see
  [commitments.md](commitments.md). Raising the first two also makes the quadratic sort more
  expensive, which is what pins them where they are.
- **`ROOT_LENGTH`** — not a knob. Changing it would change all three constructions, and every root
  already on chain would be a different shape from every root computed after.
- **`writers_length`** is not a constant at all. It is a per-file field, so it is neither raisable by
  upgrade nor changeable on a file that exists.
