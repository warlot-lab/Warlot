# Open work

What is actually outstanding, separated from what is finished and what was deliberately dropped.

The file this replaces mixed all three with no way to tell them apart, and had done since before
the identity, storage, innerfile and product domains existed. Where an item below was in that list,
the wording is kept close enough to recognise.

---

## Open

**Renewal without an off-chain database.** A dry run, an on-chain indexer, or both, so the renewal
bot can decide whether a config needs work by reading the chain rather than by keeping its own
state. This is the item that makes bot operation truly transactional, and it is the oldest one
still standing.

**The operator refresh job.** `operator::authorise` aborts `EOperatorExpired` once a slot lapses,
and nothing schedules `refresh_operator`. That is a cron job on the admin side, holding the
original capability, and it does not exist. See `documentation/upgrades.md` section 4.

**Custody of the original `AdminCap`.** No expiry, no revocation, and it is now also the key that
keeps the operator pool alive. Recorded in `documentation/deployment.md`; not solved.

**Transferring an `InnerFile`.** A file's custody is its `owner` plus every `BlobConfig` in its
rollback window plus its fallback, each a separate shared object, so moving them together runs into
the transaction's shared-object limit and a half-moved file has its history belonging to two
people. Deferred deliberately. The likely shape is moving `owner` alone and offering the revisions'
configs individually, which means a file can change hands while its history does not — a thing to
decide rather than discover.

**User deletion.** Not built, and the half-finished shape is visible: `user::remove_user` exists as
a `public(package)` function whose only caller is `migrate_system`, and `SystemConfig` carries a
`cost_to_delete` fee that **no path charges** — nothing in `sources/entry/` reads it. Deleting an
account is not simply removing the record: the account's `BlobConfig`s name no system and would
outlive it, holding content whose `can_compact` check reads a `User` that no longer exists. Decide
what happens to the content before building the call.

**A storage abstraction and a blob-settings registry.** A `blobType -> settingsSchema` map, so
encryption, TTL and size limits are per-type rather than per-call. Nothing depends on it yet.

---

## Done

| | Where |
|---|---|
| User registration, the registry object, and migration between systems | `entry_register` |
| Blobs handed back to the user's own account | `entry_withdraw` |
| A deny list blocking unauthorised writers | `deny_list`, per file |
| Version migration control | `admin::migrate_version`, `register::migrate_system` |
| The admin hierarchy and mint awareness | `admin_cap`, `state_original` / `state_duplicate` |
| Admin key decay, per credential | operator slots carry `until_ms`; `retire_operator` revokes |
| Blob storage, foreign adoption, renewal, withdrawal, arbitrary tables | `storage/` |
| Bulk operations | `revoke_passes`, `clear_drafts`, batch adoption |
| Compaction, and proving a repack faithful | `compaction`, `layout`, `file_set` |

---

## Dropped, and why

**A `paused` flag freezing all operations.** Refused. A pause switch is a lever that stops a user
renewing their own storage, and renewal is the one thing the protocol promises stays permissionless
even if Warlot disappears. The version gate already fences the case a pause was wanted for — an
upgrade in flight — and it fences it without anybody deciding to pull it.

**Per-blob and per-user freezes.** Same reason, one level down.

**Trash, soft delete and a purge.** Refused. Content is destroyed only by its owner passing the
config by value, and a soft-delete state would be a second answer to "who holds this" that the
chain would have to keep consistent with the first. Compaction is how content is superseded, and it
supersedes nothing until the owner acts.

**Burning or flagging an admin key on suspicion.** Not built. `retire_operator` removes a
credential from the set and cannot abort, which is the same outcome without a flag state that has
to be interpreted.

**Contract-level signatures on registry entries.** Unnecessary. A registry is keyed off
`ctx.sender()`, so it cannot be created for an address that did not sign.

**Rotating and hashing per-user cryptographic keys on chain.** Out of scope for the contract. The
chain holds authority, value and commitments; a key hash is none of the three.

**Aggregate counters per user.** Deliberately absent. See the root `README.md`: totals no contract
reads belong in a database.
