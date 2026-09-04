# Deployment state, per network

Every on-chain object a deployment depends on, what holds it, and what is not deployed yet.

Read live from the chain on 2026-09-04 rather than copied from a document. Re-derive it the same
way rather than trusting the table — the commands are under each section.

---

## Testnet

### What is published

| | |
|---|---|
| Package id | `0x466c3980d0f8603c3c0bfa64a23c88d36c4ee492cd5a62d3a0e95060a1a3d237` |
| Original id | the same — this is a first publish, never upgraded |
| On-chain version | `1` |
| Modules | 54 |
| Toolchain | `1.73.1`, matching `Published.toml` and the CI pin |
| Publish transaction | `6wcTFGyP8L84XuQJZQCtoDJzdYL8WujAKJAywsSit3ie` |
| Published by | `0x2f35202a4822c065e1551ebff78ed753103182f569e9e681917e9d5fd2eca0d3` |
| Cost | 0.674 SUI |

### The objects it created

Taken from the publish transaction's own report, not reconstructed afterwards.

| Object | Id | Custody |
|---|---|---|
| Package | `0x466c3980d0f8603c3c0bfa64a23c88d36c4ee492cd5a62d3a0e95060a1a3d237` | Immutable |
| `SystemConfig` | `0x3dcce443971e28376d1556ea8a01a0b08477d322692fae00b84914de7de41096` | Shared, `initial_shared_version` 997548927 |
| Original `AdminCap` | `0xb9b2ec97ac38f4f2761076222b1dde2775318ef5ec9c91e7db8927f106581521` | `0x2f35202a4822c065e1551ebff78ed753103182f569e9e681917e9d5fd2eca0d3` |
| `Vault` | `0xeebbf1f5ad41da05e513e0b650c382f929812b3a134a5642c172bdd6fc63f138` | Dynamic object field of the `SystemConfig` |
| `UpgradeCap` | `0xfe9e02d33ea48a3f7ef2e52f329766d68bc389e76f0e9f417fa15e7e80f93ee1` | **Wrapped** — see below |

The `Vault` is reached through the `SystemConfig` rather than by its own id, under the field name
`system_vault`, so the id above can be re-derived if this record is ever doubted:

```bash
sui client dynamic-field 0x3dcce443971e28376d1556ea8a01a0b08477d322692fae00b84914de7de41096
```

### The upgrade capability, and the transaction after the publish

The publish put a `sui::package::UpgradeCap` in the publisher's wallet, where it answered to nothing
the contract checks. The next transaction took it into custody:

| | |
|---|---|
| `UpgradeAuthority` | `0x0e3b32620e49f528e4202e17a88ae96a4d536d3539415ea46d6198a07eee42c4` |
| Custody | Shared, `initial_shared_version` 997548928 |
| Transaction | `4JsC3TV6EKdXMH9CNY1u8czPuba9d26ZeSoenAXCywQo` |
| Policy | `0` — `COMPATIBLE`, the policy a publish starts at |
| Capability version | `1` |

**The wallet holds no upgrade capability for this package.** The `UpgradeCap` is inside the shared
authority, so a lookup of it reports the object as not found ,  a wrapped object is not addressable
on its own:

```bash
sui client object 0xfe9e02d33ea48a3f7ef2e52f329766d68bc389e76f0e9f417fa15e7e80f93ee1
# -> Internal error, cannot read the object: Object has been wrapped
```

Verified two ways rather than assumed: that lookup, and a sweep of every `UpgradeCap` the publishing
address owns, none of which names this package.

`Published.toml` still records that same id as its `upgrade-capability`, and the id is correct — it is
the capability object. But **`sui client upgrade -c <that id>` will not work**, because the address no
longer owns it. An upgrade is the three-command programmable transaction in
[upgrades.md](upgrades.md) §2, authorised by the original `AdminCap`.

### What a client also needs

| | | How it was derived |
|---|---|---|
| `Clock` | `0x6` | Sui system object, shared, not ours |
| Walrus `System` | `0x6c2547cbbc38025cf3adac45f63cb0a8d12ecf777cdc75a4971612bf97fdf6af` | Shared, `initial_shared_version` 400185623 |
| Walrus package | `0x849e95d2718938d66c37fb91df76d72f78526c1864c339bac415ce8ecda2d8cc` (original `0xd84704c17fc870b8764832c535aa6b11f21a95cd6f5bb38a9b07d2cf42220c66`) | `Move.toml` pins `walrus` at rev `0d671d3c`; that checkout's `testnet-contracts/walrus/Published.toml` gives both ids |
| `WAL` coin type | `0x8270feb7375eee355e64fdb69c50abb6b5f9393a722883c1cf45f8e26048810a::wal::WAL` | the same way, from `testnet-contracts/wal/Published.toml` |

The Walrus `System` object id is in no manifest, so it was read from the chain by querying for the
one object of type `<walrus original id>::system::System` rather than copied from a document.

### Verifying it

```bash
sui client object 0x466c3980d0f8603c3c0bfa64a23c88d36c4ee492cd5a62d3a0e95060a1a3d237
sui client object 0x3dcce443971e28376d1556ea8a01a0b08477d322692fae00b84914de7de41096
sui client object 0xb9b2ec97ac38f4f2761076222b1dde2775318ef5ec9c91e7db8927f106581521
sui client object 0x0e3b32620e49f528e4202e17a88ae96a4d536d3539415ea46d6198a07eee42c4
sui client object 0x6c2547cbbc38025cf3adac45f63cb0a8d12ecf777cdc75a4971612bf97fdf6af
sui client tx-block 6wcTFGyP8L84XuQJZQCtoDJzdYL8WujAKJAywsSit3ie
```

The deployed `SystemConfig` reads `version: 1`, `previous_system: 0x0`, `next_system: none` — the
head of a chain of one, at the package version, so its entry surface is open.

### It has been transacted against

A deployment nobody has exercised is not known to work. One account is registered:

| | |
|---|---|
| Transaction | `HWsQiwsUeeJHYkKhcSuYRKpbCUxpA2Px7oz56dQhXSBz` |
| `Registry` | `0xb676e89b2848cfb6723cdf0a80cb13e2ac3d4ed9068fe54c3ce04c5c95833eb7`, owned by `0x2f35202a4822c065e1551ebff78ed753103182f569e9e681917e9d5fd2eca0d3` |
| `User` | `0x0861231fa63a0113f81573b00bb80264eeb9ec96a98f75d884e9f126da3c7cf0`, a dynamic object field of the `SystemConfig` |
| Username | `warlot-main` |

It raised `WalletCreated`, `UserRegistered` and `UserJoinedSystem`, in that order, which is the
sequence [event-stream.md](event-stream.md) documents.

**`WalletCreated.wallet_id` does not resolve, and that is correct.** `User` holds its `Wallet`
inline, so the wallet is wrapped from the moment it is created and is never a top-level object. A
consumer reads it through the `User`:

```bash
sui client object 0x0861231fa63a0113f81573b00bb80264eeb9ec96a98f75d884e9f126da3c7cf0
# -> wallet.id == 0xd8967654d42968e9edc159f82b4e8dc4395d48bf61f9457ab45d1efb4a680684,
#    the id WalletCreated carried
```

### The previous publications

**There are two of them, not one.** The publishing address owns a `registry::Registry` under three
different package ids, which is the cheapest way to enumerate the generations ,  a `Registry` is
created once per account per system, so one per package id is one publication per package id:

| Generation | Package | Its `Registry` | Upgrade key |
|---|---|---|---|
| First | `0x109fba1479e19843b2b6ed8d225b9fb341c85cc274ca5ae90bcf40242f0c7a0b` | `0xce9247d62aba1b640f00361dddad9d3de041c9af996aa4c02271b22948d12283` | **still held** — see below |
| Second | `0x449204e37a63f69e64d57161a72a792b9bf3399d85a641faa6c96240b41e7927` | `0x270953c43abc21cc29a085d1636b6784986d08246ffc0d7c41df4d06c6d54f7e` | none the address holds |
| Current | `0x466c3980d0f8603c3c0bfa64a23c88d36c4ee492cd5a62d3a0e95060a1a3d237` | `0xb676e89b2848cfb6723cdf0a80cb13e2ac3d4ed9068fe54c3ce04c5c95833eb7` | wrapped in the `UpgradeAuthority` |

The order is read off those `Registry` objects' versions ,  994138689, 997529324, 1002576309 ,  the
ordering evidence that survives once the publish transactions age out of a node's index.

Both prior packages are still on chain and still immutable, and **every object under either is
orphaned** by this deployment. Nothing migrates: no two of the three share types, so a
`SystemConfig` under an older id cannot be read by newer code.

What follows compares the current package against the **first**, which is the generation the module
inventory was measured against.

It was replaced rather than upgraded because a Move upgrade cannot remove a module, and this one
removes six. Read from the chain rather than from the source tree:

| | |
|---|---|
| Published then | 40 modules |
| Published now | 54 modules |
| Gone | `bucket_object`, `drive_meta`, `entry_innerfile`, `file_meta`, `foreign_meta`, `issue` |
| Added | `compaction`, `creation`, `credential`, `entry_compaction`, `entry_file_access`, `entry_file_create`, `entry_file_draft`, `entry_file_fallback`, `entry_file_project`, `entry_file_write`, `entry_transfer`, `entry_upgrade`, `file_set`, `id_set`, `layout`, `operator`, `product_events`, `revision`, `upgrade`, `upgrade_events` |

`entry_innerfile` was split into the seven `entry_file_*` modules; the four record modules the design
dropped are still on chain because a published package is immutable. Struct fields and public
signatures changed as well, which [upgrades.md](upgrades.md) §1 lists as refused.

**The first package is still upgradable by the same address.** Its `UpgradeCap`,
`0xb91084d36568df0b96764f576f263e8a4ec7185d493cb3b5059354d351f54a26`, remains owned by
`0x2f35202a4822c065e1551ebff78ed753103182f569e9e681917e9d5fd2eca0d3` at policy `0`, outside the
authority model this package now enforces on itself. It governs code nothing points at any more.

**It is the only one.** The publishing address owns 18 `sui::package::UpgradeCap` objects, every one
at policy `0`. Each was read rather than sampled, and exactly one names a Warlot package. The second
generation has no upgrade key among them, so it is orphaned but unreachable, and the current
package's key is wrapped. One loose upgrade key in total, and this is it.

---

## Mainnet

**Nothing is deployed.** The package has no `Published.toml`.

```bash
ls "Mainnet Walrus Contract Manager/warlot protocol/Published.toml"   # No such file
```

That absence is load-bearing for CI, not merely a fact about the roadmap: a package directory with
a `Published.toml` compiles with its warnings suppressed, so the mainnet package is the only one
whose warnings CI can see. See [upgrades.md](upgrades.md) §6 before publishing it.

---

## Custody, and the question it leaves open

The original `AdminCap` is held by a single address,
`0x2f35202a4822c065e1551ebff78ed753103182f569e9e681917e9d5fd2eca0d3`. The chain reports
`AddressOwner`, which does not distinguish a single key from a multisig, so **whether that address
is a multisig has to be confirmed off chain**; it is not something a live read can answer.

### What the original capability can do

It is the only key that can `migrate_version` a system, `mint_system` its successor, move fees and
tiers, withdraw from the vault, mint duplicate capabilities, enrol, refresh or retire every operator
slot — **and, since this deployment, authorise an upgrade of the package itself, ratchet the upgrade
policy, or make the package immutable.**

That last clause is the change this deployment makes to the custody picture. There used to be two
roots of trust: the `AdminCap` for everything the contract checks, and the `UpgradeCap` for the code
that does the checking. There is now one. That is strictly better against a lost or stolen
`UpgradeCap` and strictly worse against a lost or stolen `AdminCap`, which is now the only key that
matters and matters more than before.

### The open question

**The original `AdminCap` has no expiry and no revocation.** Every other credential in the protocol
decays or can be withdrawn: a `WriterPass` carries a duration and can be revoked per file, an
operator slot carries `until_ms` and can be retired, a delegation can be replaced or revoked. The
original capability carries none of that, by design — it is the root, and a root that could be
revoked would need a second root above it.

Three consequences worth stating plainly:

1. **It is also the key that keeps the operator pool alive.** `refresh_operator` requires it, and an
   unrefreshed slot lapses silently. So the key is not merely a break-glass credential held in cold
   storage; something holding it has to act on a schedule.
2. **Losing it is unrecoverable for that system.** No `migrate_version`, so the next package upgrade
   closes the system's entry surface permanently; no `mint_system`, so users cannot be moved to a
   successor. The content survives — a `BlobConfig` names no system and renewal is permissionless —
   but the account surface does not.
3. **Losing it now also ends the package's upgradability.** The `UpgradeAuthority` is shared, so
   nothing is lost by misplacing an object; but nothing can authorise through it without the
   original capability, and no second capability for a system can ever be an original.

This is recorded, not solved. It is the item to settle before mainnet.
