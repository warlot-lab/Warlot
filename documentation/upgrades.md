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
| Moving a value between a `dynamic_field` and a `dynamic_object_field` | Different key spaces, same name. **Not caught by the compatibility check** — it compiles, publishes, and then finds nothing |

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

## 2. Who may upgrade

The boundary above says what an upgrade may change. This says who may perform one, and it is a
separate question with a separate answer.

### The capability, and where it used to sit

Publishing mints a `sui::package::UpgradeCap` and transfers it to the sender. Nothing in Move can
intercept that: `init` takes a one-time witness and a `TxContext` and nothing else, so the
capability cannot be wrapped at birth. Verified against the compiler, which refuses any other `init`
signature by name.

Left where publishing puts it, that object is the whole of the protocol's upgrade authority, and it
answers to nothing the contract knows. Its holder can replace every check in this package —
`assert_original_cap_for`, the version gate, the operator set, the vault's own withdrawal
authorisation — without presenting an `AdminCap`, without any system being at any particular
version, and without the event stream saying a word.

### Taking custody

`entry_upgrade::take_custody(cap, admin_cap)` puts the capability inside an `UpgradeAuthority` and
shares it. It is run **once, in the transaction after publication**, and until it is, everything in
the paragraph above is true.

```
publish                    ──►  UpgradeCap lands in the publisher's wallet
take_custody(cap, admin)   ──►  UpgradeAuthority, shared; wallet holds nothing
```

The authority is **shared, not owned**, and that is the point of it rather than an incidental
choice. An owned wrapper would mean an upgrade needs two things — the original `AdminCap` and
whatever address the wrapper was last sent to — so a misdirected transfer would end the package's
upgradability while the admin key was still perfectly good. Shared, custody is not a factor and the
capability *is* the authority: the same original `AdminCap` that gates the treasury and the operator
set, and nothing else.

The struct is `key` without `store`, so no other module can wrap it, transfer it, or take the
`UpgradeCap` back out into a wallet. The only exit is `make_immutable`.

`take_custody` does not check that the capability governs *this* package. The framework exposes no
way to do it that keeps working — `upgrade_package` returns the current package, which equals the
original only until the first upgrade, and there is no accessor for the original id. Both ids are
announced in `UpgradeAuthorityCreated` and recorded in `deployment.md` instead, so a mismatch is
visible rather than prevented.

### Performing an upgrade

Three commands in **one** programmable transaction:

```
1. entry_upgrade::authorise_upgrade(authority, admin_cap, digest)  ──►  UpgradeTicket
2. the transaction's own Upgrade command, consuming the ticket     ──►  UpgradeReceipt
3. entry_upgrade::commit_upgrade(authority, admin_cap, receipt)
```

They cannot be split across transactions, and there is no design decision in that. `UpgradeTicket`
has no abilities: it cannot be stored, transferred or dropped, so a transaction that issues one and
does not spend it does not commit at all. This matters because `authorize_upgrade` **zeroes the
capability's package id** and `commit_upgrade` restores it, so a design that could leave the two
halves in different transactions would strand the capability in the authorised state and lock the
package out of every future upgrade. The hot potato is what makes that unreachable, and
`upgrade_tests::one_ticket_at_a_time` pins the framework's half of it.

The `digest` is SHA3-256 over the sorted modules and transitive dependencies. It is what binds the
authorisation to one specific build, and it is carried in `UpgradeAuthorised` so that a reviewer can
confirm the upgrade that landed is the one they read. The build prints it:

```bash
sui move build --dump-bytecode-as-base64 \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['digest'])"
# [247, 220, 82, ...]   32 bytes
```

The three commands are one `sui client ptb` invocation:

```bash
sui client ptb \
  --move-call <PKG>::entry_upgrade::authorise_upgrade \
      @<AUTHORITY> @<ADMIN_CAP> "vector[247u8,220u8,82u8,...]" \
  --assign ticket \
  --upgrade "." ticket \
  --assign receipt \
  --move-call <PKG>::entry_upgrade::commit_upgrade \
      @<AUTHORITY> @<ADMIN_CAP> receipt
```

**What has been checked, and what has not.** The digest command above was run on this tree. The
programmable transaction parses as written, confirmed with `sui client ptb --preview`, which
resolves the commands without contacting the chain. **It has not been executed**: the testnet
deployment has never been upgraded, so nothing here has been proved end to end against a validator.
Treat the first real upgrade as the test of this block, and dry-run it before signing.

Note that `sui client upgrade --upgrade-capability <id>` — the ordinary path — **will not work**.
That command needs the sender to own the capability, and after `take_custody` nobody does.

### The policy ratchet

| Policy | Value | Allows |
|---|---|---|
| `COMPATIBLE` | `0` | any change section 1 permits |
| `ADDITIVE` | `128` | new functions and types, dependency changes; existing bodies frozen |
| `DEP_ONLY` | `192` | dependency changes alone |

**These are the values `sui::package` declares.** The Sui documentation site gives them as `1`, `2`,
`3`; it is wrong, and a consumer decoding `policy` off the event stream needs the numbers above.

A package publishes at `COMPATIBLE`. `restrict_to_additive` and `restrict_to_dep_only` tighten it,
each needing the original `AdminCap`. **The ratchet turns one way**: the framework refuses any policy
less restrictive than the one in force (`ETooPermissive`), so neither this package nor any later
version of it can loosen what a predecessor gave up.

An upgrade is always authorised at the authority's own current policy, never at one supplied by the
caller. `package::authorize_upgrade` accepts any `u8` at least as restrictive as the capability's
own, which means it also accepts the values *between* the three the framework defines, and what a
validator makes of one of those is not something this package can check. Reading the policy back
from the capability leaves exactly one place a policy is ever chosen — the ratchet — and that place
only sets the framework's own constants.

### Freezing the package

`entry_upgrade::make_immutable(authority, admin_cap)` destroys the authority and the capability
inside it. Terminal, and terminal for the package rather than just for the object: nothing can mint
another `UpgradeCap` for a package already published.

It is exposed rather than withheld, because the alternative to a deliberate call is not safety. A
protocol that means to become unchangeable and has no way to say so keeps a live upgrade key
forever, and a key that exists is a key that can be compromised. After it, the system chain —
`mint_system` beside the old system, users walking across — is the only change left that reaches
anything.

### Why nothing in `entry_upgrade` asserts the version

It is the one module besides `admin::migrate_version` that does not, and for the same reason.

The version gate fences the state a mismatched build could write to. An upgrade writes none of that
state; what an upgrade *is*, is the repair. A build that broke migration would leave every system
permanently behind the package, and if reaching the upgrade authority required a system that was at
the package version, the one lever that could fix it would be the one the fault had already taken
away. Nothing here takes a `SystemConfig` at all, which is also why section 6's gate-coverage check
does not ask for one.

The gate still applies afterwards, and hard. Committing an upgrade leaves every `SystemConfig`
behind the new package, so the whole entry surface aborts `EWrongPackageVersion` until an admin
calls `migrate_version` on each one.

**Authorising cannot raise the version on the way past, and this is mechanical rather than a
preference.** The code executing during an upgrade transaction is the code being replaced:
`version::get_version()` in that transaction returns the *old* constant, and the new package does not
exist on chain until the upgrade command that runs after the authorising call has returned. So
`migrate_version` stays the separate second act it has always been, because there is no first act it
could have been folded into.

### What the stream carries

| Event | Raised by |
|---|---|
| `UpgradeAuthorityCreated` | `take_custody` |
| `UpgradeAuthorised` | `authorise_upgrade` |
| `UpgradeCommitted` | `commit_upgrade` |
| `UpgradePolicyRestricted` | `restrict_to_additive`, `restrict_to_dep_only` |
| `UpgradeAuthorityDestroyed` | `make_immutable` |

`UpgradeCommitted` with no matching `SystemVersionMigrated` is a protocol refusing every call. It is
a state to alert on, not one to retry through.

---

## 3. The version gate

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

## 4. When a struct must change: the system chain

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

## 5. The operator slot policy

The operator set is how a rotating backend signs without any user re-granting anything. Its
lifecycle is an operational job, not a contract one, and the contract will not remind anybody.

| | |
|---|---|
| Slot capacity | `MAX_OPERATORS = 16`, a private constant, raisable by upgrade |
| Refresh | `admin::refresh_operator` before `until_ms`, by the holder of the **original** capability |
| Revocation | `admin::retire_operator`, which cannot abort — a slot can always be removed |

**What the contract enforces about a slot's lifetime is one rule: `until_ms` must be strictly in the
future** (`EInvalidOperatorExpiry`). There is no maximum and no default. Everything else is an
operational decision made at the call site:

| Policy | |
|---|---|
| Slot lifetime | `until_ms` two years out from enrolment |
| Staggering | slots enrolled on deliberately different dates, so a full set never lapses in one week |

Neither is expressible in the contract, and neither is checked by it. They are recorded here because
the alternative is that they live in somebody's memory.

`operator::authorise` aborts `EOperatorExpired` once a slot lapses, which takes that wallet out of
service silently from the contract's side. **Nothing schedules the refresh.** That is a cron job on
the admin side, holding the original capability, and it does not exist yet.

Per-capability revocation is a weak lever under rotation and should not be relied on:
`entry_file_access::revoke_pass(file, cap_id)` bans one capability on one file, so banning a
backend from a file that way needs every id in the pool and does not cover one enrolled tomorrow.
The real levers are `set_operator_policy(operators_allowed: false)`, which is per-file and
credential-blind, and `revoke_operator_role`, which is account-wide.

---

## 6. The pre-publish checklist

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

### Immediately after publishing

- [ ] `entry_upgrade::take_custody` run, in the next transaction, before anything else
- [ ] The publishing wallet holds no `UpgradeCap` afterwards — check, do not assume
- [ ] The `UpgradeAuthority` id and the package id it names recorded in `deployment.md`
