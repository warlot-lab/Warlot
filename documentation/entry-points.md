# The entry surface

All 68 public functions in `sources/entry/`. Nothing below it is callable: every domain module keeps
its mutators `public(package)` and exposes them here, which is also why every signature on this page
is frozen at publish and almost nothing beneath it is.

The sections are shaped like their subjects rather than like each other. A sequence is written as a
sequence, a negotiation as states, a routing decision as a decision table, a single function as
prose. Where a surface genuinely is uniform — `entry_permission` — it is drawn as a grid, and that is
the exception rather than the template.

**Two things stated once and not repeated.**

*The version gate.* Every public function taking a `SystemConfig` asserts the stored version against
the package's before it does anything else, aborting `EWrongPackageVersion`. `migrate_version` does
not, because it is the call that clears that state. `supersede` and the six calls in `entry_upgrade`
take no `SystemConfig` at all, so there is nothing for them to check.
`scripts/check-events.sh` section 6 proves the coverage against `version_tests.move`, keying on the
*parameter* rather than on the presence of `assert_version` — a function that received the system and
stopped checking would drop out of the narrower rule's set silently.

*"Owner".* Everywhere below it means the `owner` or `admin` **field** on an object, not Sui object
ownership. See [objects.md](objects.md).

Refusals name the aborts a caller can reasonably hit. They are not exhaustive over every frame
beneath: a `&Coin` too small for a fee aborts inside the framework, and a delegation the sender does
not hold aborts in `user` rather than at the entry point that read it.

---

## `entry_admin` — one capability, two states, and the line between them

An `AdminCap` carries a state tag: **original** or **duplicate**. Twelve calls live here and every one
of them requires the original for *this* system, through `assert_original_cap_for`. The duplicate is
what a backend signs with, and it can do none of this.

That single byte carries the whole operator model, so the boundary is the subject of this section
rather than the list of calls.

### What the original can do, and the duplicate cannot

| | Calls | What it reaches |
|---|---|---|
| **The treasury** | `withdraw_system_wal`, `withdraw_system_coin<T>`, `add_coin_type<T>`, `remove_supported_coin<T>` | the vault's balances and its deposit allowlist |
| **The terms** | `update_cost`, `update_tier_table` | the four fees, the storage ladder and the horizon |
| **The lineage** | `mint_system` | builds the successor, shares it, and mints *its* original |
| **The gate** | `migrate_version` | raises a stale system to the package version |
| **The pool** | `mint_admin`, `enrol_operator`, `refresh_operator`, `retire_operator` | who may sign as an operator, and until when |

### What the duplicate can do, and the original cannot

Act as an operator credential. `operator::authorise` asserts the capability is a **duplicate**
(`ENotDuplicateCap`) and names this system (`ECapForAnotherSystem`), so the original is not an
operator and cannot be used as one.

The two halves are exact complements, and that is the design: the credential the backend signs with
cannot reach the treasury, mint a system or change a cost, and the root key stays out of the hot path.

### The calls, where they differ from the pattern

**`mint_system`** is the only one that changes the shape of the world rather than a value in it. It is
linear — an old system may name exactly one successor (`ESuccessorAlreadyMinted`) — so the chain never
forks and "the next system" is always a single answer. The successor opens selling what its
predecessor sold, tier table and horizon copied, because one that reset to nothing could not take an
upload until somebody remembered to configure it.

**`migrate_version` is deliberately not version-gated.** It asserts the opposite: that the system is
*behind* the package, so there is something to do (`EVersionNotOlder`). Gating it would leave a system
that could never be repaired. It is excused **by name** in `check-events.sh` section 6, with the
reason recorded there, rather than by a pattern that could quietly excuse something else.

**`enrol_operator` and `refresh_operator` are separate calls on purpose.** Enrolment refuses an id that
already holds a slot (`EAlreadyAnOperator`); a refresh refuses one that holds none (`ENotAnOperator`).
An enrolment that quietly became an extension would move a live key's deadline and change its bypass
bit while the admin believed they were onboarding a new one. Both refuse an expiry that is not in the
future (`EInvalidOperatorExpiry`), and enrolment refuses a seventeenth slot (`EOperatorSetFull`).

`enrol_operator` takes the capability's **id**, not the object. The capability is already in the
backend's hands by the time a slot is wanted, and requiring the admin to hold both would mean minting
and enrolling could never be separated. Nothing is trusted about the id as a result: `authorise`
re-checks at every use that what was presented is a duplicate naming this system.

**`retire_operator` cannot abort on a missing slot.** This is the call that pulls a leaked key, and one
that can abort is one that can fail inside the batch pulling it. Retiring an id that holds none leaves
the caller with the state they asked for, and the event is raised only when a slot was actually
dropped — so a no-op is visibly a no-op in the stream.

**`remove_supported_coin<T>` stops new deposits and nothing else.** Balances already held stay
withdrawable, because withdrawal never consults the allowlist. It does not abort on a type that was
never accepted, either — the removal is a no-op and announces nothing.

The two withdrawals abort for reasons that have nothing to do with the allowlist: `ENoBalanceFound`
when the vault holds none of that type, and `EInsufficientBalance` when it holds less than asked.

### What the original still cannot do

Destroy a user's content, pause anything, mint a writer pass, or act on a file. No entry point
anywhere takes a `BlobConfig` belonging to somebody else and consumes it. See
[refusals.md](refusals.md).

---

## `entry_register` — accounts

Four calls. Two of them are the same call with one boolean different.

```move
all_register_user_publicly(system, username, clock, ctx)
all_register_user_with_system_permission(system, username, clock, ctx)
```

Both create the `User`, attach it to the system under `ctx.sender()`, and transfer a `Registry` to
that address. The `all_` prefix marks a registration that creates every object a Warlot application
state needs rather than just the user record. Both refuse an address already registered here
(`EUserExist`), and the sender registers only themselves — there is no address argument.

The second additionally grants the **operator role** every bit it can hold, and adds
`OperatorRoleGranted` to the events. That grant names no address: it reaches whichever capability
holds a live slot at the moment of a call, so a backend key added, retired or rotated afterwards
inherits or loses it with no further write against this user. This is the ordinary path for an account
a backend will act for — consent given once at registration, narrowed later with
`replace_operator_role`.

A registration that opens with a full delegation **is** a delegation and is announced as one. Without
that event the only silent grant in the protocol would be the one made before the user has done
anything.

```move
update_username(system, registry, new_username, payment, ctx)
```

Charges `cost_to_update_name` into the system's vault. Refuses a registry belonging to a different
system (`ERegistryForAnotherSystem`); the coin is split for the fee, so a coin that does not cover it
aborts inside the framework.

```move
migrate_system(registry, current_system, next_system, coin, clock, ctx)
```

The user's own act, and the only call that gates on **two** systems' versions. It checks the registry
names the current system, that the user is registered there (`ENotRegisteredHere`) and not already in
the successor (`EAlreadyRegisteredThere`), takes `cost_to_migrate_system` into the **successor's**
vault (`EInsufficientPayment`), then moves the `User` object out of one system's dynamic fields into
the other's and repoints the `Registry`.

The half-migrated state cannot be observed, because both moves happen in the one transaction. And
almost nothing follows the account across: a `BlobConfig` names no system, an `InnerFile` names no
system, a `WriterPass` names a file and a `ProjectHolder` names an address. Only the account record
and the label move. See [upgrades.md](upgrades.md).

---

## `entry_permission` — the one genuinely symmetric surface

Six calls, and here a grid is the honest shape: two kinds of delegation, three verbs each, the same
rule in every cell.

| | Address-keyed grant | Operator role |
|---|---|---|
| **make** | `grant(system, owner, delegate, add_blob, inner_file, writer_pass, init_db, compact, set_root, ctx)`<br>refuses `EAlreadyDelegated` | `grant_operator_role(system, owner, add_blob, inner_file, init_db, compact, set_root, ctx)`<br>refuses `EOperatorRoleAlreadyGranted` |
| **change** | `replace_grant(…)`<br>refuses `ENotDelegated` | `replace_operator_role(…)`<br>refuses `EOperatorRoleNotGranted` |
| **withdraw** | `revoke(system, owner, delegate, ctx)`<br>refuses no missing delegation — revoking what was never granted is not an error | `revoke_operator_role(system, owner, ctx)`<br>refuses no missing role, same reason |

All six are gated on **the sender being the account owner** (`ENotAccountOwner`). A delegation is the
account's to give, and nothing else can give it — not an admin, not an operator, not a delegate
widening its own row.

**Making and changing are separate everywhere.** The bits are written wholesale, so a grant made
against an address that already held one would silently take away whatever the caller did not happen
to name — while reporting the same success as a first grant. Reaching for the blunt instrument cannot
quietly widen or narrow a delegation the owner meant to leave alone.

**Revocation removes the row rather than zeroing it**, so a revoked delegate is refused by the lookup
itself and no row survives that could be mistaken for a delegation. And it cannot abort: a revocation
that can fail is one that can fail at the moment it is most needed.

### The one asymmetry: five bits, not six

`grant_operator_role` and `replace_operator_role` take **five** bits. `create_writer_pass` is absent —
not taken and stored `false`, but absent from the signature, so no call in the package can express the
grant.

A pass binds to one address, and the whole point of the operator set is that authority follows the
capability slot rather than a wallet. Taking the bit and storing `false` would announce an authority
that does not exist. See [operators.md](operators.md).

### And they are ORed, never subtracted

`permission::effective_bits` reads both rows and unions them. An address grant works with no
capability at all and survives every change to the operator set; revoking the operator role does not
remove a bit the same address holds directly. To shut an address out completely, revoke both.

---

## `entry_wallet` — where the lookup is the authorisation

```move
deposit_coin(system, coin: &mut Coin<WAL>, amount, ctx): u64
withdraw_wal(system, amount, ctx)
withdraw_all_wal(system, ctx)
```

Three calls, and none of them takes an owner. The wallet is reached through the user record keyed by
`ctx.sender()`, so **the lookup is the authorisation**: no address can name another's wallet, and
there is no check to get wrong.

`deposit_coin` splits `amount` out of the caller's coin and returns the wallet's new WAL balance,
leaving the change where it was. It aborts `EInsufficientFunds` if the coin holds less than `amount`,
and `EUserNotFound` if the sender is not registered here.

The two withdrawals abort `ENoBalance` when the wallet has never taken a deposit of that type at all —
a wallet with no bank holds nothing, and the two absences answer the same way — and `withdraw_wal`
aborts `EInsufficientFunds` when it holds less than asked.

The storage underneath is multi-coin: one balance per type name, under a bank attached on the first
deposit. **The entry surface is WAL-only**, so the other types are reachable by nothing a client can
call.

---

## `entry_upload` — one act, two ways to be authorised

```move
foreign_blob_add(system, owner, cycle_end, epoch_set, blobs, clock, ctx)
foreign_blob_add_as_operator(system, admin_cap, owner, cycle_end, epoch_set, blobs, clock, ctx)
```

Takes blobs sourced outside the protocol into custody under `owner`, in **one config per call, not one
per blob**. A quilt is a single Walrus blob, so a quilt is adopted as one config and its mandate covers
the whole quilt — the only granularity Walrus offers, since a patch cannot be extended or deleted on
its own. Blobs adopted together share one mandate and are withdrawn in one call.

Refuses more than 100 blobs (`EBatchTooLarge`), none at all (`ENoBlobs`), a storage term the system
does not sell (`EInvalidTier`), and an unregistered `owner` (`EUserNotFound`). Storing under an address
that is not the sender needs `add_blob_to_address` on that address, checked three frames down in
`store::raw_store_blob` (`INVALIDACCESS`).

`cycle_end` is an `Option<u64>`: a count of renewal cycles, or `none` for a mandate with no limit,
renewed for as long as it is paid for. `some(0)` is the other end of the range — stored, never renewed
— which is why a count could never have expressed "no limit" and the field is an `Option` rather than
a sentinel.

`owner` is an address rather than a `&Registry`, and that is worth one paragraph because the same
shape recurs. A `Registry` is an owned object with no `store`, so only the address it names could ever
pass it — which meant a delegate could not adopt at all, and the operator sibling could not be executed
by anybody, since one transaction cannot take two owned objects belonging to two different addresses.
The registry also checked nothing that is not checked anyway.

### Why every operator sibling is a separate function

`Option<&AdminCap>` is not a type Move will accept, so a credential cannot be an optional argument.
Every `_as_operator` call in this package exists for that reason and no other: it authorises the
capability once at the top, then joins the same private helper as its owner-facing twin, carrying an
`OperatorAuth` — a `copy, drop` proof with no `store`, so nothing can keep one past the call.

The credential's own checks are the same four everywhere, in `operator::authorise`: it is a duplicate,
it names this system, it holds a slot, and the slot has not expired.

---

## `entry_renew` — the one anybody may call

```move
renew_blob(system, walrus_system, config, payment, ctx)
```

One function, and the whole design exists to make it possible.

**There is no capability, no allowlist and no owner check.** Any address may renew any config. The
mandate is `epoch_set` and `cycle_limit` on the config itself, set once by whoever created it, and
**the executor pays** out of the coin they hand in, keeping the change. If Warlot disappears, the
user, a competitor or a community bot keeps every blob alive without our cooperation.

The horizon is read from the config rather than taken from the caller. The term is what the owner
bought; letting a renewer name a different one would let a stranger decide how much storage the
owner's mandate is spent on.

It is a **sustained target, not a top-up.** Every renewal brings each blob back to
`current_epoch + epoch_set`, so a config settles into a steady state that many epochs ahead of wherever
the chain has got to.

Renewing many configs is one call per config inside a single programmable transaction block. The
transaction is the unit of batching, because Move cannot take a vector of mutable references.

### What it does, per call

The only abort Warlot itself raises here is `EInvalidAhead`, from a config whose term is zero — a term
that can never do work is refused outright rather than accepted as a silent no-op. Walrus's own
`extend_blob` runs beneath this and has its own failure modes. Everything else is announced rather
than refused:

| Outcome | Event | |
|---|---|---|
| the mandate is spent | `RenewSkipped`, reason `0` | announced, not aborted — a drained mandate is what an attacker is aiming for, so it is the outcome that must not be silent |
| a blob is already paid past the target | `RenewSkipped`, reason `1` | per blob |
| a blob's storage has already lapsed | `RenewSkipped`, reason `2` | per blob; an expired blob cannot be renewed |
| a blob was extended | `BlobRenewed` | per blob, with the WAL actually spent and the new end epoch |
| at least one blob moved | `RenewCycleSpent` | once, after the work |

**The cycle is charged after the extension, and only if at least one blob was actually extended.**
Charging it up front would make a call that does nothing indistinguishable from one that does work,
which would let any address exhaust another user's mandate for the price of gas.

The cost of each extension is measured as the coin's value either side of the call, because nothing
else knows it: the price is Walrus's, not the protocol's, and it varies with size and epochs bought.

The caller is recorded on every event this raises. Renewal being open to anyone makes "who paid to keep
my data alive" a thing the chain owes the owner an answer to.

A standing custody offer changes nothing here — renewal addresses the config, not its owner.

---

## `entry_withdraw` — the only way content leaves

```move
self_withdraw_blob(system, config, ctx)
self_withdraw_blobs(system, configs, ctx)
```

The config is taken **by value** and destroyed; its blobs are transferred to the address that held it.
Because the config is the only record of who holds what, deleting it is the whole operation — nothing
else has to be updated to match.

`ENotOwner` unless the sender owns it, checked **per config** in the batch form. Configs with different
owners can be handed in together, and each is refused or released on its own; hoisting the check would
add a rule the mechanism does not have.

The batch saves per-call overhead and **lifts no ceiling**: every config is still a shared-object
input, so Sui's input limit binds exactly as it did. What it makes practical is clearing a retired
wallet, which one config per transaction does not.

Not delegable, and there is no operator sibling. Withdrawal consumes the config, hands out the blobs,
and cannot be undone by the owner noticing afterwards — which is the test the whole permission model
applies. See [refusals.md](refusals.md).

---

## `entry_transfer` — a two-party negotiation with states

Custody arriving is a **responsibility**, not only a gift: the recipient becomes the address that pays
to keep the content alive. So nothing moves until they act, and the surface is a small state machine
rather than three independent calls.

```
                      ┌──────────────────────┐
      ┌──────────────▶│   no standing offer  │◀─────────────────┐
      │               └───────────┬──────────┘                  │
      │                           │                             │
      │              offer(recipient)                    cancel()
      │              sender = owner                      sender = owner
      │              recipient ≠ owner                   ENoStandingOffer if none
      │              → BlobConfigOwnershipOffered        → ...OfferCancelled
      │                           │                             │
      │                           ▼                             │
      │               ┌──────────────────────┐                  │
      │               │   offered to R       │──────────────────┘
      │               └───────────┬──────────┘
      │                           │  offer(R2) replaces it — there is no queue
      │                           │
      │              accept()
      │              sender = R, and R is registered
      │              → BlobConfigOwnerChanged + ...OwnershipAccepted
      │                           │
      │                           ▼
      │               ┌──────────────────────┐
      └───────────────│  owner = R, no offer │
   any other move of  └──────────────────────┘
   owner lands here too, voiding the offer
```

### The four refusals, and what each is protecting

| | Abort | |
|---|---|---|
| `offer` by anyone but the owner | `ENotOwner` | |
| `offer` to the current owner | `EOfferToSelf` | refused rather than absorbed: accepting would raise a custody change in which nothing changed hands, a row a consumer replaying the stream has to special-case |
| `accept` by anyone but the named recipient | `ENotTheOfferedRecipient` | |
| `accept` by an unregistered address | `ENotRegistered` | every constructor resolves a `User`, and this is the only path that moves a config *between* accounts, so it is the only place the "owner is always registered" invariant could be lost |
| `accept` or `cancel` with no offer standing | `ENoStandingOffer` | `cancel` refuses rather than passing silently: the owner is acting on a belief about the config's state, and a no-op would confirm a belief that may be wrong |

The registration check is on `accept` and **not** on `offer`, deliberately: offering to an address that
intends to register first is a legitimate flow.

### Two rules that are not visible in the calls

**A second offer replaces the first.** There is one custody to hand over, so a queue of candidates
would be a queue in which only the first to act mattered, and the owner would have no way to tell
which of their offers was still live.

**Any move of `owner` voids a standing offer**, however it moved, and announces
`BlobConfigOwnershipOfferCancelled`. That event therefore has two causes, and a consumer telling them
apart reads what accompanies the row in the same transaction. The rule is what makes the *other*
custody mechanism safe: a draft merge re-parents a config directly, and without it an offer the
writer had left open would survive the merge and let the address it named pull content out of the
owner's own history afterwards.

While an offer stands, nothing about renewal changes. `epoch_set` and `cycle_limit` are untouched and
renewal is permissionless anyway, so there is never a window where it is unclear who is paying.

---

## `entry_compaction` — a three-call sequence inside one transaction

Not three independent entry points. One operation, split because Move cannot take a vector of mutable
references and a compaction has to **read** every predecessor to refuse a cross-user or mixed-policy
one.

```move
// all four calls in one programmable transaction block
let plan = entry_compaction::plan_compaction(system, &new_quilt_config);
entry_compaction::supersede(&mut plan, &old_config_1);
entry_compaction::supersede(&mut plan, &old_config_2);
entry_compaction::register_layout(system, &mut new_quilt_config, plan,
                                  /* kind */ 1, /* generation */ 1,
                                  paths, content_hashes, clock, ctx);
```

### What holds it together

`CompactionPlan` has **no abilities at all** — not `store`, not `copy`, not `drop`. A transaction that
opens one and does not close it cannot finish, so it does not commit. Nothing pending is ever left on
chain, and there is no state to forge.

The two alternative shapes are both refused on purpose. Accumulating predecessors across transactions
would be pending state that has to be forgeable to be useful. Taking the predecessors by value would
let a compaction retire content whose owner never released it.

### What each call does

**`plan_compaction`** is permissionless, and has to be: it reads two public fields off a shared object
and returns a value that cannot be stored, transferred or dropped. Authority is checked where the
state changes. It settles the terms from the **target** — owner, `epoch_set`, `cycle_limit`,
`generation_floor` — so the caller chooses which configs to name, never what counts as matching.

**`supersede`** narrows the plan and never widens it. It is the one entry point that takes no
`SystemConfig`, so it has no version gate — there is no system in the call to check.

| Refuses | |
|---|---|
| `ESupersedesItself` | a compaction cannot supersede its own target |
| `ETooManySuperseded` | more than 666 |
| `ESupersededNotAscending` | predecessors must arrive in ascending id order — which keeps the repeat check to one comparison instead of a scan, and leaves the root's own sort with nothing to do |
| `ECrossUserQuilt` | deletion is whole-quilt: in a quilt holding two users' files, neither can delete without destroying the other's, so "only the user can delete" is not awkward across users, it is impossible |
| `EPolicyNotHomogeneous` | renewal is whole-quilt too, so one `epoch_set` and one mandate have to serve every file in the quilt permanently |

**`register_layout`** writes the receipt and is where authority is checked: `can_compact` on the
**target's owner**, or the sender being that owner. `register_layout_as_operator` is the same call
satisfying it through the operator role, and it is deliberately the widest thing an operator may do to
stored content — and still additive.

| Refuses | |
|---|---|
| `ENotTheTarget` | the plan was opened against a different config |
| `EOwnerMoved` | a plan and its target are separate transaction inputs, so a call sequence could re-parent the config in between. A public transfer path makes that check more load-bearing, and it was already there |
| `ELayoutAlreadyRegistered` | write-once; a new generation is a new config |
| `ENothingSuperseded` | |
| `EGenerationNotAdvanced` | the generation must exceed every generation superseded, which makes the lineage a strict order rather than a set of claims |
| `EMismatchedEntries` | every path needs exactly one content hash |
| `EPathsNotAscending`, and the path rules | see [commitments.md](commitments.md) |
| `EQuiltIsOneBlob` | a quilt is one Walrus blob however many patches it carries, so `kind` is checked against the custody rather than believed |

Both commitments are computed here from what the contract read — the file-set root over the entries
submitted, the superseded root over the ids `supersede` actually saw. Neither is an argument, so
neither can be asserted, and a layout that does not match what was submitted cannot be registered.
That is what makes it a receipt rather than a claim.

### And then nothing happens

**Registering a layout destroys nothing.** It retires nothing and re-parents nothing. The superseded
configs are exactly as renewable afterwards as before, and the only consent signal is whether the
owner subsequently calls `self_withdraw_blobs` on them — which is owner-only and not delegable.

There is no accept step and no pending flag, and their absence is the point: an "accepted" boolean
would be one more thing Warlot could set on the user's behalf.

**The chain does not verify a compaction and cannot.** A quilt's patch index lives inside the quilt and
its patch ids are derived off chain from the whole quilt's composition, so Move has no way to ask
whether a file is inside a blob. What the chain does is narrower and is the part that has to be
trustworthy: it refuses a heterogeneous set, derives both commitments from state it read, and writes
the receipt once.

---

## `entry_file_create` — two calls; the difference is who chooses the terms

```move
create_file(system, owner, writers_length, track_back_length, blobs, epoch_set, cycle_end,
            clock, commit, draft_epoch_duration,
            operators_allowed, operators_may_bypass_draft, operators_may_draft,
            should_include_pass, pass_duration, ctx): ID

create_file_as_operator(system, admin_cap, owner, writers_length, track_back_length, blobs,
                        epoch_set, cycle_end, clock, commit, draft_epoch_duration, ctx): ID
```

Both store `blobs` as the file's first revision — so a file never exists without content — share the
file, and mint the owner a non-decaying, draft-bypassing pass. Both need `add_blob_to_address` **and**
`create_inner_file` on `owner`, or the sender being `owner`.

Refuses a window depth outside 1 to 8 (`INVALIDTRACKBACKLENGTH`), a policy that admits operators while
opening neither route (`EPolicyOpensNoRoute`), no blobs (`ENoBlobs`), a term the system does not sell
(`EInvalidTier`), and an unregistered `owner` (`EUserNotFound`).

`cycle_end` is an `Option<u64>` and it is fixed here for the life of the file: every later revision is
bought on the same mandate, and there is no setter. `none` is a mandate with no limit.

### What the operator form does not take

**No policy.** The file is born admitting its creator on both routes. `create_inner_file` means *"make
me a file you will maintain"*, and one the operator cannot write to is not what that grant asked for.
Letting the call carry the three bits would make it the one place a file's terms for operators were
chosen by an operator — the opposite of what `operators_allowed` says it is for. The owner narrows it
afterwards with `set_operator_policy`, which is the escape hatch rather than the starting point.

**No pass.** The credential is what authorises an operator's write; a pass minted to a rotating key
would have to be re-minted per file per key, which is the cost the whole operator path exists to
remove. `should_include_pass` is hardcoded `false`.

On the owner-facing call, `should_include_pass` mints the **caller** a second pass when they are not the
owner. That branch needs `create_writer_pass` as well, and asserts `pass_duration` is strictly in the
future (`EInvalidPassDuration`) — a delegate acting on someone else's behalf is given authority with an
end date, and the future check is also what keeps the value away from the sentinel that marks a pass
non-decaying.

---

## `entry_file_write` — one routing decision

Three calls, and what matters is not which one you call but where the write lands: in the file's
history, or in its draft queue. The routing is a decision over a four-state policy, and it decides
**who pays for the content** as well as where it goes.

### The policy: three bits, four states

Set by the file's owner at creation or with `set_operator_policy`, and gated on the **sender**, never
on a pass — a pass that could flip these would let an operator that had been shut out re-admit itself.

| `operators_allowed` | `..._may_bypass_draft` | `operators_may_draft` | The file's terms |
|---|---|---|---|
| `false` | — | — | the operator does not write here |
| `true` | `true` | `false` | **direct only** — a request to queue aborts |
| `true` | `false` | `true` | **queue only** — a direct write is routed into the queue |
| `true` | `true` | `true` | **either**, and the operator picks with `to_draft` |
| `true` | `false` | `false` | **refused**, at creation and at `set_operator_policy` |

The fifth spelling means exactly what `operators_allowed: false` means, and a state with two spellings
is one a reader gets wrong. It is refused rather than normalised, because silently rewriting an
owner's terms would announce a policy they did not set.

The third bit exists because two could not say what an owner needed to say. With only the first two,
`allowed: true, bypass: false` did not refuse a direct write — it **silently redirected it into the
draft queue**. So an owner clearing the bypass changed *where* the operator's output went rather than
whether it arrived, and under a rotating credential that output landed in per-wallet custody.

### The routing, for an operator

`write_as_operator(file, admin_cap, to_draft, issue, clock, system, blobs, commit, evicted, ctx)`

```
may_bypass  =  the slot's bypass bit  AND  the file's operators_may_bypass_draft
```

The conjunction is the owner winning. An admin granting bypass on a slot cannot override a file whose
owner refused it here.

| `to_draft` | condition | outcome |
|---|---|---|
| `true` | `operators_may_draft` | **queued** |
| `true` | not `operators_may_draft` | abort `EOperatorDraftsRefused` |
| `false` | `may_bypass` | **straight into history** |
| `false` | not `may_bypass`, `operators_may_draft` | **queued** — the fallback the owner opened |
| `false` | not `may_bypass`, no drafts | abort `EOperatorSlotCannotBypass` |

`EOperatorSlotCannotBypass` names a reachable state that is easy to misread as impossible: a file may
legally be direct-only, and an operator whose *slot* carries no bypass then has neither route open even
though the file's own bits look ordinary. It is named separately from `EOperatorDraftsRefused` because
the two need different fixes — one is the owner's policy, the other is a slot to refresh.

### The routing, for a pass

`write_(file, writer_pass, to_draft, issue, clock, system, blobs, commit, evicted, ctx)`

Different rules, deliberately. **A pass holder may always propose**, and skipping the queue needs the
pass's own `admin_privilege` or the call is refused outright (`ACCESSDENIED`). Neither half consults the
file's operator bits, which are about operators and say nothing about a pass minted on this file.

`force_write_innerfile(file, writer_pass, clock, system, blobs, commit, evicted, ctx)` is the owner's
own direct route: any valid pass for the file plus `inner_file.owner() == ctx.sender()`
(`INVALIDACCESS`). It does not consult `admin_privilege` and cannot reach `ACCESSDENIED` at all. It is
owner-only, so it has no operator sibling — the owner check is strictly stronger than any credential
could be.

### Where the content lands, and who pays

| Route | Config's owner | Grant asked of the file's owner |
|---|---|---|
| into history | the **file's owner** | `add_blob_to_address` |
| into the queue | **`ctx.sender()`** | none |

A queued write is custodied by whoever pushed it, so it stores under the sender's own address and asks
the file's owner for nothing. Two consequences:

- **A signing key whose writes can be queued must itself be a registered user**, because
  `raw_store_blob` resolves it — an unregistered sender aborts `EUserNotFound`. A key that always
  bypasses never stores under its own address and needs no registration at all.
- `write_as_operator` checks `add_blob_to_address` on the owner in **exactly** the case the routing
  sends to history, and names the refusal `ENoAddBlobGrant` — the same denial `store` would give three
  frames down, moved to where the caller can act on it. `store`'s version is shared by every delegated
  path and cannot say which grant was missing.

### The eviction rule, on every write

The rollback window holds `track_back_length` revisions. The write that overflows it pushes one out,
and that revision is the last on-chain reference to content that is stored and being paid for — so the
caller has to say what becomes of it.

| | |
|---|---|
| the window still has room | pass `evicted: vector[]`. Passing a config aborts `EUnexpectedConfig` |
| the window is full | pass exactly the displaced revision's `BlobConfig`. Omitting it aborts `EEvictedConfigRequired`; passing the wrong one aborts `EWrongConfig` |
| the displaced revision is still the file's **fallback** | pass nothing. The file has given up the revision, not the state it can roll back to, so the content stays where it is |
| a queued write | pass nothing. A draft displaces nothing, so it can retire nothing |

A config arriving where nothing is retired cannot simply be ignored: it has no `drop`, so the
alternatives are to consume it — destroying content the caller never asked to destroy — or to refuse
the call.

**It is reconstructible from the stream alone.** `HeadAdvanced` carries `blob_config_id` and
`window_depth`, and the window is newest-first, so a FIFO of depth `track_back_length` fed from the
stream yields the config to pass.

### Everything all three refuse

From `verify_pass` or `verify_operator`: a pass for another file (`INVALIDPASS`), a decayed pass
(`DECAYEXCEEDED`), a denied writer address (`INVALIDWRITER`), a revoked credential id
(`EPassRevoked`), and for an operator a file that admits none (`EOperatorsRefused`). From the store
beneath: `ENoBlobs` and `EUserNotFound` where the address being stored for is not registered on
**this** system — the file's owner for a write into history, the sender for a queued one. From the
queue: `EDraftLimitReached` once the file holds as many open drafts as `writers_length` allows.

**A write cannot abort `EInvalidTier`**, and that is deliberate. A file's `epoch_set` is fixed at
creation and has no setter, so re-checking it against the live tier table on every revision meant
that retuning the ladder froze every existing file bought on a dropped term — permanently, with no
action available to the owner, who could not move the file to a term still sold. The term is now
validated where it is *bought*: `create_file` and its three siblings, and `foreign_blob_add` and its
operator sibling. A revision is not a purchase; it is the system honouring a term it already sold.

---

## `entry_file_draft` — resolving a proposal

Three calls, one gate: the sender is the **file's owner** (`INVALIDACCESS`) *and* holds a valid pass.
No operator siblings, and none is possible — a credential that could satisfy the owner check would be
the owner.

What distinguishes them is what happens to the proposal's config, which the writer still owns.

```move
merge_draft_into_file(system, file, owner_pass, draft_config, draft_index, merge_latest, evicted, clock, ctx)
```

**Accepts.** Re-parents `draft_config` to the file's owner in the same transaction that accepts the
content, then advances the head under the eviction rules above. An approval that left the content
custodied and funded by the proposer would not be an approval: the owner's authoritative history would
depend on the writer's mandate, and the writer could withdraw it back out again.

`merge_latest` ignores `draft_index` and takes the most recently pinned draft — the highest index ever
assigned, not the highest still present, so it aborts rather than reaching further back if that draft
has already been resolved. Refuses `EWrongDraftConfig` if the config handed in is not the one the
merged draft names, `ENoDraftQueue` on a file that has never held a draft, and `INVALIDDRAFTINDEX` or
`ENoDraftPinned` on an index that names nothing.

```move
delete_draft(system, file, owner_pass, draft_index, clock, ctx)
clear_drafts(system, file, owner_pass, from_index, to_index, clock, ctx)
```

**Rejects.** Nothing transfers. The config stays with the writer who proposed it, along with any offer
they had made on it — it was theirs and always was. `RevisionRetired` fires with `released: false`,
naming the config precisely so the writer can find it and reclaim it.

Automatically transferring it to the file's owner was considered and refused: the owner *rejected* it,
and pushing custody onto them would make saying no cost them storage.

`clear_drafts` takes a caller-named range, so one call costs what the caller asked it to cost, and
refuses `from >= to` (`EInvalidDraftRange`). The previous form walked every index the file had ever
issued — which meant a file that had accumulated enough drafts could never clear them again, and those
drafts were then stuck for good, since clearing was the only way out.

---

## `entry_file_fallback` — the recovery pair

```move
set_root_change(system, file, writer_pass, commit, config, clock, ctx)
remove_root_change(system, file, writer_pass, clock, ctx)
```

Its own module rather than two more entry points among the writes, because it is half of one
mechanism: revoking a credential stops the damage, and the fallback is the state the owner returns to
afterwards. Neither works without the other.

Both are owner-only (`INVALIDACCESS`) and take a valid pass.

`set_root_change` names the config **by the object, not by its id**, and refuses one the file's owner
does not hold (`ENotOwnersConfig`). A fallback is the state the owner intends to return to; one that
named somebody else's content is a fallback that can be withdrawn out from under them. Setting a
second fallback discards the first as a revision — the content it named is untouched.

`remove_root_change` leaves the content alone. It is the file owner's already, it is a shared object
they can reach by id, and withdrawal is the one call that releases it — so the removal announces the
config and stops there rather than deciding on the owner's behalf that the content is finished with.

A revision that is *also* the fallback survives leaving the rollback window, and takes no `evicted`
config with it. See the eviction rule above.

---

## `entry_file_access` — four different instruments

Seven calls, and they are not one kind of thing. All seven are gated on the sender being the file's
owner (`ENotFileOwner`) — **on the sender and never on a pass**, because a pass that could flip these
would let a delegate re-admit itself.

### 1. The terms — `set_operator_policy`

The one call that undoes what `create_file_as_operator` opens. Takes all three bits together, because
they are one statement about one file, and refuses the spelling that opens no route
(`EPolicyOpensNoRoute`). See the matrix above.

### 2. Denying an address — `deny_writer`, `redeny_writer`, `remove_deny_writer`

Refuses an address whatever credential it presents. A period of `0` denies indefinitely; anything else
must be in the future (`INVALIDTIME`).

The make-versus-change rule again: `deny_writer` refuses a writer already denied (`EAlreadyDenied`),
`redeny_writer` refuses one holding none (`ENotDenied`), so reaching for the blunt instrument cannot
quietly shorten a denial the owner meant to leave alone.

`redeny_writer` also refuses a file with **no deny list at all** (`ENotDenied`) rather than attaching
one to hold the change. `remove_deny_writer` passes silently in the same situation — a file that has
never denied anybody denies this writer too, so there is nothing to lift. Only the three calls that
*record* something can attach the list, so a file cannot be given one by somebody asking it to forget a
denial.

### 3. Revoking a credential — `revoke_pass`, `revoke_passes`

Refuses one credential whoever presents it. **There is no unrevoke**: a pass is revoked because it is in
the wrong hands, and an unrevoke would hand whoever holds it a second chance. The owner mints a
replacement instead.

This exists because a pass is an owned object living in its holder's account — the file's owner cannot
reach it and cannot destroy it. The record kept on the file is the whole of the mechanism: the pass
survives in the delegate's account and stops being accepted.

The record is keyed by `ID` and **blind to what the id names**, so the same call refuses an operator's
admin capability on this one file, without waiting for the admin to retire its slot everywhere.

`revoke_passes` attaches the list once for the whole batch rather than once per id, and an id already
refused is passed over — so resubmitting a list you are unsure of is not an error. An owner who has
decided a delegate is finished usually has more than one id to refuse, and doing that one transaction
at a time leaves a window in which some of them still write.

### 4. Minting a pass — `create_pass`

```move
create_pass(system, file, writer, duration, admin_pass, clock, ctx)
```

`duration` must be strictly in the future (`EInvalidPassDuration`), the same rule the creation path
holds. `0` is the sentinel for a pass the system never decays, so the check is also what keeps an
unset field from minting permanent write authority.

An **admin** pass is refused unless `writer` may already store blobs under the file's owner
(`ENoAddBlobGrant`), on the strength of an address-keyed grant alone — deliberately blind to the
operator role, because a pass is minted to an address and the role names none. Such a pass writes
straight into history, and the store underneath checks `add_blob` as well, so one minted without it
fails at its first use and says nothing about why at the mint. Failing here is legible.

It is a refusal and **never an auto-grant**. Conferring `add_blob` on the recipient would widen a
delegation past what the caller asked for, so the order is load-bearing: grant `add_blob`, then mint
the pass.

A **draft-only** pass is refused nothing, because a queued write is custodied by whoever pushed it and
stores under the sender's own address. Requiring a grant on the owner's account for that pass would
hand a draft-only collaborator authority to store under the owner's address — strictly more than the
pass they are being given can use.

`duration` is passed through unchecked, and **`0` is the sentinel for a pass the system does not
decay**. Unlike the delegated pass minted at file creation, which must expire in the future, an owner
minting on their own file may mint a permanent one.

There is no operator sibling, and the refusal is structural rather than an omission. See
[operators.md](operators.md).

---

## `entry_file_project` — every call in pairs

Eight calls, four operations. Every one has an `_as_operator` sibling, so the whole project surface can
run with **no user signature after registration**.

| Operation | Owner form | Operator form | Gated on |
|---|---|---|---|
| open the holder | `open_project_holder` | `open_project_holder_as_operator` | the sender / `can_init_db` on `owner` |
| mint a project | `create_project` | `create_project_as_operator` | `can_init_db` on the holder's `admin` |
| move the root | `set_file_set_root` | `set_file_set_root_as_operator` | **`can_set_root`** on the holder's `admin` |
| name the database | `initialize_project_file` | `initialize_project_file_as_operator` | `can_init_db`, plus everything file creation needs |

Every permission check in the package lives at this layer, because `project_object` cannot import
`identity` without reaching upward through the dependency ladder. So each call resolves the account
from the holder's `admin`, tests the sender's grant against **that** account, and hands the same
address down to the mutator, which re-asserts `admin == owner` (`INVALIDACCESS`).

### The two things that carry this section

**`admin` is the `owner` argument and never the sender.** The credential decides that a holder is
created, not whose it is. `admin` is fixed at creation with no setter, so a holder rooted on a
rotating wallet would tie an account's whole project surface to a key the pool retires.

Note the asymmetry in the first row: the owner-facing `open_project_holder` opens the sender's own and
takes no address at all, while the operator form opens `owner`'s. Creating the authority root and
creating the projects under it are the same grant, and an operator that may do the second has no reason
to be stopped at the first.

**`can_set_root` is a bit of its own, and this is why.** Initialising a database and writing a quilt are
additive; moving a root **overwrites** the previous commitment in place. Withdrawing this bit alone
freezes what the account's projects claim at their last honest value while leaving storing, file
creation, database initialisation and compaction running. Folding it into `can_init_db` would have made
revocation coarser than you need in exactly the moment you need precision. See
[permissions.md](permissions.md).

### The refusals

| | |
|---|---|
| `EProjectHolderExists` | a second holder for one account, whichever form asked — through the marker on `User` |
| `INVALIDACCESS` | from `permission` for a missing bit, and from `project_object` for a holder that is not this account's |
| `ENoSuchProject` | an id this holder does not hold |
| `EInvalidRootLength` | a root that is not exactly 32 bytes |
| `DBEXIST` | a project names its database once and cannot name another — the one irreversible thing a project record does |

`initialize_project_file` creates the file through the same path as any other, so it also carries every
refusal `create_file` does. Its operator form takes no policy either, for the same reason: `can_init_db`
is a grant to build the account's database, and a database the operator cannot write is not one.

---

## `entry_upgrade` — the package's own code

Six calls, and the only surface in the protocol that acts on the package rather than on anything
stored in it. Every one of them needs the **original** `AdminCap` for the system the authority names,
through the same `assert_original_cap_for` the treasury and the operator set go through. A duplicate
is refused, and so is an original minted for another system.

```move
take_custody(cap, admin_cap, ctx)
authorise_upgrade(authority, admin_cap, digest, ctx): UpgradeTicket
commit_upgrade(authority, admin_cap, receipt, ctx)
restrict_to_additive(authority, admin_cap, ctx)
restrict_to_dep_only(authority, admin_cap, ctx)
make_immutable(authority, admin_cap, ctx)
```

**Nothing here takes a `SystemConfig`, and nothing here asserts the version.** It is the one exception
besides `migrate_version`, and it is the same exception: an upgrade is the repair, and a build that
broke migration would otherwise have taken away the only lever that could fix it. The full argument,
and the shape of the three-command upgrade transaction, is in [upgrades.md](upgrades.md) §2.

`authorise_upgrade` returns an `UpgradeTicket`, so it cannot be an `entry` function and cannot be
called on its own. The ticket has no abilities: a transaction that issues one and does not spend it in
the same transaction's `Upgrade` command does not commit at all.

### The refusals

| | |
|---|---|
| `ENotOriginalCap` | a duplicate capability, including a live operator credential |
| `ECapForAnotherSystem` | an original minted for a different system |
| `ETooPermissive` | from `sui::package`, for a ratchet asked to move the loose way |
| `EAlreadyAuthorized` | from `sui::package`, for a second ticket while one is outstanding |

There is no refusal for "this capability governs another package". The framework exposes no way to
check it that keeps working past the first upgrade, so the ids are announced in
`UpgradeAuthorityCreated` and recorded in [deployment.md](deployment.md) instead.
