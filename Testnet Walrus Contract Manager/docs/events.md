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

1. **Every event names the system it belongs to.** `mint_system` supports
   concurrent systems, so an event without one cannot be attributed. The single
   exception is `WriterPassDestroyed`: a pass names a file rather than a system,
   its holder destroys it alone, and there is no `SystemConfig` on that path.
2. **Every removal is announced, not only every creation.** Withdrawal,
   revocation, eviction, user removal, fallback removal and pass destruction all
   emit. A consumer that replays from genesis and only ever adds rows would
   reconstruct a state that never existed.
3. **Where the acting address differs from the subject, both are carried.**
   `owner` and `stored_by`, `owner` and `executed_by`, `commit_by`, `minted_by`.
4. **Aggregates are carried as the value after the change**, so a consumer never
   has to guess whether it saw every delta.

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

This affects every `commit` field, and `previous_commit` on `HeadAdvanced`. **A
decoder must base64-decode them.** `vector<u16>` and `vector<ID>` are unaffected and
are still arrays.

`docs/event-schema.json` carries one `parsedJson` example per event type, in the
same shapes.

## The events

### System ,  `system_events`

| Event | Emitted from | Fields |
|---|---|---|
| `SystemCreated` | system/config.move , `new` | `system_id`, `previous_system`, `minted_by`, `version`, `warlot_allowed_address`, `tier_table`, `max_epochs_ahead`, `cost_change_apikey_forms`, `cost_to_migrate_system`, `cost_to_update_name`, `cost_to_delete` |
| `SystemSucceeded` | system/config.move , `set_next_system` | `system_id`, `next_system`, `minted_by` |
| `SystemFeesChanged` | system/config.move , `set_costs` | `system_id`, `cost_change_apikey_forms`, `cost_to_migrate_system`, `cost_to_update_name`, `cost_to_delete`, `changed_by` |
| `SystemTiersChanged` | system/config.move , `set_tier_table` | `system_id`, `tier_table`, `max_epochs_ahead`, `changed_by` |
| `SystemVersionMigrated` | system/config.move , `update_version` | `system_id`, `version`, `migrated_by` |
| `AdminCapMinted` | system/admin_cap.move , `transfer_to` | `system_id`, `admin_cap`, `state`, `total_system`, `recipient`, `minted_by` |

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
| `UserJoinedSystem` | identity/user.move , `add_user` | `system_id`, `user`, `user_id`, `users` |
| `UserLeftSystem` | identity/user.move , `remove_user` | `system_id`, `user`, `user_id`, `users` |
| `UsernameUpdated` | identity/registry.move , `update_username` | `system_id`, `registry_id`, `user`, `public_username` |
| `RegistryMigrated` | identity/registry.move , `migrate_system` | `system_id`, `previous_system`, `registry_id`, `user`, `updated_at` |
| `WalletCreated` | identity/wallet.move , `create_wallet` | `system_id`, `wallet_id`, `user`, `created_at` |
| `WalletDeposited` | identity/wallet.move , `deposit` | `system_id`, `user`, `coin_type`, `amount`, `new_balance` |
| `WalletWithdrawn` | identity/wallet.move , `withdraw`, `withdraw_all` | `system_id`, `user`, `coin_type`, `amount`, `new_balance` |
| `PermissionGranted` | identity/permission.move , `create_table`, `create_permission_state` | `system_id`, `owner`, `delegate`, `add_blob_to_address`, `create_inner_file`, `create_writer_pass`, `can_init_db`, `can_compact` |
| `PermissionRevoked` | identity/permission.move , `revoke_permission_state` | `system_id`, `owner`, `delegate` |

### Blob custody ,  `storage_events`

| Event | Emitted from | Fields |
|---|---|---|
| `BlobStored` | storage/blob_config.move , `new` | `system_id`, `config_id`, `owner`, `stored_by`, `blobs_obj_id`, `blob_sizes`, `size`, `encoded_size`, `end_epoch`, `epoch_set`, `cycle_limit`, `fileMeta_id`, `uploaded_on` |
| `BlobConfigOwnerChanged` | storage/blob_config.move , `transfer_ownership` | `system_id`, `config_id`, `previous_owner`, `new_owner` |
| `BlobRenewed` | storage/renew.move , inside the per-blob loop | `system_id`, `config_id`, `owner`, `blob_obj_id`, `epoch_set`, `current_epoch`, `epochs_extended`, `new_end_epoch`, `wal_spent`, `executed_by` |
| `RenewCycleSpent` | storage/renew.move , after the cycle is charged | `system_id`, `config_id`, `owner`, `blobs_extended`, `wal_spent`, `cycles_remaining`, `executed_by` |
| `RenewSkipped` | storage/renew.move , on every path that does no work | `system_id`, `config_id`, `owner`, `blob_obj_id`, `reason`, `epoch_set`, `current_epoch`, `executed_by` |
| `BlobWithdrawn` | storage/blob_config.move , `destroy` | `system_id`, `config_id`, `owner`, `blobs_obj_id` |
| `ForeignMetaCreated` | foreign/foreign_meta.move , `create_meta` | `system_id`, `foreign_meta_id`, `owner` |
| `ForeignBlobsAdopted` | foreign/foreign_meta.move , `add_foreign_blob` | `system_id`, `foreign_meta_id`, `owner`, `adopted_by`, `chunk_index`, `config_ids`, `total_blob_config` |

### Inner files ,  `innerfile_events`

| Event | Emitted from | Fields |
|---|---|---|
| `InnerFileCreated` | innerfile/inner_file.move , `share` | `system_id`, `file_id`, `owner`, `created_by`, `writers_length`, `track_back_length`, `epoch_set`, `cycle_end`, `draft_epoch_duration`, `created_at_ms`, `commit`, `blob_config_id` |
| `HeadAdvanced` | innerfile/eviction.move , `advance_history` | `system_id`, `file_id`, `commit`, `commit_by`, `blob_config_id`, `previous_commit`, `previous_blob_config`, `window_depth`, `last_modified` |
| `RevisionRetired` | innerfile/eviction.move , `release` and `discard` | `system_id`, `file_id`, `blob_config`, `commit`, `commit_by`, `released` |
| `RootChangeSet` | innerfile/inner_file.move , `swap_root_change` | `system_id`, `file_id`, `commit`, `commit_by`, `blob_config_id`, `previous_blob_config` |
| `RootChangeRemoved` | innerfile/inner_file.move , `extract_root_change` | `system_id`, `file_id`, `blob_config_id`, `removed_by` |

### Drafts ,  `draft_events`

| Event | Emitted from | Fields |
|---|---|---|
| `DraftPinned` | innerfile/draft.move , `pin_draft` | `system_id`, `file_id`, `draft_id`, `draft_index`, `writer_pass`, `issue`, `commit`, `commit_by`, `blob_config_id`, `total_draft`, `last_modified` |
| `DraftMerged` | innerfile/draft.move , `resolve_draft_to_file` | `system_id`, `file_id`, `draft_index`, `merged_by`, `commit`, `blob_config_id`, `total_draft`, `last_modified` |
| `DraftDeleted` | innerfile/draft.move , `delete_draft` | `system_id`, `file_id`, `draft_index`, `deleted_by`, `total_draft`, `last_modified` |

### Passes and revocations ,  `pass_events`

| Event | Emitted from | Fields |
|---|---|---|
| `WriterPassMinted` | innerfile/writer_pass.move , `transfer_to` | `system_id`, `file_id`, `pass_id`, `holder`, `duration`, `admin_privilege`, `minted_by` |
| `WriterPassDestroyed` | innerfile/writer_pass.move , `destroy_writer_pass` | `file_id`, `pass_id`, `destroyed_by` |
| `WriterPassRevoked` | innerfile/deny_list.move , `revoke_pass` | `system_id`, `file_id`, `pass_id`, `revoked_by` |
| `WriterDenied` | innerfile/deny_list.move , `deny` | `system_id`, `file_id`, `writer`, `until_ms`, `denied_by`, `numbers_of_deny` |
| `WriterUndenied` | innerfile/deny_list.move , `undeny` | `system_id`, `file_id`, `writer`, `undenied_by`, `numbers_of_deny` |

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
