# Worked call sequences

Each sequence lists the calls in order and the events they raise, so a consumer can predict the
stream before reading the source. Event names are the structs declared under `sources/events/`; the
full field lists are in each package's `docs/events.md`.

Every call below asserts the system's version first. That abort is not repeated in each sequence.

---

## 1. Registration

```move
entry_register::all_register_user_publicly(system, username, clock, ctx)
```

| Event | |
|---|---|
| `UserRegistered` | the account exists, with its `Registry` and its public label |
| `UserJoinedSystem` | the `User` object is now a dynamic field of this system |

`all_register_user_with_system_permission` does the same and additionally grants the operator role
every bit it can hold, adding `OperatorRoleGranted`. That is the ordinary path for an account the
backend will act for: consent given once, narrowed later.

The `Registry` is **owned** by the user; the `User` is a dynamic object field on the shared
`SystemConfig`. A user who only ever stores blobs never acquires a delegation table, a deny list, a
draft queue, a wallet or a project holder — each is attached by the first call that puts something
in it.

---

## 2. Adopting blobs the caller already holds

```move
entry_upload::foreign_blob_add(system, owner, cycle_end, epoch_set, blobs, clock, ctx)
```

| Event | |
|---|---|
| `BlobStored` | one config now holds these blobs, with their term and mandate |
| `ForeignBlobsAdopted` | the adoption itself, naming who adopted for whom |

Bounded at `MAX_ADOPTION_BATCH = 100` blobs per call. `epoch_set` must be a term the system sells
(`tier::validate`). Storing under another address needs `add_blob_to_address` on that address —
`foreign_blob_add_as_operator` is the same call satisfying it through the operator role.

---

## 3. Creating a file and writing to it

```move
entry_file_create::create_file(system, owner, writers_length, track_back_length, blobs,
                               epoch_set, cycle_end, clock, commit, draft_epoch_duration,
                               operators_allowed, operators_may_bypass_draft, operators_may_draft,
                               should_include_pass, pass_duration, ctx)
```

| Event | |
|---|---|
| `BlobStored` | the first revision's config |
| `InnerFileCreated` | the shared file, its window depth, its terms and its first commit |
| `WriterPassMinted` | the owner's own non-decaying, draft-bypassing pass |
| `WriterPassMinted` | again, only if `should_include_pass` and the caller is not the owner |

Then a write straight into history:

```move
entry_file_write::write_(file, pass, /* to_draft */ false, issue, clock, system,
                         blobs, commit, evicted, ctx)
```

| Event | |
|---|---|
| `BlobStored` | the new revision's config, owned by the **file's owner** |
| `HeadAdvanced` | the new head, the one it displaced, and the window depth after |
| `RevisionRetired` | only once the window is full — see below |

**`evicted` is required exactly when the window is full.** The rollback window holds
`track_back_length` revisions; the write that overflows it pushes one out, and that revision is the
last on-chain reference to content that is stored and being paid for. So the caller has to say what
becomes of it by passing the displaced revision's `BlobConfig`. Pass it when nothing is displaced
and the call is refused (`EUnexpectedConfig`); omit it when something is and the call is refused
(`EEvictedConfigRequired`).

It is reconstructible from the stream alone: `HeadAdvanced` carries `blob_config_id` and
`window_depth`, and the window is newest-first, so a FIFO of depth `track_back_length` fed from the
stream yields the config to pass. `RevisionRetired.released` says which of the two outcomes
happened — content handed back and the config destroyed, or the config left alive because a draft's
author or the file's own fallback still holds a claim on it.

---

## 4. Proposing and merging a draft

```move
entry_file_write::write_(file, pass, /* to_draft */ true, issue, clock, system,
                         blobs, commit, /* evicted */ vector[], ctx)
```

| Event | |
|---|---|
| `BlobStored` | the proposal's config, owned by **the sender**, not the file's owner |
| `DraftPinned` | its index in the queue, the credential that pushed it, and the queue depth |

A draft displaces nothing, so it can retire nothing: passing `evicted` here is refused.

The owner accepts:

```move
entry_file_draft::merge_draft_into_file(system, file, owner_pass, draft_config,
                                        draft_index, merge_latest, evicted, clock, ctx)
```

| Event | |
|---|---|
| `DraftMerged` | the draft leaves the queue |
| `BlobConfigOwnershipOfferCancelled` | only if the writer had an offer standing on that config |
| `BlobConfigOwnerChanged` | the config is re-parented to the file's owner |
| `HeadAdvanced` | the merged revision becomes the head |
| `RevisionRetired` | if the merge overflowed the window |

Or rejects:

```move
entry_file_draft::delete_draft(system, file, owner_pass, draft_index, clock, ctx)
```

| Event | |
|---|---|
| `DraftDeleted` | the draft leaves the queue |
| `RevisionRetired` with `released: false` | the config id is announced; the content stays with its writer |

Nothing transfers on rejection. The event exists precisely so the writer can find the config and
reclaim it. `clear_drafts(from_index, to_index)` does the same over a range the caller names.

---

## 5. Compacting, and releasing what it superseded

```move
let plan = entry_compaction::plan_compaction(system, new_quilt_config);
entry_compaction::supersede(&mut plan, old_config);      // once per config being replaced
entry_compaction::register_layout(system, new_quilt_config, plan, kind, generation,
                                  paths, content_hashes, clock, ctx);
```

| Event | |
|---|---|
| `LayoutRegistered` | the receipt: what the new layout holds, its root, and every config it supersedes |

`CompactionPlan` is a hot potato — no abilities — so a plan that is opened must be closed in the
same transaction. Every config in it must share the target's owner, term and mandate; `generation`
must exceed every generation superseded. `supersede` takes no `SystemConfig` and is the one entry
point with no version gate, because there is no system in the call to check.

**Registering a layout destroys nothing.** The superseded configs are exactly as renewable
afterwards as before, and the only consent signal is whether the owner subsequently withdraws them:

```move
entry_withdraw::self_withdraw_blobs(system, superseded_configs, ctx)
```

| Event, per config | |
|---|---|
| `BlobWithdrawn` | the config is destroyed and its blobs go to the address that held it |

That second step is owner-only and is not delegable. See [custody.md](custody.md).

---

## 6. Transferring a config

```move
entry_transfer::offer(system, config, recipient, ctx)     // BlobConfigOwnershipOffered
entry_transfer::accept(system, config, ctx)               // by the recipient
```

| Event on accept | |
|---|---|
| `BlobConfigOwnerChanged` | custody moved |
| `BlobConfigOwnershipAccepted` | and it moved by consent |

`cancel` raises `BlobConfigOwnershipOfferCancelled` and leaves custody where it is. So does any
other move of `owner`, which is why a consumer telling the two apart reads what accompanies the row
in the same transaction.

---

## 7. The project surface, end to end

Owner-signed:

```move
entry_file_project::open_project_holder(system, ctx)                    // ProjectHolderCreated
let project = entry_file_project::create_project(holder, system, ctx);  // ProjectCreated
entry_file_project::initialize_project_file(holder, project, system, owner, …);
entry_file_project::set_file_set_root(holder, project, root, system, ctx);
```

| Event | |
|---|---|
| `ProjectHolderCreated` | the account's authority root for its whole project surface |
| `ProjectCreated` | one project, committed to the empty file set |
| `BlobStored`, `InnerFileCreated`, `WriterPassMinted` | the database file, created through the same path as any other file |
| `ProjectDatabaseInitialised` | the project now names that file, and cannot name another |
| `ProjectFileSetRootChanged` | carrying `previous_root`, so the move stays auditable |

Every one of these has an `_as_operator` sibling, and the whole sequence can run with **no user
signature after registration**:

```move
entry_file_project::open_project_holder_as_operator(system, cap, owner, clock, ctx)
entry_file_project::create_project_as_operator(holder, system, cap, clock, ctx)
entry_file_project::initialize_project_file_as_operator(holder, project, system, cap, owner, …)
entry_file_project::set_file_set_root_as_operator(holder, project, root, system, cap, clock, ctx)
```

The holder's `admin` is the `owner` argument and never the sender: the credential decides that a
holder is created, not whose it is. `admin` is fixed at creation with no setter, so a holder rooted
on a rotating wallet would tie an account's whole project surface to a key the pool retires.

A second holder for the same account is refused by name (`EProjectHolderExists`), through the same
marker on `User` whichever form asked. Gated on `can_init_db`, checked against the `owner`'s
account.

---

## 8. Renewal — the one anybody can execute

```move
entry_renew::renew_blob(system, walrus_system, config, payment, ctx)
```

| Event | |
|---|---|
| `BlobRenewed` | per blob extended, with the WAL spent and the new end epoch |
| `RenewCycleSpent` | one cycle of the mandate consumed, and how many remain |
| `RenewSkipped` | nothing to do, with a `reason` code |

**No capability, no allowlist, no owner check.** The mandate is `epoch_set` and `cycle_limit` on the
config, and the executor pays. This is the call the whole design exists to make possible: if Warlot
disappears, the user, a competitor or a community bot keeps every blob alive with it.

A standing custody offer changes nothing here — renewal addresses the config, not its owner.
