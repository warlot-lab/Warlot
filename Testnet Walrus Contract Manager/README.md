# Warlot Protocol

Warlot is the on-chain half of a decentralised storage-management protocol built on Sui. It
orchestrates [Walrus](https://github.com/MystenLabs/walrus) storage: it does not hold the bytes and
it does not hold the metadata. It holds who is allowed to do what, the money, and the commitments
that make everything off-chain verifiable.

Walrus storage expires at a fixed epoch, Walrus blobs are immutable, and small blobs are
disproportionately expensive. Warlot's answer to all three is the same move: put the renewal
mandate and the mutable-state head on chain, in public, so that execution is permissionless.
Anyone can renew anyone's blobs; Warlot's bot is the default executor, not a privileged one.

## Package layout

`sources/` is organised by domain. One module, one responsibility.

```
sources/
├── entry/        composition only ,  no structs, no state
├── events/       every event struct and its emitter, in one module
├── system/       protocol configuration, admin capability, treasury, version
├── identity/     registry, user, delegated permissions, wallet
├── storage/      blob configs, storage tiers, renewal accounting, compaction
├── innerfile/    mutable-state anchoring on immutable storage
└── product/      file, project, bucket and drive records
```

### The dependency rule

```
entry     ──► events, system, identity, storage, innerfile, product
innerfile ──► storage, identity, system
product   ──► storage
storage   ──► identity, system
identity  ──► system
system    ──► version
events    ──► (sui::event only)
```

Every domain may also import `events`, which invariant 3 below is what permits, so those edges are
left off the ladder rather than drawn six times.

`innerfile` and `product` are peers rather than a stack: both sit directly above `storage` and
neither imports the other. `product` reaches `storage` for `file_set`, the Merkle commitment a
project's file set resolves against.

Three invariants, checkable by reading the `use` lines of any module:

1. No domain imports `entry`.
2. No domain imports sideways or upward. `identity` never imports `storage`.
3. `events` imports nothing internal, so any module may import it without risking a cycle.

Every event type is declared under `sources/events/`, in one module per domain, so a single
package-scoped event-type filter returns the whole stream. `docs/events.md` records the filters.

Where domains must be composed ,  registration touches `identity` and `system`, upload touches
`identity` and `storage` ,  that composition happens in `entry`, never by one domain reaching into
another.

### Module map

Directory paths are the architecture; module names are unique across the package, so every module
in `entry/` carries an `entry_` prefix.

| File | Module | Purpose |
|---|---|---|
| `entry/register.move` | `entry_register` | Create, rename and migrate a user's registry and state |
| `entry/wallet.move` | `entry_wallet` | Fund a user's internal wallet, and pay it back out |
| `entry/upload.move` | `entry_upload` | Adopt externally-sourced blobs into renewal management |
| `entry/renew.move` | `entry_renew` | Renew one blob config, one call per config in a block |
| `entry/withdraw.move` | `entry_withdraw` | Return a user's blobs to them |
| `entry/permission.move` | `entry_permission` | Grant, replace and revoke a delegate's or the operator role's capability bits |
| `entry/file_create.move` | `entry_file_create` | Create an inner file |
| `entry/file_project.move` | `entry_file_project` | Create a file and name it as a project's database |
| `entry/file_write.move` | `entry_file_write` | Write into a file's history or into its draft queue |
| `entry/file_fallback.move` | `entry_file_fallback` | Record and drop the revision an owner can fall back to |
| `entry/file_draft.move` | `entry_file_draft` | Merge, reject and clear drafts |
| `entry/file_access.move` | `entry_file_access` | A file's terms for delegates: passes, denials, revocations |
| `entry/compaction.move` | `entry_compaction` | Plan a compaction, name what it replaces, register the receipt |
| `entry/admin.move` | `entry_admin` | Treasury withdrawal, fee changes, system and cap minting, the operator set |
| `events/system_events.move` | `system_events` | System configuration, lineage and capability events |
| `events/treasury_events.move` | `treasury_events` | Treasury custody events |
| `events/identity_events.move` | `identity_events` | Registration, wallet and delegation events |
| `events/storage_events.move` | `storage_events` | Blob custody, renewal and adoption events |
| `events/innerfile_events.move` | `innerfile_events` | File creation, head, fallback and retirement events |
| `events/draft_events.move` | `draft_events` | Draft queue events |
| `events/pass_events.move` | `pass_events` | Writer pass and revocation events |
| `events/product_events.move` | `product_events` | Project holder, project, database and commitment events |
| `system/config.move` | `system_config` | Version, fees, mint lineage and treasury |
| `system/admin_cap.move` | `admin_cap` | Mint and inspect the admin capability |
| `system/operator.move` | `operator` | The capabilities a system accepts as backend credentials |
| `system/vault.move` | `vault` | Custody the protocol's multi-coin treasury |
| `system/version.move` | `version` | The package version and its gate |
| `identity/registry.move` | `registry` | The owned object binding a user to a system |
| `identity/user.move` | `user` | The per-user state container attached to `SystemConfig` |
| `identity/permission.move` | `permission` | Store, write and check the bits delegated to an address or to the operator role |
| `identity/wallet.move` | `wallet` | Hold, receive and release a user's coin balances |
| `storage/blob_config.move` | `blob_config` | The shared object holding blobs and their mandate |
| `storage/store.move` | `store` | Take blobs into custody as shared configs |
| `storage/tier.move` | `tier` | Resolve a requested `epoch_set` to a term on offer |
| `storage/renew.move` | `renew` | Compute the extension and account for one cycle |
| `storage/layout.move` | `layout` | A compaction's receipt: two roots, constant in the file count |
| `storage/compaction.move` | `compaction` | Assemble a compaction and write its receipt |
| `storage/id_set.move` | `id_set` | The root committing to the configs a compaction replaces |
| `innerfile/inner_file.move` | `inner_file` | The authoritative head, rollback window and fallback |
| `innerfile/file_data.move` | `file_data` | One revision: its commit, author and blob config |
| `innerfile/writer_pass.move` | `writer_pass` | Delegated write authority |
| `innerfile/credential.move` | `credential` | Which authority one write was made under |
| `innerfile/deny_list.move` | `deny_list` | Revocation of writers |
| `innerfile/draft.move` | `draft` | Proposals awaiting the owner's merge |
| `innerfile/commit.move` | `commit` | The Merkle root a revision commits to |
| `innerfile/eviction.move` | `eviction` | What becomes of a revision that leaves the window |
| `innerfile/creation.move` | `creation` | Build a file from its first revision |
| `innerfile/revision.move` | `revision` | Store blobs as one revision of a file |
| `storage/file_set.move` | `file_set` | The root binding logical paths to the bytes they resolve to |
| `product/project_object.move` | `project_object` | A project's database and its commitment, keyed by id |

### Conventions

Every module follows a fixed section order, marked with `// === Section ===` headers: imports,
errors, constants, structs, events, method aliases, public functions, view functions, admin
functions, package functions, private functions, test-only helpers. `///` doc comments carry the
public surface; `//` carries implementation notes.

A module is too large when its purpose no longer fits one sentence; over roughly 250 lines it needs
a justification or a split.

## Networks

The two package directories are one package with two dependency resolutions. Their `sources/` and
`tests/` trees are identical, and only `Move.toml` differs ,  the Walrus dependency resolves to
`mainnet-contracts/` for one and `testnet-contracts/` for the other. Their Move sources are
byte-identical upstream; only the published addresses differ, which is exactly what the two
directories exist to select between.

| Directory | Walrus contracts |
|---|---|
| `Mainnet Walrus Contract Manager/warlot protocol/` | `mainnet-contracts/` |
| `Testnet Walrus Contract Manager/` | `testnet-contracts/` |

The Walrus dependency is pinned to a full commit SHA, never a branch, so the build is reproducible
and an upstream change cannot silently alter the bytecode.

## Building

Requires the Sui CLI at 1.73 or later, which is where the new-style package manifest landed.

```bash
sui move build
sui move test
```

`sui move build` resolves for the CLI's active environment. Pass `--build-env mainnet` or
`--build-env testnet` to pin a specific environment's dependency addresses into `Move.lock`.

## Tests

```
tests/
├── regression/    one file per proven audit finding
└── support/       shared test-only constructors
```

The regression tests currently pass by **demonstrating** the findings they name. Each will be
inverted as its finding is fixed, so that it passes by demonstrating the finding's absence.
`support/fixtures.move` builds the Walrus objects the tests need ,  a system, a WAL coin and a
registered blob ,  against the real Walrus package rather than a stub.
