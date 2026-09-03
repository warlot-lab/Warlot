# The objects

The spine of the protocol. Fourteen stored types, four values that are never stored, and one rule
that decides the shape of almost all of it.

---

## The rule: custody is a field

**Almost nothing here is owned by Sui.** `SystemConfig`, `BlobConfig`, `InnerFile` and
`ProjectHolder` are all shared objects carrying an `owner` or `admin` **field** that is the real
authority.

The reason is mechanical and worth stating once. An owned object can only enter a transaction its
owner signed, and one transaction cannot take two different addresses' owned objects. An owned
`ProjectHolder` could therefore never appear in a delegate's or an operator's transaction at all —
which is the entire surface built on top of it. Sui ownership would have made delegation impossible.

The exceptions are the three credentials and the label:

| Sui-owned | Why |
|---|---|
| `AdminCap` | holding one **is** the authority; it is presented, not addressed |
| `WriterPass` | the same, per file — and a pass in a delegate's account cannot be reached by the file's owner, which is why revocation is a record kept on the **file** rather than a destruction of the pass |
| `Registry` | the user's own label, mutated only by them |

`Registry`, `BlobConfig` and `WriterPass` carry `key` without `store`, so none of them can be
wrapped inside another object or handed on with `public_transfer`. A `BlobConfig` is created, shared
once, and consumed by `unwrap`; nothing can take it out of the shared pool.

---

## What is attached to what

This protocol attaches almost everything on first use. A registration creates three objects — the
`User`, the `Wallet` inline on it, and the `Registry` handed to the sender — and every container below
arrives with the call that first puts something in it. An account that never uses one never pays for
it.

```
SystemConfig                                                              shared
├─ "system_vault"      → Vault                     dyn. object field    at mint
│  ├─ accepted_coins: Table<String, bool>          inline
│  └─ <coin type name> → Balance<T>                dyn. field           first deposit of that type
└─ <owner address>     → User                      dyn. object field    at registration
   ├─ wallet: Wallet                               inline               at registration
   │  └─ "wallet_bank" → Bank                      dyn. object field    first deposit
   │     └─ <coin type name> → Balance<T>          dyn. field           first of that type
   ├─ "acceptance key" → Table<address, SubPermission>
   │                                               dyn. object field    first address grant
   ├─ "operator role" → SubPermission              dyn. field           when the role is granted
   └─ "project holder" → ID                        dyn. field           when a holder is opened

InnerFile                                                                 shared
├─ "deny list"         → DenyList                  dyn. object field    first denial or revocation
│  ├─ <writer address> → u64                       dyn. field           one per denial
│  └─ <credential id>  → bool                      dyn. field           one per revoked id
└─ "file draft"        → FileDraftHolder           dyn. object field    first draft
   └─ <index: u64>     → Draft                     dyn. object field    one per open draft

ProjectHolder                                                             shared
└─ <project id>        → Project                   dyn. field           one per project

BlobConfig             standalone, shared          nothing attaches to it, it attaches to nothing
AdminCap               standalone, Sui-owned
WriterPass             standalone, Sui-owned
Registry               standalone, Sui-owned
```

The keys are the literal byte strings above. `dynamic_object_field` and `dynamic_field` look in
different key spaces, so a record attached with one has to be detached with the other's counterpart
— which is why `user::remove_user` says so in a comment.

Two things the tree makes visible that a flat list does not:

- **A `BlobConfig` hangs off nothing.** It names no system, no file and no project. That is why a
  package upgrade, a system migration and the loss of an account record all leave stored content
  untouched, and why renewal can address a config without resolving anything else.
- **`SystemConfig` is the root of the account surface and nothing else.** Files, configs and project
  holders are all reachable on their own ids.

---

## Nothing here can be destroyed, with five exceptions

Worth knowing before reading any individual entry. Most of these types have no destructor at all —
not a restricted one, none.

| Type | Destroyed by | |
|---|---|---|
| `BlobConfig` | `blob_config::destroy`, reached by `unwrap` (owner-only withdrawal) and `unwrap_for_owner` (a revision leaving the rollback window) | the only content exit |
| `Draft` | `resolve_draft_to_file`, `delete_draft` | merged or rejected |
| `FileData` | `file_data::destroy` | has no `drop`; see below |
| `WriterPass` | `destroy_writer_pass`, by its holder alone | |
| an operator slot | `operator::remove` | a `VecMap` entry, not an object |
| **everything else** | — | `SystemConfig`, `Vault`, `AdminCap`, `Registry`, `User`, `Wallet`, `Bank`, `InnerFile`, `DenyList`, `FileDraftHolder`, `ProjectHolder`, `Project`, and every delegation row |

`FileData` deliberately has no `drop`. A revision names a `BlobConfig` holding paid-for content, so
a revision that fell out of scope unnoticed was content nobody could reach and the renewal service
kept paying for. Unpacking it is the only way to be rid of it, and `file_data::destroy` yields the
config id — so whoever retires a revision cannot do so without holding the name of what it leaves
behind.

---

# The system

## `SystemConfig`

**What it is.** One deployment of the protocol: its version gate, its fee schedule, the storage
terms it sells, the capabilities it accepts as backend credentials, its treasury, and every account
registered with it.

**Ownership.** Shared — `public_share_object` at `init`, and again for each successor
`mint_system` builds. It has to be: every user's record hangs off it, so any account's call touches
it. Authority is the `AdminCap` naming its id, checked by `assert_original_cap_for`.

**Inside it**

| Field | For |
|---|---|
| `operators: OperatorSet` | a `VecMap<ID, Operator>` of the capability ids this system accepts, at most 16. Keyed by **id**, so rotating a backend key is a transfer of an owned object and writes nothing here |
| `version: u64` | the upgrade gate. Born at the package version; raised only by `migrate_version` |
| `mint_cap: SystemMintCap` | `previous_system: ID` and `next_system: Option<ID>`. `option::fill` on the second is what makes the chain linear — a second `mint_system` aborts |
| `user_modification_cfg: UserMdCfg` | four fees. Only two are charged by any path: `cost_to_update_name` by `update_username`, `cost_to_migrate_system` by `migrate_system`. `cost_change_apikey_forms` and `cost_to_delete` are settable and readable and no entry point reads either |
| `tier_table: vector<u32>` | the storage terms on sale, strictly ascending, 1 to 16 entries. Default `[1, 2, 7, 13, 20, 26, 52]` |
| `max_epochs_ahead: u32` | the storage horizon. The top tier must sit strictly below it, so a blob on the longest term always has one epoch of extension left. Default 53 |

**Lifecycle.** Created by `init` — once per publish — and by `mint_system`. **No destructor.** A
system that has been superseded stays on chain and stays usable by anyone who has not migrated.

**Attached.** The vault at creation; one `User` per registration, keyed by the registrant's address,
and never removed except by `migrate_system` moving it to the successor.

**Acted on by.** All twelve `entry_admin` calls, on the **original** capability for this system.
Both registration calls and `migrate_system` add or remove a `User`. Every other entry point that
takes it reads it and asserts its version.

**Events.** `SystemCreated`, `SystemSucceeded`, `SystemFeesChanged`, `SystemTiersChanged`,
`SystemVersionMigrated`, `SystemOperatorEnrolled`, `SystemOperatorRefreshed`,
`SystemOperatorRetired`; `UserJoinedSystem` and `UserLeftSystem` as accounts arrive and leave.

## `Vault`

**What it is.** The protocol treasury, holding many coin types at once — one dynamic field per type
name, so it is not generic over `T`.

**Ownership.** A dynamic object field of `SystemConfig` under `b"system_vault"`, and every route to it
in the package goes through the system: `get_vault_mut` is `public(package)` and takes a
`&mut SystemConfig`, and `get_system_balance<T>` takes a `&SystemConfig`. It carries `system: ID`
anyway, and every payout is authorised against that field — the vault does not depend on being
unreachable to be safe.

**Inside it.** `accepted_coins: Table<String, bool>` — the deposit allowlist, keyed by the fully
qualified type name. Balances live beside it as dynamic fields under the same key.

**Lifecycle.** Built by `system_config::new` and attached in the same call, already accepting WAL —
through `support_coin_on_creation`, which exists because the system's original capability does not
exist yet at that point. **No destructor.**

**What it refuses.** A deposit of a type not on the list (`EInvalidCoin`). Withdrawal does **not**
consult the list, so removing a type stops new deposits and leaves the balance already held
withdrawable; it aborts `ENoBalanceFound` when the vault holds none of that type and
`EInsufficientBalance` when it holds less than asked.

**Events.** `VaultDeposited`, `SystemWithdraw`, `VaultCoinSupportChanged`. Every payout is announced
from inside `vault::withdraw`, so a route added later cannot take value out without saying so.

## `AdminCap`

**What it is.** The capability that administers one system. It carries a **state tag** — original or
duplicate — and that one byte carries the whole operator model.

**Ownership.** Sui-owned. Holding it is the authority, and it is transferred only through
`admin_cap::transfer_to`, which announces the mint together with its holder: a capability nobody
holds is not authority over anything.

**Inside it.** `system_config_id: ID` — the system it names, checked everywhere. `state: u8` — `0`
original, `1` duplicate. `total_system: u8` — how many successors have been minted through it;
incremented by `mint_system` and read by nothing that gates.

**The boundary.**

|  | Original | Duplicate |
|---|---|---|
| Every `entry_admin` call | ✅ `assert_original_cap_for` | ❌ `ENotOriginalCap` |
| Every `vault` mutation | ✅ `vault::assert_operator` | ❌ `ENotOriginalCap` |
| An operator credential | ❌ `ENotDuplicateCap` | ✅ `operator::authorise` |

The two halves are exact complements, and that is the point: the credential a backend signs with
cannot reach the treasury, mint a system or change a cost, and the root key is not an operator and
cannot act as one. That is what keeps the root out of the hot path.

**Lifecycle.** One original per system — at `init`, and one minted alongside each successor by
`mint_system`. Duplicates by `mint_admin`, unbounded in number; only sixteen may hold a slot at
once. **No destructor.** A capability cannot be burned; a duplicate is neutralised by
`retire_operator` dropping its slot, and the original by nothing at all.

**Events.** `AdminCapMinted`, from `transfer_to`, carrying the state tag and the receiver.

---

# The account

## `Registry`

**What it is.** The user's own label and the pointer that says which system they belong to. It is
the only thing in the protocol a user holds in their own account.

**Ownership.** Sui-owned, `key` without `store` — it cannot be wrapped, and only its holder can pass
it to a transaction.

**Inside it.** `user: address` and `public_username: String`; `system_details: SystemDetail`, holding
`user_object_id` and `system_id`; `created_at`, `updated_at`; and `decay_at`, set to
`API_DECAY` (10,000,000,000 ms ≈ 116 days) past creation. **`decay_at` is written and never read.**
Nothing in `sources/` gates on it and no entry point moves it.

**Lifecycle.** Created inside `user::create_user` and transferred to the sender. **No destructor** —
a registry cannot be deleted, which is half of why user deletion is open work rather than a hidden
feature.

**Acted on by.** `update_username` — for a fee, and only against the system it names
(`ERegistryForAnotherSystem`). `migrate_system` — repointed at the successor.

**Events.** `UserRegistered`, `UsernameUpdated`, `RegistryMigrated`.

## `User`

**What it is.** Everything the protocol knows about one account on one system: its balances, and
every delegation it has made.

**Ownership.** A dynamic object field of `SystemConfig`, keyed by the account's **address**. The
field's existence *is* membership — `check_user` reads it directly, and there is no list or index
maintained beside it.

**Inside it.** `owner: address`, and `wallet: Wallet` as an inline field. Everything else is
attached.

**What is attached, and when**

| Key | Holds | Arrives with |
|---|---|---|
| `b"acceptance key"` | `Table<address, SubPermission>` | the account's first address grant |
| `b"operator role"` | `SubPermission` | `grant_operator_role`, or a registration through `all_register_user_with_system_permission` |
| `b"project holder"` | `ID` | `open_project_holder`, either form |

An account acting only on itself consults no table: every `check_permission_*` returns immediately
when `ctx.sender() == owner`. So a user who has never delegated anything holds no delegation table
at all and pays nothing for the possibility.

The project-holder entry is a **marker, not the holder**. The holder is a shared object standing on
its own — putting it here would route every project write through `SystemConfig` and serialise it
against registration, wallet operations and every permission change. What the marker buys is
uniqueness: the holder is created lazily, and without it nothing would stop an account minting a
second one and splitting its projects across two roots nobody can reconcile.

**Lifecycle.** Created by `create_user` at registration, added by `add_user`, and moved between
systems by `migrate_system`. `remove_user` exists but is `public(package)` and `migrate_system` is
its only caller, so a `User` is never destroyed — only re-parented.

**Acted on by.** All six `entry_permission` calls, each gated on `user_obj.owner() == ctx.sender()`
(`ENotAccountOwner`) — a delegation is the account's to give, and nothing else can give it. All
three `entry_wallet` calls, reached by the sender's own address. `open_project_holder` and its
operator sibling, which write the marker.

**Events.** `UserRegistered`, `UserJoinedSystem`, `UserLeftSystem`, `PermissionGranted`,
`PermissionRevoked`, `OperatorRoleGranted`, `OperatorRoleRevoked`.

## `Wallet` and `Bank`

**What they are.** The account's internal balances. `Wallet` is the handle; `Bank` is the container
the balances actually live in, one dynamic field per coin type.

**Ownership.** `Wallet` is an inline field of `User`, so it exists from registration and is reached
only through the user record keyed by `ctx.sender()`. **That lookup is the authorisation**: no
address can name another's wallet, and no entry point takes an owner argument.

**Lifecycle.** The wallet is created with the account. The bank is attached on the **first deposit**
— it is a dynamic object field, two objects counting the field entry, and an account that has never
funded its wallet holds no balance for it to keep. Neither has a destructor. A read against a wallet
with no bank answers zero rather than aborting; a withdrawal against one aborts `ENoBalance`.

**What it holds.** `owner: address` and `created_at: u64` on the wallet; `Balance<T>` per coin type
under the bank. `entry_wallet` exposes WAL only — `deposit_coin` takes a `Coin<WAL>` and the two
withdrawals are `withdraw<WAL>` and `withdraw_all<WAL>` — so although the storage is multi-coin, WAL
is the only type an entry point can move.

**Events.** `WalletCreated`, `WalletDeposited`, `WalletWithdrawn` — each carrying the coin type name,
because a wallet holds many types under one object and an untyped amount would sum balances of
different things into one meaningless number.

## `SubPermission`

**What it is.** Six booleans: `add_blob_to_address`, `create_inner_file`, `create_writer_pass`,
`can_init_db`, `can_compact`, `can_set_root`. Not an object — a `store` value used in two places.

**Where it lives.** Keyed by address in the delegation table, it is a grant to one named key.
Attached alone under `b"operator role"`, it is the same set of bits granted to whichever capability
holds a live slot at the moment of the call. Both are read by `effective_bits`, which **ORs** them;
neither being absent is an error.

**The asymmetry.** The operator row can never carry `create_writer_pass`. `create_operator_role_state`
takes five parameters and writes `false` into the sixth, and `grant_operator_role` has no such
parameter — so no signature in the package can express the grant. See
[permissions.md](permissions.md) and [operators.md](operators.md).

**Lifecycle.** A row is added by a grant and **removed** by a revoke rather than zeroed, so a revoked
delegate is refused by the lookup itself and no row survives that could be mistaken for a
delegation. The table itself is never removed once attached.

---

# Storage

## `BlobConfig`

**What it is.** The wrapper around one or more Walrus blobs that names who may withdraw them and
tells the renewal system how to keep them alive. It is the protocol's unit of custody, of renewal
and of deletion, and it is the only object that holds anything a user would call their data.

**Ownership.** Shared, and `key` without `store`. Shared because renewal is permissionless and an
owned object can only enter a transaction its owner signed. `key` alone because a config must never
be wrapped inside another object or transferred out of the shared pool: it is created, shared once,
and consumed by `unwrap`.

Custody is therefore the `owner` **field**. Anyone may pass a config to renewal; only `owner` may
pass it to withdrawal. Moving custody is a write, not a transfer, and the config stays reachable by
everybody throughout.

**Inside it**

| Field | For |
|---|---|
| `owner: address` | who pays to keep the content alive and who may withdraw it. The only authorisation this object needs |
| `pending_owner: Option<address>` | who may **take** custody, once they ask for it. `none` until offered, which costs a config that is never handed on one byte |
| `blobs: vector<Blob>` | the content. Fixed at creation — nothing adds to or removes from it |
| `epoch_set: u32` | how many epochs ahead the blobs are kept paid for. A sustained target, not a one-off purchase: each renewal tops them back up to `current_epoch + epoch_set` |
| `cycle_limit: Option<u64>` | how many renewal cycles remain. `none` means indefinite — and **no path creates one**: `raw_store_blob` is the sole constructor's only caller and always passes `some` |
| `layout: Option<Layout>` | the compaction receipt. `none` on every config an ordinary upload creates, filled once and never again |

**Lifecycle.** Created by `store::raw_store_blob` — the single constructor call site in the package,
which is what makes "every config's owner is a registered account" an invariant with exactly one
place it could be established. Destroyed by `blob_config::destroy`, reached two ways: `unwrap`, which
asserts the sender is the owner, and `unwrap_for_owner`, which does not and hands the blobs back to
whoever owns it — because a revision leaving a file's rollback window is retired by whoever wrote
the revision that displaced it. Both routes announce `BlobWithdrawn`, so a consumer replaying the
stream sees the row disappear however the config was consumed.

**Custody moves two ways, and they are different acts.** Offer and accept is a negotiated handover
between users; a draft merge is a unilateral re-parent by the file's owner over content already
pinned to their own file. Both run through `transfer_ownership`, and **any** move of `owner` voids a
standing offer and announces `BlobConfigOwnershipOfferCancelled` — which is what makes the direct
re-parent safe. See [custody.md](custody.md).

**Who may act on it**

| | Call | Gate |
|---|---|---|
| renew | `renew_blob` | **nobody** — anyone may call it |
| offer / cancel | `offer`, `cancel` | sender is `owner` |
| accept | `accept` | sender is `pending_owner`, and registered |
| withdraw | `self_withdraw_blob`, `self_withdraw_blobs` | sender is `owner`, per config |
| compact | `register_layout[_as_operator]` | `can_compact` on `owner` |
| retire | eviction inside a write, merge or fallback change | the write's own gate |

**Bounded by.** 100 blobs per adoption; the storage term must be one the system sells.

**Events.** `BlobStored`, `BlobConfigOwnershipOffered`, `BlobConfigOwnershipAccepted`,
`BlobConfigOwnershipOfferCancelled`, `BlobConfigOwnerChanged`, `BlobRenewed`, `RenewCycleSpent`,
`RenewSkipped`, `LayoutRegistered`, `BlobWithdrawn`; `ForeignBlobsAdopted` when the content came
from outside the protocol.

## `Layout`

**What it is.** The receipt a compaction leaves on the config it produced: what the new layout
holds, and what it replaces. Two 32-byte Merkle roots and four scalars.

**Why it is a field and not an object.** `copy, drop, store` and no `key`. Unlike a `FileData` it
names no content that has to be accounted for — the content is the config's own blobs — so it is
safe to let it fall out of scope with the config it belongs to.

**Why it exists at all.** The receipt has to outlive the data it describes. A quilt's index and its
per-patch tags live *inside* the quilt, so deleting generation N destroys the record of what
generation N contained — and deleting generation N is the whole point of compacting into N+1. It is
constant in the file count by construction: a per-file record would exceed Sui's maximum object size
at roughly five thousand files, and this one is the same size at one file and at 666.

**Inside it.** `kind: u8` (`0` raw blobs, `1` a quilt — and a quilt is checked against the custody
rather than believed, since a quilt is one Walrus blob however many patches it carries);
`generation: u32`, strictly greater than every generation superseded; `file_count`;
`file_set_root`, over this layout's `(path, content_hash)` pairs; `superseded_root`, over the config
ids replaced, 32 zero bytes when it replaces nothing; `superseded_count`; `created_at_ms`.

**Write-once.** `set_layout` refuses a config that already carries one (`ELayoutAlreadyRegistered`).
The layout is what a holder of superseded content checks before deleting it, so a layout that could
be replaced would be a receipt Warlot could rewrite after the fact. A new generation is a new config.

Both roots are derived by `compaction::register` from state the contract read — never taken from an
argument — which is what makes this a receipt rather than a claim. See
[commitments.md](commitments.md).

## `CompactionPlan`

**What it is.** A compaction being assembled. It has **no abilities at all** — not `store`, not
`copy`, not `drop` — so the only way a transaction can finish holding one is not to finish.

That is the whole design. A compaction has to *read* every predecessor to refuse a cross-user or
mixed-policy one, and Move has no vector of mutable references; the two alternative shapes are both
refused deliberately. Accumulating predecessors across transactions would be pending state that has
to be forgeable to be useful. Taking the predecessors by value would let a compaction retire content
whose owner never released it. So the plan carries them between calls inside one transaction, and
nothing pending is ever left on chain.

**Inside it.** `target: ID`, `owner`, `epoch_set`, `cycle_limit` — all read off the target config by
`plan`, never asserted by the caller — plus `generation_floor`, raised as predecessors are named, and
`superseded: vector<ID>`.

**Lifecycle.** Opened by `plan_compaction`, narrowed by `supersede`, consumed by `register_layout`
or its operator sibling. It cannot be stored and cannot be dropped; a transaction that opens one and
does not register it does not commit.

---

# The file

## `InnerFile`

**What it is.** A collaboratively edited document anchored on immutable storage: its authoritative
head, a bounded rollback window behind it, a known-good fallback beside it, and its owner's terms for
system operators.

**Ownership.** Shared. A file has an owner, writer-pass holders and operators, and only a shared
object appears in all three's transactions. `InnerFile.owner` is the authority, not Sui ownership.

**Inside it**

| Field | For |
|---|---|
| `owner: address` | the address that may merge drafts, set the fallback, mint passes and set the terms below |
| `writers_length: u8` | how many drafts may stand open at once. Enforced at `pin_draft`; a file created with `0` accepts none |
| `operators_allowed` | whether an operator credential may write this file at all |
| `operators_may_bypass_draft` | whether an operator's write may go straight into history |
| `operators_may_draft` | whether an operator's write may be proposed into the queue |
| `draft_epoch_duration: u32` | how many epochs a draft lives for. Held here as well as on the queue, because the queue is built on the first draft and the terms have to survive until then |
| `file_history: FileTrack` | the head, the window, the fallback and the storage terms |
| `created_at_ms` | |

`FileTrack` holds `root_change: Option<FileData>` — the fallback; `track_back_length: u8`, the window
depth, 1 to 8; `warlot_state: WarlotState`, the `epoch_set` and `cycle_end` every revision of this
file is stored under; `track_back: vector<FileData>`, **newest first**; and `last_modified`.

**The three operator bits spell four states.** They are the file owner's terms and are gated on the
**sender**, never on a pass — a pass that could flip them would let an operator that had been shut
out re-admit itself. The fifth spelling, admitting operators while opening neither route, is refused
at creation and at `set_operator_policy` rather than stored, because it means exactly what
`operators_allowed: false` means and a state with two spellings is one a reader gets wrong. The
matrix is in [entry-points.md](entry-points.md#entry_file_write--one-routing-decision).

**Lifecycle.** Created by `creation::new_file`, reached from `create_file`, `create_file_as_operator`,
`initialize_project_file` and its operator sibling — always with a first revision already stored, so
a file never exists without content. **No destructor**, and an `InnerFile` cannot be transferred:
its custody is `owner` plus every config in the window plus the fallback, each a separate shared
object, and moving them together runs into the transaction's shared-object input limit. Deferred
deliberately; see [refusals.md](refusals.md).

**What is attached, and when.** The deny list on the first denial or pass revocation; the draft queue
on the first draft. Both are dynamic object fields — two objects each, counting the field entry — and
most files never deny anybody and never take a draft. A file with no deny list refuses nobody, and
every read asks `attached` first.

**Who may act on it**

| | Calls | Gate |
|---|---|---|
| write into history | `force_write_innerfile` | sender is `owner`, holding any valid pass for this file |
| | `write_` with `to_draft: false` | a pass carrying `admin_privilege` |
| | `write_as_operator` with `to_draft: false` | the slot's bypass **and** the file's, plus `add_blob_to_address` on the owner |
| propose | `write_`, `write_as_operator` with `to_draft: true` | a valid pass; for an operator, `operators_may_draft` |
| resolve | `merge_draft_into_file`, `delete_draft`, `clear_drafts` | sender is `owner`, holding a valid pass. No operator siblings |
| fallback | `set_root_change`, `remove_root_change` | the same |
| terms | the seven `entry_file_access` calls | sender is `owner`. No operator siblings |

**Bounded by.** The window at 8 revisions; open drafts at `writers_length`; a commit at exactly 32
bytes.

**Events.** `InnerFileCreated`, `FileOperatorPolicySet`, `HeadAdvanced`, `RevisionRetired`,
`RootChangeSet`, `RootChangeRemoved`, plus the draft and pass events of the objects attached to it.

## `FileData`

**What it is.** One revision: `commit` (exactly 32 bytes, checked at construction), `commit_by` — the
address that made the change — and `blob_config_id`, the config holding the content.

`commit_by` and the config's `owner` differ on every delegated write, and that is the point: the
author is recorded, the payer is the config's field.

**Ownership.** A `store` value, never an object. It lives in three places: index 0 of `track_back` is
the head, indices 1..n are the rollback window, and `root_change` is the fallback. A `Draft` holds
one too, in `Option`.

**No `drop`** — see the note under the destruction table above.

## `WriterPass`

**What it is.** Authority to write to one named file. Not an account-level bit: the six bits in
`SubPermission` are about an account, and a pass is about a file.

**Ownership.** Sui-owned, `key` without `store`, transferred only through `writer_pass::transfer_to`,
which announces the mint together with its holder.

**Inside it.** `file_id: ID` — the one file it authorises, checked by `verify_pass` (`INVALIDPASS`);
`duration: u64` — the timestamp past which it has decayed, with **zero as the sentinel for a pass
the system does not decay**; `admin_privilege: bool` — whether it may write straight into history
rather than into the draft queue.

**How it is minted.**

| Route | Duration | Privilege |
|---|---|---|
| the owner's own pass, on every file creation | non-decaying | yes |
| the creator's pass, when `should_include_pass` and the creator is not the owner | `pass_duration`, asserted **strictly in the future** | yes |
| `entry_file_access::create_pass` | whatever the owner passes — and `0` mints a non-decaying pass | the owner's choice |

The two are not the same rule. The creation branch refuses a duration that is not in the future, which
also keeps it away from the non-decaying sentinel: a delegate acting on someone else's behalf is
given authority with an end date. `create_pass` applies no such check, so an owner deliberately
minting a permanent pass can do so by passing `0`.

An **admin** pass through `create_pass` is refused unless the recipient may already store blobs under
the file's owner (`ENoAddBlobGrant`) — the store underneath such a write checks `add_blob` as well, so
a pass without it is one that fails at its first use and says nothing about why at the mint. It is a
refusal and never an auto-grant: grant `add_blob`, then mint the pass. A **draft-only** pass is
refused nothing, because a queued write stores under the sender's own address.

**Lifecycle.** Destroyed only by its holder, through `destroy_writer_pass` — the one announcement in
the protocol of authority ending by the holder's own hand. The file's owner cannot reach it: it lives
in the delegate's account, which is exactly why revocation is a record kept on the file.

**Revoked by.** `revoke_pass` and `revoke_passes`, which record the pass's **id** on the file's deny
list. There is no unrevoke.

**Events.** `WriterPassMinted`, `WriterPassDestroyed`, `WriterPassRevoked`.

## `DenyList`

**What it is.** Two revocations sharing one object. Denying a **writer** refuses an address whatever
credential it presents; revoking a **pass** refuses one credential whoever presents it.

**Ownership.** A dynamic object field of `InnerFile` under `b"deny list"`, attached on the first
denial or revocation. Only the three calls that *record* something reach for the attaching accessor —
lifting a denial that was never made does not, so a file cannot be given a deny list by somebody
asking it to forget one.

**Inside it.** Nothing. The object carries no fields of its own: the denials **are** the dynamic
fields. `<address> → u64` is a denial with its deadline in ms, where **zero denies indefinitely**;
`<ID> → bool` is a revoked credential id. The two key spaces do not collide. A consumer that wants a
count counts the `WriterDenied` and `WriterUndenied` events.

**Keyed by `ID`, blind to what the id names.** That is what lets one mechanism cover both a writer
pass and an operator's admin capability — `verify_pass` and `verify_operator` read the same record
the same way. It is also how a file's owner refuses one operator's capability on one file without
waiting for the admin to retire its slot everywhere.

**Lifecycle.** Attached once, never removed. **No destructor.**

**Acted on by.** `deny_writer` (refuses a writer already denied), `redeny_writer` (moves a deadline,
refuses a writer holding none, and refuses a file with no list at all), `remove_deny_writer` (passes
silently on a file with no list — it denies nobody), `revoke_pass` and `revoke_passes` (an id already
refused is passed over, so resubmitting a list is not an error). All five are owner-only.

**Events.** `WriterDenied`, `WriterUndenied`, `WriterPassRevoked`.

## `FileDraftHolder` and `Draft`

**What they are.** The queue of proposed revisions awaiting the owner's merge, and one proposal.

**Ownership.** The holder is a dynamic object field of `InnerFile` under `b"file draft"`, attached by
the first draft. Each `Draft` is a dynamic object field of the holder, keyed by a `u64` index.

**Inside the holder.** `draft_epoch_duration`, `last_modified`, `total_draft` — the number standing
open, checked against the file's `writers_length` — and `available_index`, the next index to assign.

**Indices only move forward**, including across deletions, so an index used once never names a
different draft later. `merge_latest` takes `available_index - 1`: the highest index ever assigned,
not the highest still present, so it aborts rather than reaching further back if that draft has
already been resolved. Guessing on the caller's behalf would merge content nobody asked for.

**Inside a draft.** `issue: Option<ID>` — an opaque reference to whatever the draft resolves, recorded
because it is part of what the owner agreed to when merging; nothing on chain interprets it. And
`file: Option<FileData>`, the revision proposed.

**A draft records no credential.** The id of the pass or capability behind it is carried by
`DraftPinned` instead, together with a `credential_kind` discriminant — `0` a pass, `1` an operator
capability. An id on its own cannot be resolved to a type by anything on chain, and the variant set
of an enum a published module declares cannot be widened by a later upgrade, so the discriminant
belongs in the payload rather than in stored state.

**Custody is the thing to know.** A queued write's blobs are custodied by **the writer who pushed
it**, not by the file's owner: a draft is a proposal, it costs the owner nothing, and its content
stays the proposer's until the owner accepts it. Merging re-parents the config to the owner in the
same transaction that accepts the content. Rejecting transfers nothing — the config was the writer's
and always was, and `DraftDeleted` plus a `RevisionRetired` with `released: false` names it so they
can reclaim it.

**Lifecycle.** The holder is attached once and never removed. A draft is destroyed by
`resolve_draft_to_file` or `delete_draft`; `clear_drafts` does the latter over a caller-named range.

**Events.** `DraftPinned`, `DraftMerged`, `DraftDeleted`.

---

# Projects

## `ProjectHolder`

**What it is.** One account's authority root over its whole project surface.

**Ownership.** Shared, with `admin: address` as the gate. Not by preference: an owned holder could
only ever enter a transaction its own admin signed, which would make every delegate and operator path
impossible.

**`admin` is fixed at creation with no setter.** Both creation paths pass the account's address, and
the operator sibling passes `owner` and never `ctx.sender()` — the credential decides that a holder is
created, not whose it is. A holder rooted on a rotating wallet would tie an account's whole project
surface to a key the pool retires.

**One per account.** A second is refused by name (`EProjectHolderExists`) through the marker on
`User`, whichever form asked. The holder is created lazily, so nothing but that assert stops a second
one existing.

**Lifecycle.** Created by `open_project_holder` or `open_project_holder_as_operator`, shared
immediately. **No destructor.**

**Acted on by.** `create_project[_as_operator]` and `initialize_project_file[_as_operator]`, gated on
`can_init_db`; `set_file_set_root[_as_operator]`, gated on `can_set_root`. Every one resolves the
account from `admin`, tests the sender's grant against **that** account, and hands the same address
down to the mutator, which re-asserts `admin == owner`.

**Events.** `ProjectHolderCreated`, and the project events below.

## `Project`

**What it is.** Two fields: the inner file acting as the project's database, and the project's
commitment to the paths it resolves.

**Not an object.** A plain `store` value in a `dynamic_field`, keyed by the project's id. A project is
never transferred, never shared and never fetched by its own id — it is only ever reached through its
holder — so as a field entry it costs one entry rather than an object plus an entry, and one node
fetch rather than two.

**Its id is announced rather than derivable.** A project carries no name, so nothing off chain can
compute it; the id comes from `ctx.fresh_object_address()` and arrives in `ProjectCreated`.

**Inside it.** `db_inner_file: Option<ID>` — named once by `init_db` and never again (`DBEXIST`),
which is the one irreversible thing a project record does. And `file_set_root: vector<u8>` — the
32-byte Merkle root over the project's `(path, content_hash)` mapping, opening at the empty-set root
of 32 zero bytes.

**What a project used to be.** A name, a description, two timestamps and two counters, keyed by the
name so that a rename was an object removed and re-added. None of it was read by any contract
function. What is left is the two things a contract does read, plus the root that binds the names now
living off chain to the content they resolve to.

**The root is not recomputed on chain** — the set it commits to lives off chain and can be far larger
than a transaction. What the chain enforces is that the value is a well-formed root, that the holder
belongs to the account the caller was checked against, and that every move is announced with its
`previous_root`.

**Lifecycle.** Created by `create_project[_as_operator]`. **No destructor** — a project cannot be
removed from its holder.

**Events.** `ProjectCreated`, `ProjectDatabaseInitialised`, `ProjectFileSetRootChanged`.

---

# Values that are never stored

Three of these are enforced never-stored by the type system, and the enforcement is the design.

**`OperatorAuth`** — `copy, drop`, and deliberately **no `store`**, so no object can keep one: a
struct with `key` or `store` cannot carry a field that lacks `store`. The only way to obtain one is
`operator::authorise`, which needs a `&AdminCap`, so a function taking one cannot be reached by a
caller who does not hold the capability. It is proof, good for the length of one call, that the
sender presented a live operator credential — and it is threaded down through the domain layers
because `Option<&AdminCap>` is not a type Move will accept.

**`Credential`** — a `copy, drop` enum, `Pass(ID)` or `Operator(ID)`, constructible only from the
object it names. So the kind is settled by the type system rather than by the caller's word for it,
where a bare `ID` would carry no such answer. It is an argument and an event field, never a struct
field: adding a variant to any enum a published module declares is refused as an incompatible
upgrade, stored or not, and storing it would freeze the field's layout as well. A third credential
kind needs a new package either way.

**`FileEntry`** — `copy, drop, store`, one `(path, content_hash)` pair. Built by `file_set::new_entry`,
which validates the path, and consumed by `file_set::root` in the same call. Nothing stores one; the
root is what the chain keeps.

**`CompactionPlan`** — covered above. No abilities at all, which is a stronger statement than
"never stored": it cannot be stored, copied **or** dropped.
