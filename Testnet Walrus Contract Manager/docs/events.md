# The event stream

Everything the protocol announces, where it announces it from, and what an
off-chain consumer may rely on.

## Reading the whole stream

Every event type is declared in a module under `sources/events/`, and nowhere
else. That is what lets one filter return the protocol's whole history:

```graphql
{ events(filter: { type: "<PACKAGE-ID>" }) { nodes { contents { json } } } }
```

```
# gRPC, LedgerService.ListEvents
EventFilter { terms { event_type { event_type: "<PACKAGE-ID>" } } }
```

Both filter on the module the event type is **defined** in, and both accept an
address alone, so the whole surface comes back through one subscription and one
cursor however many modules declare into it. A consumer that wants one event
subscribes to `<PACKAGE-ID>::storage_events::BlobRenewed` instead.

**`suix_queryEvents` is gone.** JSON-RPC on public fullnodes returns
`-32601 Method not found` on both mainnet and testnet, checked 2026-08-26. Any
consumer still on it is not deprecated, it is dead.

## Payload fields cannot be filtered

Only sender, module, type and time are matchable. Under delegation the acting
`sender` differs from the record's `owner`, and `owner` is a payload field, so
*"every event for owner X"* cannot be expressed as a chain-side filter. Read the
stream whole and join locally.

## What the payloads promise

1. **Almost every event names the system it belongs to.** `mint_system` supports
   concurrent systems, so an event without one cannot be attributed. Five carry
   no `system_id`, in two groups.

   `WriterPassDestroyed` carries `file_id` and nothing above it: a pass names a
   file rather than a system, its holder destroys it alone, and there is no
   `SystemConfig` on that path.

   The four `product_events` carry `holder_id` in its place. A `ProjectHolder`
   holds an `admin` address and no system either, so attributing a project means
   joining `holder_id` back to its `ProjectHolderCreated` row and that row's
   `admin` to a registration. An address may hold one project holder per system,
   and where it holds more than one the stream alone does not say which holder
   belongs to which system.
2. **Every removal is announced, not only every creation.** Withdrawal,
   revocation, eviction, user removal, fallback removal and pass destruction all
   emit. A consumer that replays from genesis and only ever adds rows would
   reconstruct a state that never existed.
3. **Where the acting address differs from the subject, both are carried.**
   `owner` and `stored_by`, `owner` and `executed_by`, `commit_by`, `minted_by`.
4. **Aggregates are carried as the value after the change** where the chain still
   keeps one. Where it no longer does ,  the registered-user count, a file's deny
   count, a user's adopted-config total ,  the count is not in the payload either,
   because a value the chain does not hold is one the emitter would have had to
   compute purely to announce. A consumer accumulates those from the deltas, which
   is what `tests/support/replay.move` does and what the rebuild test checks.

### The credential behind a write

`DraftPinned.credential` is the id of the object the write was authorised by, and
`credential_kind` says which kind it is: `0` a writer pass, `1` a system
operator's admin capability. The draft object records neither. An id on its own
cannot be resolved to a type by anything on chain, and the variant set of an enum
a published module declares cannot be widened by a later upgrade, so the
discriminant belongs in the payload rather than in stored state.

### The operator set

A backend key is a **capability id** with a slot on the system, not an address.
Enrolment, refreshment and retirement each raise their own event; moving the
capability to another wallet raises none, because nothing on chain changes. A
consumer tracking who may act for a user therefore joins three things: the slots
in the stream, the `OperatorRoleGranted` rows, and the per-file
`operators_allowed` bit ,  and it cannot know which wallet holds a slot without
following the capability object itself.

### Timestamps

An event carries a time field only where that time is itself on-chain state ,  a
config's `uploaded_on`, a file's `created_at_ms`, a draft queue's
`last_modified`, a denial's deadline. Everything else takes the transaction's
wall clock from the event envelope, which carries it already. Putting it in the
payload would mean a `&Clock` argument on entry points that have no other use for
one, including renewal, where every extra shared-object input costs batch size.

## JSON encoding

Verified against live Sui mainnet GraphQL on 2026-08-26.

| Move type | JSON |
|---|---|
| `bool` | boolean |
| `u8`, `u16`, `u32` | number |
| `u64`, `u128`, `u256` | **string** ,  the value can exceed 2^53 |
| `address`, `ID` | `0x`-prefixed 32-byte hex string |
| `std::string::String` | string |
| `Option<T>` | `T`, or `null` |
| `vector<T>` | array of `T` |
| `vector<u8>` | **base64 string** ,  not an array; see below |

`vector<u8>` is a **special case** and it is now settled. It does not follow the
`vector<T>` rule above: it comes back as a **base64 string**, not as an array of
numbers and not as hex. A 32-byte commit sent as `00112233445566778899aabbccddeeff`
twice reads back as `"ABEiM0RVZneImaq7zN3u/wARIjNEVWZ3iJmqu8zd7v8="`. Confirmed on a
published testnet package across six events and five transactions, read both from
the executing client and re-fetched from the fullnode.

This affects every `commit` field, `previous_commit` on `HeadAdvanced`, both root
fields on `ProjectCreated` and `ProjectFileSetRootChanged`, and on
`LayoutRegistered` both roots plus **every element of** `paths` and
`content_hashes` ,  a `vector<vector<u8>>` is a JSON array of base64 strings.
**A decoder must base64-decode them.** `vector<u16>` and `vector<ID>` are
unaffected and are still arrays.

`docs/event-schema.json` carries one `parsedJson` example per event type, in the
same shapes.

## The events

### System ,  `system_events`

| Event | Emitted from | Fields |
|---|---|---|
| `SystemCreated` | system/config.move , `new` | `system_id`, `previous_system`, `minted_by`, `version`, `tier_table`, `max_epochs_ahead`, `cost_change_apikey_forms`, `cost_to_migrate_system`, `cost_to_update_name`, `cost_to_delete` |
| `SystemSucceeded` | system/config.move , `set_next_system` | `system_id`, `next_system`, `minted_by` |
| `SystemFeesChanged` | system/config.move , `set_costs` | `system_id`, `cost_change_apikey_forms`, `cost_to_migrate_system`, `cost_to_update_name`, `cost_to_delete`, `changed_by` |
| `SystemTiersChanged` | system/config.move , `set_tier_table` | `system_id`, `tier_table`, `max_epochs_ahead`, `changed_by` |
| `SystemVersionMigrated` | system/config.move , `update_version` | `system_id`, `version`, `migrated_by` |
| `AdminCapMinted` | system/admin_cap.move , `transfer_to` | `system_id`, `admin_cap`, `state`, `total_system`, `recipient`, `minted_by` |
| `SystemOperatorEnrolled` | system/config.move , `enrol_operator` | `system_id`, `admin_cap`, `until_ms`, `may_bypass_draft`, `enrolled_by` |
| `SystemOperatorRefreshed` | system/config.move , `refresh_operator` | `system_id`, `admin_cap`, `until_ms`, `may_bypass_draft`, `refreshed_by` |
| `SystemOperatorRetired` | system/config.move , `retire_operator` | `system_id`, `admin_cap`, `retired_by` |

### Treasury ,  `treasury_events`

| Event | Emitted from | Fields |
|---|---|---|
| `VaultCoinSupportChanged` | system/vault.move , `add_supported_coin`, `remove_supported_coin`, `support_coin_on_creation` | `system_id`, `coin_type`, `supported` |
| `VaultDeposited` | system/vault.move , `deposit` | `system_id`, `coin_type`, `amount`, `new_balance` |
| `SystemWithdraw` | system/vault.move , `withdraw` | `system_id`, `operator`, `coin_type`, `amount`, `new_balance` |

### Identity ,  `identity_events`

| Event | Emitted from | Fields |
|---|---|---|
| `UserRegistered` | identity/registry.move , `create_registry` | `system_id`, `user_id`, `registry_id`, `user`, `public_username`, `created_at`, `decay_at` |
| `UserJoinedSystem` | identity/user.move , `add_user` | `system_id`, `user`, `user_id` |
| `UserLeftSystem` | identity/user.move , `remove_user` | `system_id`, `user`, `user_id` |
| `UsernameUpdated` | identity/registry.move , `update_username` | `system_id`, `registry_id`, `user`, `public_username` |
| `RegistryMigrated` | identity/registry.move , `migrate_system` | `system_id`, `previous_system`, `registry_id`, `user`, `updated_at` |
| `WalletCreated` | identity/wallet.move , `create_wallet` | `system_id`, `wallet_id`, `user`, `created_at` |
| `WalletDeposited` | identity/wallet.move , `deposit` | `system_id`, `user`, `coin_type`, `amount`, `new_balance` |
| `WalletWithdrawn` | identity/wallet.move , `withdraw`, `withdraw_all` | `system_id`, `user`, `coin_type`, `amount`, `new_balance` |
| `PermissionGranted` | identity/permission.move , `create_permission_state`, `replace_permission_state` | `system_id`, `owner`, `delegate`, `add_blob_to_address`, `create_inner_file`, `create_writer_pass`, `can_init_db`, `can_compact`, `can_set_root` |
| `PermissionRevoked` | identity/permission.move , `revoke_permission_state` | `system_id`, `owner`, `delegate` |
| `OperatorRoleGranted` | identity/permission.move , `create_operator_role_state`, `replace_operator_role_state` | `system_id`, `owner`, `add_blob_to_address`, `create_inner_file`, `create_writer_pass`, `can_init_db`, `can_compact`, `can_set_root` |
| `OperatorRoleRevoked` | identity/permission.move , `revoke_operator_role_state` | `system_id`, `owner` |

### Blob custody ,  `storage_events`

| Event | Emitted from | Fields |
|---|---|---|
| `BlobStored` | storage/blob_config.move , `new` | `system_id`, `config_id`, `owner`, `stored_by`, `blobs_obj_id`, `blob_sizes`, `size`, `encoded_size`, `end_epoch`, `epoch_set`, `cycle_limit`, `uploaded_on` |
| `BlobConfigOwnerChanged` | storage/blob_config.move , `transfer_ownership` | `system_id`, `config_id`, `previous_owner`, `new_owner` |
| `BlobConfigOwnershipOffered` | storage/blob_config.move , `offer_ownership` | `system_id`, `config_id`, `owner`, `recipient` |
| `BlobConfigOwnershipAccepted` | storage/blob_config.move , `accept_ownership` | `system_id`, `config_id`, `previous_owner`, `new_owner` |
| `BlobConfigOwnershipOfferCancelled` | storage/blob_config.move , `cancel_ownership_offer` and `transfer_ownership` | `system_id`, `config_id`, `owner`, `recipient` |
| `BlobRenewed` | storage/renew.move , inside the per-blob loop | `system_id`, `config_id`, `owner`, `blob_obj_id`, `epoch_set`, `current_epoch`, `epochs_extended`, `new_end_epoch`, `wal_spent`, `executed_by` |
| `RenewCycleSpent` | storage/renew.move , after the cycle is charged | `system_id`, `config_id`, `owner`, `blobs_extended`, `wal_spent`, `cycles_remaining`, `executed_by` |
| `RenewSkipped` | storage/renew.move , on every path that does no work | `system_id`, `config_id`, `owner`, `blob_obj_id`, `reason`, `epoch_set`, `current_epoch`, `executed_by` |
| `BlobWithdrawn` | storage/blob_config.move , `destroy` | `system_id`, `config_id`, `owner`, `blobs_obj_id` |
| `ForeignBlobsAdopted` | entry/upload.move , `adopt` | `system_id`, `owner`, `adopted_by`, `config_id`, `blob_count` |
| `LayoutRegistered` | storage/compaction.move , `register` | `system_id`, `config_id`, `owner`, `registered_by`, `kind`, `generation`, `file_count`, `file_set_root`, `paths`, `content_hashes`, `superseded_root`, `superseded_count`, `superseded`, `created_at_ms` |

#### Custody moves in two acts, and the stream says which act happened

`BlobConfigOwnerChanged` is the event that says custody moved. It is not the
event that says *why*, because a draft merge re-parents a config too, on a path
nobody offered or accepted anything on.

A handover between users is therefore three rows, not one. `offer` raises
`BlobConfigOwnershipOffered` and moves nothing. The named recipient's `accept`
raises `BlobConfigOwnerChanged` and `BlobConfigOwnershipAccepted` together, in
that order. The owner's `cancel` raises `BlobConfigOwnershipOfferCancelled` on
its own.

A consumer tracking whether an offer stands needs one more rule:
`BlobConfigOwnershipOfferCancelled` is also raised when custody moves by any
other route, because that voids a standing offer. Those two cases are told apart
by what accompanies the row in the same transaction ,  a void carries
`BlobConfigOwnerChanged` and no `BlobConfigOwnershipAccepted`; a deliberate
withdrawal carries neither.

There is no expiry, no auto-accept and no inbound policy. Ownership decides who
may withdraw, so requiring the recipient to act is what stops content being
pushed onto an address that never asked for it, and once it is required none of
the accounting rules that would otherwise be needed are.

#### The adoption record has no on-chain index behind it

`ForeignMetaCreated` is gone and so is the per-user `ForeignMeta` object it
announced. The index it named covered only the *adopted* subset of a user's
configs and said nothing about that, so a client walking it got a partial answer
and had to consult a service anyway. Two sources replace it, which is one more
than it had: this event, and `BlobConfig.owner`, which answers ownership from the
config object itself and therefore survives an event a consumer missed.

An adoption is now **one config per call** rather than one per blob, so
`config_ids` has become `config_id` and `blob_count` says how many blobs went
into it. `BlobStored` fires once beside it with the blob ids, the sizes and the
renewal terms.

#### `LayoutRegistered` is the receipt, and it has to outlive the data

A quilt's patch index and its per-patch tags live *inside* the quilt, so deleting
a generation destroys the record of what that generation contained ,  and deleting
it is the point of compacting past it. The object keeps two 32-byte roots and the
counts beside them, which is constant in the file count; the event keeps the
members those roots commit to. A consumer that wants to know what generation *N*
held after generation *N* is gone reads this event and nothing else.

`paths` and `content_hashes` are positionally paired and arrive in **ascending
path order**, which is the order the root is folded in, so a consumer recomputing
`file_set_root` folds them as given. `superseded` arrives in ascending id order
for the same reason. Both are `vector<vector<u8>>` and `vector<ID>` respectively:
each element of `paths` and `content_hashes` is a `vector<u8>` and therefore
arrives **base64**, inside a JSON array.

`kind` is `0` for raw blobs and `1` for a quilt. `generation` is strictly greater
than every generation the compaction supersedes, so the lineage is a strict order
rather than a set of claims.

There is no accept, reject or expiry event, because there is no accept, reject or
expiry. Registering a layout destroys nothing and re-parents nothing; the only
consent signal is whether the owner subsequently withdraws the superseded
configs, which raises `BlobWithdrawn` and which nobody but the owner can cause.

### Inner files ,  `innerfile_events`

| Event | Emitted from | Fields |
|---|---|---|
| `InnerFileCreated` | innerfile/inner_file.move , `share` | `system_id`, `file_id`, `owner`, `created_by`, `writers_length`, `track_back_length`, `epoch_set`, `cycle_end`, `draft_epoch_duration`, `operators_allowed`, `operators_may_bypass_draft`, `operators_may_draft`, `created_at_ms`, `commit`, `blob_config_id` |
| `HeadAdvanced` | innerfile/eviction.move , `advance_history` | `system_id`, `file_id`, `commit`, `commit_by`, `blob_config_id`, `previous_commit`, `previous_blob_config`, `window_depth`, `last_modified` |
| `RevisionRetired` | innerfile/eviction.move , `release` and `discard` | `system_id`, `file_id`, `blob_config`, `commit`, `commit_by`, `released` |
| `RootChangeSet` | innerfile/inner_file.move , `swap_root_change` | `system_id`, `file_id`, `commit`, `commit_by`, `blob_config_id`, `previous_blob_config` |
| `RootChangeRemoved` | innerfile/inner_file.move , `extract_root_change` | `system_id`, `file_id`, `blob_config_id`, `removed_by` |
| `FileOperatorPolicySet` | innerfile/inner_file.move , `set_operator_policy` | `system_id`, `file_id`, `operators_allowed`, `operators_may_bypass_draft`, `operators_may_draft`, `set_by` |

### Drafts ,  `draft_events`

| Event | Emitted from | Fields |
|---|---|---|
| `DraftPinned` | innerfile/draft.move , `pin_draft` | `system_id`, `file_id`, `draft_id`, `draft_index`, `credential`, `credential_kind`, `issue`, `commit`, `commit_by`, `blob_config_id`, `total_draft`, `last_modified` |
| `DraftMerged` | innerfile/draft.move , `resolve_draft_to_file` | `system_id`, `file_id`, `draft_index`, `merged_by`, `commit`, `blob_config_id`, `total_draft`, `last_modified` |
| `DraftDeleted` | innerfile/draft.move , `delete_draft` | `system_id`, `file_id`, `draft_index`, `deleted_by`, `total_draft`, `last_modified` |

### Projects ,  `product_events`

A project is addressed by a minted `ID` and carries no name on chain, so
`ProjectCreated` is the only announcement that the id exists. A reader holding
the label a user typed has nothing else to resolve it against.

`file_set_root` is the 32-byte Merkle root over the project's whole
`(path, content_hash)` mapping, in the frozen format ,  leaf
`H(0x00 || u32_be(len(path)) || path || content_hash)`, node `H(0x01 || l || r)`,
sorted ascending by raw path bytes, last node of an odd level paired with itself,
empty set 32 zero bytes. It is a `vector<u8>` and therefore arrives base64.

| Event | Emitted from | Fields |
|---|---|---|
| `ProjectHolderCreated` | product/project_object.move , `create_project_holder` | `holder_id`, `admin` |
| `ProjectCreated` | product/project_object.move , `create_project` | `holder_id`, `project_id`, `created_by`, `file_set_root` |
| `ProjectDatabaseInitialised` | product/project_object.move , `init_db` | `holder_id`, `project_id`, `inner_file_id`, `initialised_by` |
| `ProjectFileSetRootChanged` | product/project_object.move , `set_file_set_root` | `holder_id`, `project_id`, `file_set_root`, `previous_root`, `changed_by` |

### Passes and revocations ,  `pass_events`

| Event | Emitted from | Fields |
|---|---|---|
| `WriterPassMinted` | innerfile/writer_pass.move , `transfer_to` | `system_id`, `file_id`, `pass_id`, `holder`, `duration`, `admin_privilege`, `minted_by` |
| `WriterPassDestroyed` | innerfile/writer_pass.move , `destroy_writer_pass` | `file_id`, `pass_id`, `destroyed_by` |
| `WriterPassRevoked` | innerfile/deny_list.move , `revoke_pass` | `system_id`, `file_id`, `pass_id`, `revoked_by` |
| `WriterDenied` | innerfile/deny_list.move , `deny` | `system_id`, `file_id`, `writer`, `until_ms`, `denied_by` |
| `WriterUndenied` | innerfile/deny_list.move , `undeny` | `system_id`, `file_id`, `writer`, `undenied_by` |

## The contract with consumers

`scripts/check-events.sh` runs in CI and fails the build when any of these stops
holding:

- an emitter in `sources/events/` has no call site
- `event::emit` appears outside `sources/events/`
- an event module imports anything internal
- an `assert!` aborts with a bare integer
- the mainnet and testnet packages differ in `sources/` or `tests/`

`tests/support/replay.move` rebuilds an off-chain view from the stream alone, and
`tests/regression/rebuild_tests.move` compares it against chain state field by
field. The replay asserts that it consumed every event raised in each transaction,
so adding an event and not teaching the replay about it fails the build rather
than being silently dropped.
