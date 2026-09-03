# Upgrades, versioning and migration

What a package upgrade may change, what it may not, and what to do when the change you need falls
on the wrong side of that line.

Read this before planning a change. The boundary below is why the whole `can_set_root` /
`Project` layout / `pending_owner` / `operators_may_draft` window had to land before the first
mainnet publish rather than after it.

---

## 1. The boundary

Sui checks an upgrade for **layout compatibility** before it accepts it. The check is on the
package's public surface and its stored types, not on behaviour.

### An upgrade may change

| | Example in this package |
|---|---|
| Any function body | rewriting the routing in `entry_file_write::write_core` |
| A private constant | raising `operator::MAX_OPERATORS` from 16 |
| An error message | the text of any `#[error]` constant |
| A new public function | adding `entry_file_project::open_project_holder_as_operator` |
| A new module | adding a domain module, or a new `sources/events/` module |
| A new event struct | events are emitted, never stored, so they are not layout |
| A new `#[error]` constant | error constants are not part of the stored layout |

The rule of thumb: anything the chain does not have to read back out of an existing object.

### An upgrade may not change

| | Why |
|---|---|
| Adding a struct field | Every stored instance would be missing it |
| Removing a struct field | Every stored instance would carry a field the type no longer has |
| Reordering struct fields | Layout is positional |
| Changing a field's type | Same |
| Changing a public function's signature | Callers compiled against the old one would break |
| Removing a public function | Same |
| Changing a struct's abilities | `key`, `store`, `copy`, `drop` are part of the type |
| Moving a value between a `dynamic_field` and a `dynamic_object_field` | Different storage shape, same name |

A `public(package)` function is not part of the public surface, so its signature may change freely.
That is one reason the domain modules keep their mutators `public(package)` and expose them through
`entry`, and it is worth preserving: every signature in `sources/entry/` is frozen at publish, and
almost nothing below it is.

### The two that catch people

**A field cannot be added even if nothing reads it yet.** This is the whole reason
`operators_may_draft` on `InnerFile` and `pending_owner` on `BlobConfig` are pre-mainnet work.
Neither is expensive; both become a new package plus a migration of every user's state the moment
the package is live.

**A public signature cannot gain a parameter.** `entry_file_access::set_operator_policy` taking a
third bit, and `entry_file_create::create_file_as_operator` losing two, are both upgrade-incompatible
changes to a published surface. They are free now and a migration later.

---

## 2. The version gate

`sources/system/version.move` declares one constant:

```move
const VERSION: u64 = 1;
```

Every `SystemConfig` stores the version it was last raised to. Every public entry point that takes
a `SystemConfig` calls `assert_version()` before it does anything else, and aborts
`EWrongPackageVersion` if the stored version is not the package's.

So after an upgrade the whole surface is closed until an admin reopens it. That is deliberate: an
upgrade that changed a function body while a system still held state written by the old body is
exactly the window a half-applied change is dangerous in, and the gate is what makes it impossible
to transact through.

**`admin::migrate_version` is the one entry point with no gate**, and it must stay that way — it is
the call that raises a stale system to the package version, so gating it would leave a system that
could never be repaired. It requires the **original** capability for that system.

```
publish upgrade  ──►  every entry point aborts EWrongPackageVersion
                 ──►  admin calls migrate_version(cap, system)
                 ──►  surface reopens at the new version
```

`scripts/check-events.sh` section 6 enforces the charter: every `public fun` in `sources/entry/`
that takes a `SystemConfig` must have a matching `gate_<name>` test in `version_tests.move`,
`migrate_version` excepted by name. The rule keys on the parameter rather than on the presence of
`assert_version` deliberately — a function that received the system and then stopped checking would
drop out of the narrower rule's set silently, which is the regression worth catching.

---

## 3. When a struct must change: the system chain

An upgrade cannot change a struct. What the protocol does instead is **build a new system beside
the old one and let users walk across**.

### The three calls

```
mint_system(cap, old_system, …)      admin, original cap    creates the successor, shares it,
                                                            and mints its own original cap
migrate_system(registry, current,    the user               moves their User record and their
              next, coin, clock)                            Registry into the successor, for a fee
migrate_version(cap, system)         admin, original cap    raises a system to the package version
```

`mint_system` is **linear**: an old system may name exactly one successor
(`ESuccessorAlreadyMinted`), so the chain never forks and "the next system" is always a single
answer. The successor opens selling what its predecessor sold — the tier table and
`max_epochs_ahead` are copied — because a successor that reset to nothing could not take an upload
until somebody remembered to configure it.

`migrate_system` gates on **both** systems' versions, checks the registry names the current system,
takes the fee into the successor's vault, and refuses a user already registered in the successor.
It moves the `User` object out of one system's dynamic fields and into the other's, then repoints
the `Registry`.

### What happens to objects still naming the old system

Almost nothing names a system, and that is the point.

| Object | Names a system? | What migration does to it |
|---|---|---|
| `Registry` | yes, in `system_details` | repointed by `migrate_system` |
| `User` | no | moved between systems by `migrate_system` |
| `BlobConfig` | **no** | untouched; keeps its owner, blobs, terms and mandate |
| `InnerFile` | **no** | untouched; keeps its owner, window, fallback and policy |
| `WriterPass` | no — it names a **file** | untouched, still accepted by that file |
| `ProjectHolder` | no — it names an **admin address** | untouched |

So a user's stored content does not migrate at all: it was never parented to a system. Only the
account record and the label move. A `BlobConfig` renews against any system at the package version,
because renewal is permissionless and addresses the config rather than its owner's account.

The half-migrated state — a user removed from one system and not yet added to the next — cannot be
observed, because both moves happen in the one `migrate_system` transaction. What the gate fences
is the other half: a system at the wrong version admits no call that could write to it.

---

## 4. The operator slot policy

The operator set is how a rotating backend signs without any user re-granting anything. Its
lifecycle is an operational job, not a contract one, and the contract will not remind anybody.

| | |
|---|---|
| Slot capacity | `MAX_OPERATORS = 16`, a private constant, raisable by upgrade |
| Slot lifetime | `until_ms` set to **two years** from enrolment |
| Staggering | slots are enrolled on deliberately different dates, so a full set never lapses in one week |
| Refresh | `admin::refresh_operator` before `until_ms`, by the multisig holding the **original** capability |
| Revocation | `admin::retire_operator`, which cannot abort — a slot can always be removed |

`operator::authorise` aborts `EOperatorExpired` once a slot lapses, which takes that wallet out of
service silently from the contract's side. **Nothing schedules the refresh.** That is a cron job on
the admin side, holding the original capability, and it does not exist yet.

Per-capability revocation is a weak lever under rotation and should not be relied on:
`entry_file_access::revoke_pass(file, cap_id)` bans one capability on one file, so banning a
backend from a file that way needs every id in the pool and does not cover one enrolled tomorrow.
The real levers are `set_operator_policy(operators_allowed: false)`, which is per-file and
credential-blind, and `revoke_operator_role`, which is account-wide.

---

## 5. The pre-publish checklist

### A published package compiles with its warnings suppressed

A package directory carrying a `Published.toml` is compiled **without warnings at all**. The
testnet package has one, so it reports clean whatever the sources say. The mainnet package has none
today, and that is the only reason CI's `--warnings-are-errors` means anything.

**The moment the mainnet package is published it gains a `Published.toml` and goes quiet too.** At
that point the warning gate silently stops protecting anything, and the only honest measurement is
a build with the file temporarily moved aside:

```bash
cd "Mainnet Walrus Contract Manager/warlot protocol"
mv Published.toml Published.toml.off
sui move build --build-env mainnet --warnings-are-errors
mv Published.toml.off Published.toml
```

This belongs on the checklist rather than in somebody's memory, because the failure is silent: CI
goes green, and it goes green because it stopped looking.

### Before publishing

- [ ] Both suites green, both packages, with `--warnings-are-errors` and lints on
- [ ] `./scripts/check-events.sh` passes, including sections 5, 6 and 7
- [ ] Every struct field the design wants is present — after this, each one is a new package
- [ ] Every `public fun` signature in `sources/entry/` is the one you want frozen
- [ ] `docs/events.md` and `docs/event-schema.json` match the emitted set
- [ ] The CI warning gate is re-derived per the paragraph above, not trusted
- [ ] `documentation/deployment.md` updated with the published ids and their custody
