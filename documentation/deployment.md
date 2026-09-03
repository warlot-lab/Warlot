# Deployment state, per network

Every on-chain object a deployment depends on, what holds it, and what is not deployed yet.

Read live from the chain on 2026-09-03 rather than copied from a document. Re-derive it the same
way rather than trusting the table — the commands are under each section.

---

## Testnet

### What is published

| | |
|---|---|
| Package id | `0x109fba1479e19843b2b6ed8d225b9fb341c85cc274ca5ae90bcf40242f0c7a0b` |
| Original id | the same — this is the first publish, never upgraded |
| On-chain version | `1` |
| Toolchain | `1.73.1`, matching every `Published.toml` and the CI pin |
| Publish transaction | `FqCoo1gYwYH2PwebV99G9oDF1Tx4P8SxcpxAtPGmAfaA` |

### The objects it created

| Object | Id | Custody |
|---|---|---|
| Package | `0x109fba14…2f0c7a0b` | Immutable |
| `SystemConfig` | `0xe83d94b6…559e79f3` | Shared, `initial_shared_version` 992978149 |
| Original `AdminCap` | `0x88b1b6ca…b16f0864` | `0x2f35202a…d2eca0d3` |
| `UpgradeCap` | `0xb91084d3…51f54a26` | `0x2f35202a…d2eca0d3` |
| `Clock` | `0x6` | Sui system object, shared, not ours |

The deployed `SystemConfig` reads `version: 1`, `previous_system: 0x0`, `next_system: none` — the
head of a chain of one, at the package version, so its entry surface is open.

```bash
sui client object 0x109fba1479e19843b2b6ed8d225b9fb341c85cc274ca5ae90bcf40242f0c7a0b
sui client object 0xe83d94b66a2b80f6c7bb64eba2fbfd01eb56bd2ca12a5a5db380d816559e79f3
sui client tx-block FqCoo1gYwYH2PwebV99G9oDF1Tx4P8SxcpxAtPGmAfaA
```

### The published package is not this source tree

**Do not treat the testnet deployment as a build of `main`.** It is an earlier shape of the same
package, and the module sets differ:

| | |
|---|---|
| Published, no longer exists | `bucket_object`, `drive_meta`, `entry_innerfile`, `file_meta`, `foreign_meta`, `issue` |
| Exists, not published | `compaction`, `creation`, `credential`, `entry_compaction`, `entry_file_access`, `entry_file_create`, `entry_file_draft`, `entry_file_fallback`, `entry_file_project`, `entry_file_write`, `entry_transfer`, `file_set`, `id_set`, `layout`, `operator`, `product_events`, `revision` |

40 modules published; 51 in the tree. `entry_innerfile` has since been split into the seven
`entry_file_*` modules, and the four record modules the design dropped are still on chain because a
published package is immutable.

The gap is wider than an upgrade could close: the current tree changes struct fields
(`operators_may_draft`, `pending_owner`, `can_set_root`) and public signatures, which
`documentation/upgrades.md` §1 lists as refused. **The next testnet deployment is a fresh publish,
not an upgrade**, and it gets new ids for everything in the table above.

---

## Mainnet

**Nothing is deployed.** The package has no `Published.toml`, which is consistent with the
pre-release banner in the root `README.md`:

> **Status: pre-release.** Under active development and not deployed to Sui mainnet. Interfaces,
> object layouts and the event schema are all still changing. Do not build against this yet.

```bash
ls "Mainnet Walrus Contract Manager/warlot protocol/Published.toml"   # No such file
```

That absence is load-bearing for CI, not merely a fact about the roadmap: a package directory with
a `Published.toml` compiles with its warnings suppressed, so the mainnet package is the only one
whose warnings CI can see. See `documentation/upgrades.md` §5 before publishing it.

---

## Custody, and the question it leaves open

Both capabilities — the original `AdminCap` and the `UpgradeCap` — are held by a single address,
`0x2f35202a4822c065e1551ebff78ed753103182f569e9e681917e9d5fd2eca0d3`. The chain reports
`AddressOwner`, which does not distinguish a single key from a multisig, so **whether that address
is a multisig has to be confirmed off chain**; it is not something a live read can answer.

### What the original capability can do

It is the only key that can `migrate_version` a system, `mint_system` its successor, move fees and
tiers, withdraw from the vault, mint duplicate capabilities, and enrol, refresh or retire every
operator slot.

### The open question

**The original `AdminCap` has no expiry and no revocation.** Every other credential in the protocol
decays or can be withdrawn: a `WriterPass` carries a duration and can be revoked per file, an
operator slot carries `until_ms` and can be retired, a delegation can be replaced or revoked. The
original capability carries none of that, by design — it is the root, and a root that could be
revoked would need a second root above it.

Two consequences worth stating plainly:

1. **It is now also the key that keeps the operator pool alive.** `refresh_operator` requires it,
   and an unrefreshed slot lapses silently. So the key is not merely a break-glass credential held
   in cold storage; something holding it has to act on a schedule.
2. **Losing it is unrecoverable for that system.** No `migrate_version`, so the next package upgrade
   closes the system's entry surface permanently; no `mint_system`, so users cannot be moved to a
   successor. The content survives — a `BlobConfig` names no system and renewal is permissionless —
   but the account surface does not.

This is recorded, not solved. It is the item to settle before mainnet.
