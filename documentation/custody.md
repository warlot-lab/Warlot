# Custody

`BlobConfig.owner` is the single field that decides who pays to keep content alive and who may
withdraw it. Everything below is about how that field gets its value and how it changes.

Custody is a **field**, not Sui object ownership. A `BlobConfig` is a shared object, so moving
custody is a write rather than a transfer, and the config stays reachable by everybody — which is
what keeps renewal permissionless while withdrawal stays exclusive. The object itself is described in
[objects.md](objects.md).

## Who owns a config, on every path that creates one

Every config in existence is created by `store::raw_store_blob`, which resolves
`user::get_user(system, owner)` before it wraps anything. So **every config's owner is a registered
account**, always, and there is exactly one place that invariant could be established.

| Path | Owner of the new config | Whose grant is asked for |
|---|---|---|
| `foreign_blob_add(system, owner, …)` | `owner` | `add_blob_to_address` on `owner`, unless sender is `owner` |
| `foreign_blob_add_as_operator` | `owner` | the same, via the operator role |
| `create_file` / `create_file_as_operator` | the file's `owner` | `add_blob_to_address` + `create_inner_file` |
| `initialize_project_file[_as_operator]` | the file's `owner` | the same, plus `can_init_db` |
| `force_write_innerfile` | the file's `owner` | owner-only call |
| `write_` / `write_as_operator`, **into history** | the file's `owner` | `add_blob_to_address` on the owner |
| `write_` / `write_as_operator`, **into the draft queue** | **`ctx.sender()`** | none on the owner |
| compaction's new quilt | whoever stored it, by one of the rows above | as that row |

### The draft row is the one that surprises people

A queued write stores under the **sender**, not the file's owner. That is deliberate: a draft is a
proposal, it costs the file's owner nothing, and its content stays the proposer's until the owner
accepts it. It is also why `write_as_operator` asks for `add_blob_to_address` only on the
non-queued branch — for a queued write the sender *is* the owner of the store, so the check passes
trivially and asks the file's owner for nothing.

Two operational consequences:

- **A signing key whose writes can be queued must itself be a registered user**, because
  `raw_store_blob` resolves it — an unregistered sender aborts `EUserNotFound` on a call that looks
  nothing to do with registration. A key that always bypasses never stores under its own address and
  needs no registration at all.
- **A rotating wallet must have its owned configs drained before it is retired from the pool.** A
  rejected draft stays with the writer who proposed it, and only that address can withdraw it. This
  is a runbook item for the backend, not something the contract solves — and an owner who wants to
  avoid it entirely sets `operators_may_draft: false`.

## How custody moves

There are exactly two mechanisms, and they are different acts rather than one with a special case.

### Offer and accept — a negotiated handover

```move
entry_transfer::offer(system, config, recipient, ctx)   // sender must be the current owner
entry_transfer::accept(system, config, ctx)             // sender must be the named recipient
entry_transfer::cancel(system, config, ctx)             // sender must be the current owner
```

Custody arriving is a **responsibility**, not only a gift: the recipient becomes the address that
pays to keep the content alive. So nothing moves until they act. That closes the
push-content-at-a-stranger vector by construction, with no inbound quota, byte budget or per-user
policy — none of which are needed once the move requires the recipient to act.

The states, the transitions and the four refusals are drawn in
[entry-points.md](entry-points.md). What matters here is what each one means for custody:

- A second offer **replaces** the first. There is one custody to hand over, so a queue of candidates
  would be a queue in which only the first to act mattered.
- `offer` refuses a recipient equal to the current owner (`EOfferToSelf`) — accepting would raise a
  custody change in which nothing changed hands.
- `accept` refuses an **unregistered** recipient. Every constructor resolves a `User`, and this is
  the only path that moves a config between accounts, so it is the only place the "owner is always
  registered" invariant could be lost. The check is on `accept` and not on `offer` deliberately:
  offering to an address that intends to register first is a legitimate flow.
- **Any move of `owner` voids a standing offer**, however it moved, and announces
  `BlobConfigOwnershipOfferCancelled`. That event therefore has two causes; a consumer that wants to
  tell them apart reads what accompanies the row in the same transaction.
- While an offer stands, **nothing about renewal changes**. `epoch_set` and `cycle_limit` are
  untouched and renewal is permissionless anyway, so there is never a window where it is unclear who
  is paying.

### Merge — a unilateral taking

`merge_draft_into_file` re-parents the draft's config to the file's owner directly, in the same
transaction that accepts the content. An approval that left the content custodied and funded by the
proposer would not be an approval: the owner's authoritative history would depend on the writer's
mandate, and the writer could withdraw it back out again.

This is **not** an offer/accept in disguise, and it deliberately is not built as one:

| | offer / accept | merge |
|---|---|---|
| Shape | negotiated, two parties each act | unilateral taking by the file owner |
| Prior claim | neither party has one | the draft is pinned to the owner's own file |
| Writer's consent | given at accept time, revocable until then | given at `pin_draft`, already spent |

Pinning a draft **is** the offer — it is the writer's act of proposing content into someone else's
file, and it is complete on its own. Requiring a second, separately revocable offer would let the
writer withdraw the consent the first act settled, and would hand them a veto: pin, re-offer the
config elsewhere, and the owner's accept then fails its `sender == pending_owner` check, repeatably.

The offer-voiding rule above is what makes the direct re-parent safe. A writer may offer their draft
config while it is still a proposal; without that rule the offer would survive the merge and the
address it named could pull content out of the owner's own history afterwards.

**A rejected draft stays with its writer**, and any offer they made on it survives the rejection.
The config is theirs and always was. Automatically transferring it to the file owner was considered
and refused: the owner *rejected* it, and pushing custody onto them would make saying no cost them
storage.

## How content leaves

```move
entry_withdraw::self_withdraw_blob(system, config, ctx)    // one config
entry_withdraw::self_withdraw_blobs(system, configs, ctx)  // as many as a transaction can carry
```

The config is taken **by value** and destroyed; its blobs are transferred to the address that held
it. Because the config is the only record of who holds what, nothing else has to be updated to
match. Ownership is checked per config, so configs with different owners can be handed in together
and each is refused or released on its own.

`eviction::release` is the other exit: a revision leaving the rollback window hands its blobs back
to the config's **existing** owner and destroys the config. It is returning content to whoever
already held it, never a new obligation on anyone.

Every exit runs through one private `destroy`, so a consumer replaying the stream sees the row
disappear however the config was consumed. A replay that only ever adds reconstructs a state that
never existed.

## Why deletion is not delegable

**There is no `can_delete` bit, and there will not be one.** Nothing in the six bits lets a delegate
destroy content, and no operator path reaches a withdrawal.

The reasoning is the same test the codebase applies everywhere: `can_compact` is delegable *because
writing a new quilt is additive* — it destroys nothing and supersedes nothing until the owner acts.
Withdrawal is the opposite. It consumes the config, hands out the blobs, and cannot be undone by the
owner noticing afterwards.

So compaction is split down that line. A delegate may do the additive half — write the new quilt,
register the layout, record what it supersedes — and the destructive half stays with the owner:
only they can withdraw the superseded configs, and until they do, the old content is exactly as
renewable as it was. The layout is a **receipt** the owner checks before deleting anything, which is
also why it is write-once. A layout that could be replaced would be a receipt Warlot could rewrite
after the fact.

`compaction::register` re-checks `blob_config::owner(target) == owner` and aborts `EOwnerMoved`,
because a plan and its target are separate transaction inputs and a call sequence could re-parent
the config in between. A public transfer path makes that check more load-bearing, and it was already
there.
