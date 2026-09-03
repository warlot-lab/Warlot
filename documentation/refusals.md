# What the contract will not do

Written as carefully as the capabilities, because the absences are load-bearing. If you are looking
for one of these, stop looking — it is not hidden behind a permission bit or an admin call.

---

## There is no pause switch

No flag freezes the protocol, per system, per user or per blob. An early plan had one; it was
refused.

A pause is a lever that stops a user renewing their own storage, and permissionless renewal is the
one thing the protocol promises survives Warlot disappearing. A switch that can suspend it makes
that promise conditional on nobody pulling it.

The case a pause is usually wanted for — a package upgrade in flight, with state written by code
that is being replaced — is already covered by the **version gate**, which closes the whole entry
surface after an upgrade until an admin calls `migrate_version`. It fences that window without
anybody deciding to, and it cannot be left on by accident because the protocol is unusable until it
is cleared. See [upgrades.md](upgrades.md).

---

## There is no delete, and no trash

**No admin can destroy a user's content.** No entry point takes a `BlobConfig` belonging to someone
else and consumes it. The only calls that destroy one are `self_withdraw_blob` and
`self_withdraw_blobs`, which take it by value and check the sender is its owner.

**No delegate can either.** There is no `can_delete` bit among the six, and none is planned.
`can_compact` is delegable precisely because writing a new quilt is *additive*: it destroys nothing
and supersedes nothing until the owner acts. Withdrawal is the opposite, and it cannot be undone by
the owner noticing afterwards. So compaction is split down that line — the delegate writes the quilt
and registers the receipt, the owner withdraws the superseded configs, and until they do the old
content is exactly as renewable as it was.

**There is no soft delete.** A trash state would be a second answer to "who holds this" that the
chain would have to keep consistent with the first. Content is either under a config or it is gone.

**There is no user deletion.** `user::remove_user` exists but is `public(package)`, and its only
caller is `migrate_system`. Deleting an account is not simply removing the record: its `BlobConfig`s
name no system and would outlive it, holding content whose `can_compact` check reads a `User` that
no longer exists. It is open work, not a hidden feature — see the package's `docs/todo.md`.

---

## An operator can never withdraw, and never mints a pass

No `_as_operator` sibling exists for `self_withdraw_blob`, `merge_draft_into_file`, `delete_draft`,
`set_root_change`, `create_pass`, `deny_writer` or `set_operator_policy`. Six of those assert the
sender is the file's owner, so a credential adds nothing: an operator that could satisfy that assert
would *be* the owner.

`create_writer_pass` is refused structurally rather than merely left unimplemented.
`grant_operator_role` does not accept the bit; both operator creation paths hardcode
`should_include_pass = false`; `entry_file_access::create_pass` is owner-only. A pass binds to one
address, the backend rotates keys, and the point of the operator set is that authority follows the
capability slot. An operator minting passes would be manufacturing the single-wallet binding the
model exists to remove.

---

## The chain does not hold names, descriptions or counters

No file name, no folder label, no description, no per-user totals. These are things no contract
function reads, so putting them on chain means paying consensus for them and keeping them consistent
for ever.

What the chain holds instead is a **commitment** — a 32-byte Merkle root binding logical paths to
content hashes. A database serves the names quickly; the root is what stops it serving the wrong
bytes.

One consequence for consumers: *"every event for owner X"* **cannot be expressed as a chain-side
filter**. Only sender, module, type and time are matchable, and under delegation the acting `sender`
differs from the record's `owner`, which is a payload field. Read the stream whole and join locally.

---

## An `InnerFile` cannot be transferred

Deliberately deferred, not overlooked. A file's custody is its `owner` **plus** every `BlobConfig`
in its rollback window (up to `MAX_TRACK_BACK` = 8) **plus** its fallback — each a separate shared
object. Moving them together runs into the transaction's shared-object input limit, and a half-moved
file is one whose history belongs to two people.

The likely eventual shape is moving `InnerFile.owner` alone and offering the revisions' configs
individually, which means a file could change hands while its history did not. That is something to
decide deliberately rather than discover mid-implementation.

`BlobConfig` custody **can** be transferred, through offer and accept. See [custody.md](custody.md).

---

## Nobody can push content onto you

`BlobConfig` custody moves only when the recipient calls `accept`. There is no push, no auto-accept,
no inbound quota and no byte budget — and none is needed, because requiring the recipient to act
closes the vector by construction rather than by a policy that has to be tuned.

An earlier design had an `auto_accept_budget` and a `max_auto_config_size` on each user. It was
dropped once the consent gate existed, because no path needed auto-accept: a direct operator write
is born owned by you and transfers nothing, a draft merge is your own explicit act, and a rejected
draft stays with its writer.

The exception that is not an exception: a **delegated store** puts content under your address
without a further accept. That was consented to once already, at grant time —
`add_blob_to_address` is the consent, and revoking it is the lever. Requiring an accept there would
break every operator write and every delegated upload while protecting nobody.

---

## A rejected draft is not pushed onto the file's owner

It stays with the writer who proposed it, along with any offer they had made on it. The config is
theirs and always was.

Transferring it to the file's owner automatically was considered and refused: the owner **rejected**
it, and pushing custody onto them would make saying no cost them storage.

The operational consequence is real and belongs in the backend's runbook rather than in the
contract: a rotating wallet must have its owned configs drained before it is retired from the pool,
because only that address can withdraw them. An owner who wants to avoid producing them at all sets
`operators_may_draft: false`.

---

## A layout cannot be rewritten

`blob_config::set_layout` refuses a config that already carries one. The layout is the **receipt** a
holder of superseded content checks before deleting it, so a layout that could be replaced would be
a receipt Warlot could rewrite after the fact. A new generation is a new config.

---

## A project cannot rename its database, and an account cannot hold two holders

`init_db` names a project's database once. Having named it, it cannot name another — that is the one
invariant the project record exists to hold.

A second `ProjectHolder` for one account is refused by name (`EProjectHolderExists`), through a
marker on `User`, whichever form asked. With lazy creation and no marker, nothing would stop two
holders existing, projects would split across them, and "which holder is this account's" would
become a question with two answers.

---

## `migrate_version` is not version-gated, on purpose

Every other entry point taking a `SystemConfig` asserts the version first. This one must not: it is
the call that raises a stale system to the package version, so gating it would leave a system that
could never be repaired.

It is excused **by name** in `scripts/check-events.sh` section 6, with the reason recorded there,
rather than by a pattern that could quietly excuse something else.

---

## `suix_queryEvents` is gone

Not our refusal, but consumers hit it here. JSON-RPC returns `-32601 Method not found` on public
fullnodes, mainnet and testnet, checked 2026-08-26. Any consumer still on it is not deprecated, it
is dead. Use the GraphQL `events` filter or gRPC `LedgerService.ListEvents`; both filter on the
module an event type is **defined** in, which is why every event in this protocol is declared under
`sources/events/`.
