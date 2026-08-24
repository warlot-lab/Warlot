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
├── storage/      blob configs, storage tiers, renewal accounting
├── innerfile/    mutable-state anchoring on immutable storage
├── foreign/      blob configs adopted from outside the protocol
└── product/      file, project, bucket and drive records
```

### The dependency rule

```
entry     ──► events, system, identity, storage, innerfile, foreign, product
innerfile ──► storage
storage   ──► identity
identity  ──► system
system    ──► version
events    ──► (sui::event only)
```

Three invariants, checkable by reading the `use` lines of any module:

1. No domain imports `entry`.
2. No domain imports sideways or upward. `identity` never imports `storage`.
3. `events` imports nothing internal, so any module may import it without risking a cycle.

Where domains must be composed ,  registration touches `identity` and `system`, upload touches
`identity` and `storage` ,  that composition happens in `entry`, never by one domain reaching into
another.

### Module map

Directory paths are the architecture; module names are unique across the package, so every module
in `entry/` carries an `entry_` prefix.

| File | Module | Purpose |
|---|---|---|
| `entry/register.move` | `entry_register` | Create, rename and migrate a user's registry and state |
| `entry/wallet.move` | `entry_wallet` | Fund a user's internal wallet |
| `entry/upload.move` | `entry_upload` | Adopt externally-sourced blobs into renewal management |
| `entry/renew.move` | `entry_renew` | Select which users' configs to renew, and drive renewal |
| `entry/withdraw.move` | `entry_withdraw` | Return a user's blobs to them |
| `entry/innerfile.move` | `entry_innerfile` | Create a file, write to it, merge a draft, mint a pass |
| `entry/admin.move` | `entry_admin` | Treasury withdrawal, fee changes, system and cap minting |
| `events/events.move` | `events` | Declare every event struct and its emitter |
| `system/config.move` | `system_config` | Version, fees, mint lineage, treasury, user index |
| `system/admin_cap.move` | `admin_cap` | Mint and inspect the admin capability |
| `system/vault.move` | `vault` | Custody the protocol's multi-coin treasury |
| `system/version.move` | `version` | The package version and its gate |
| `identity/registry.move` | `registry` | The owned object binding a user to a system |
| `identity/user.move` | `user` | The per-user state container attached to `SystemConfig` |
| `identity/permission.move` | `permission` | Store, write and check delegated capability bits |
| `identity/wallet.move` | `wallet` | Hold, receive and release a user's coin balances |
| `storage/blob_config.move` | `blob_config` | The object wrapping blobs and carrying their mandate |
| `storage/store.move` | `store` | Attach configs to a user and detach them again |
| `storage/tier.move` | `tier` | Resolve a requested `epoch_set` to a term on offer |
| `storage/renew.move` | `renew` | Compute the extension and account for one cycle |
| `innerfile/inner_file.move` | `inner_file` | The authoritative head, rollback window and fallback |
| `innerfile/file_data.move` | `file_data` | One revision: its commit, author and blob config |
| `innerfile/writer_pass.move` | `writer_pass` | Delegated write authority |
| `innerfile/deny_list.move` | `deny_list` | Revocation of writers |
| `innerfile/draft.move` | `draft` | Proposals awaiting the owner's merge |
| `innerfile/issue.move` | `issue` | Issues raised and resolved against a file |
| `foreign/foreign_meta.move` | `foreign_meta` | Index of adopted blob configs |
| `product/file_meta.move` | `file_meta` | On-chain attributes of a stored file |
| `product/project_object.move` | `project_object` | Projects, their buckets and their database |
| `product/bucket_object.move` | `bucket_object` | A named collection of files inside a project |
| `product/drive_meta.move` | `drive_meta` | Folder-style view with category counters |

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
