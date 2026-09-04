# Warlot Protocol

Sui Move contracts for storage-lifecycle management on [Walrus](https://www.walrus.xyz/).

Walrus stores bytes and issues a `Blob` object carrying a prepaid storage resource that expires at
a fixed epoch. Warlot is the layer that keeps that resource from expiring, on a mandate the user
sets once, executable by anyone.

## Status

Three separate claims:

| | |
|---|---|
| **Sui testnet** | **Deployed.** Package `0x466c3980d0f8603c3c0bfa64a23c88d36c4ee492cd5a62d3a0e95060a1a3d237`, see [deployment.md](documentation/deployment.md) |
| **Sui mainnet** | **Not deployed.** No `Published.toml` exists for the mainnet package |
| **External audit** | **Not completed.** No third party has reviewed this code |

What that means in practice: the testnet deployment is real, exercised, and safe to build a client
against. It is not safe to put anything you cannot lose on it. Object layouts and public signatures
are frozen for the published package — an upgrade cannot change either, see
[upgrades.md](documentation/upgrades.md) §1 — but **the mainnet deployment will be a fresh publish
with new ids for everything**, not an upgrade of the testnet one.

---

## Why it exists

Walrus solves durable storage. Three problems sit on top of it, and Walrus solves none of them:

**Storage expires, so someone has to renew it.** That someone must watch the clock, hold WAL, and
call `extend_blob` before expiry. If it is a centralised service, the user has handed over custody
of their data's survival.

**Blobs are immutable, so mutable state needs an anchor.** A database, a document, a configuration
file, anything that changes, needs an authoritative pointer to its current state and a controlled
way to advance it with more than one writer. An event log cannot serve this purpose: two concurrent
writers reading a log can both believe they are building on the tip.

**Small blobs are disproportionately expensive.** Every Walrus blob pays a fixed metadata charge
regardless of size. Batching many files into one blob is the answer, but it makes deletion and
renewal whole-blob operations and changes a file's address when it is repacked, so it needs a
stable file identity that survives re-layout, and a way to prove a repack was faithful.

Warlot's answer to all three is the same: **put the mandate and the head on chain, in public, so
that execution is permissionless.** A user states once what they want renewed, how far ahead, and
how many times. Anyone can then execute that mandate, no capability, no allowlist. If Warlot
disappears, the user, a competitor, or a community bot can keep every blob alive without our
cooperation.

## What the contract holds

Three things, and deliberately nothing else:

| | |
|---|---|
| **Authority** | who may act on whose behalf, and what they may do, granular and revocable |
| **Value** | per-user balances and the protocol treasury |
| **Commitments** | the cryptographic anchors that make off-chain data verifiable |

It does not store file bytes; Walrus does. It does not store file names, descriptions, or
aggregate counters; those are labels and running totals that no contract reads, so they belong in
a database. What the chain holds instead is a commitment binding names to content, which is the
part with trust value.

## Who can change it

One key, and the same one throughout. Every privileged operation — the treasury, the operator set,
the fee and tier configuration, minting the next system — requires the **original** `AdminCap` for
that system. A duplicate capability is refused, and so is an original minted for a different system.

**The package's own code answers to that same key.** The `UpgradeCap` publishing mints is not left
in a wallet: it is held inside a shared `UpgradeAuthority`, and authorising an upgrade, tightening
the upgrade policy or making the package immutable all require the original `AdminCap`. There is no
path to replace this code that does not pass a check the contract itself makes.

What that means for a consumer:

- **An upgrade cannot change a struct field or a public signature.** Those are refused by Sui's
  compatibility check, so a client compiled against the published surface keeps working.
- **After any upgrade, every system is closed until an admin migrates it.** Each `SystemConfig`
  stores the version it was raised to, and every entry point taking one aborts
  `EWrongPackageVersion` until `migrate_version` is called on it. A client seeing that abort across
  the whole surface is looking at an unmigrated system, not at a bug.
- **Every step is announced.** Custody, authorisation, policy ratchet, commit and freeze each raise
  an event.
- **The upgrade policy is a one-way ratchet.** It starts `COMPATIBLE` and can only be tightened.

The full account, including the shape of an upgrade transaction, is in
[upgrades.md](documentation/upgrades.md) §2. The open question about the root key having no expiry
and no revocation is stated plainly in [deployment.md](documentation/deployment.md).

## Documentation

[`documentation/`](documentation/) is written for someone arriving with no context. Start at its
[index](documentation/README.md), which routes by what you are doing.

**The shape of the thing**

| | |
|---|---|
| [architecture.md](documentation/architecture.md) | What the contract holds, the domain ladder, and why the dependency rule is shaped that way |
| [objects.md](documentation/objects.md) | Every stored object: what is inside it, what attaches to it and when, what can destroy it |
| [bounds.md](documentation/bounds.md) | Every limit in the protocol, with the reason for it and what raising it would buy |

**Who may do what**

| | |
|---|---|
| [permissions.md](documentation/permissions.md) | The six delegation bits, the dependency chain between them, and the two places a grant lives |
| [operators.md](documentation/operators.md) | The credential a rotating backend signs with: three independent gates, and who revokes each |
| [custody.md](documentation/custody.md) | Who owns a `BlobConfig` on every path that creates one, and why deletion is not delegable |
| [entry-points.md](documentation/entry-points.md) | All 68 public functions, each section shaped like its subject |
| [refusals.md](documentation/refusals.md) | What the contract will not do, and why |

**Building against it**

| | |
|---|---|
| [flows.md](documentation/flows.md) | Worked call sequences, with the events each raises, in order |
| [event-stream.md](documentation/event-stream.md) | What a consumer can rely on, and the three things that will otherwise cost you an afternoon |
| [commitments.md](documentation/commitments.md) | The three Merkle constructions, their exact preimages, and their test vectors |

**Operating it**

| | |
|---|---|
| [upgrades.md](documentation/upgrades.md) | What an upgrade may and may not change, who may perform one, and the migration path when it may not |
| [deployment.md](documentation/deployment.md) | Every on-chain object a deployment depends on, per network, with its custody |

Each package also carries a `docs/` folder — `events.md` and `event-schema.json` are the event
contract an off-chain consumer decodes against.

## Repository layout

| Path | Contents |
|---|---|
| `Mainnet Walrus Contract Manager/warlot protocol/` | The protocol package. Source of truth. |
| `Testnet Walrus Contract Manager/` | The same package, resolved against Walrus testnet contracts. |
| `Mainnet Walrus Contract Manager/WLT/` | Reserved. Not implemented. |
| `waitlist/` | Independent NFT waitlist package. Not part of the protocol. |

The two contract folders are one package with two dependency resolutions, mainnet Walrus
contracts for one, testnet for the other. `sources/`, `tests/`, `docs/` and the package `README.md`
are kept byte-identical; only `Move.toml` differs, and `scripts/check-events.sh` enforces that.

## Building

Requires the [Sui CLI](https://docs.sui.io/references/cli). This tree is built and tested with:

```bash
sui --version
# sui 1.73.1-ff1fe0ec4551
```

```bash
cd "Mainnet Walrus Contract Manager/warlot protocol"
sui move build
sui move test
# Test result: OK. Total tests: 282; passed: 282; failed: 0
```

Build the **mainnet** package when you want to see warnings. A package directory carrying a
`Published.toml` compiles with its warnings suppressed, and the testnet package has one, so it
reports clean whatever the sources say.

The package depends on the Walrus `wal` and `walrus` Move packages, fetched from
[MystenLabs/walrus](https://github.com/MystenLabs/walrus) at a pinned revision. Build output goes
to `build/`, which is not tracked.

Every static contract the repository keeps about itself — emitter coverage, event declarations,
named aborts, reachability, version-gate coverage, the event reference, and the two packages being
identical — is checked by one script:

```bash
./scripts/check-events.sh
# All event checks passed.
```

## Quickstart against testnet

```bash
sui client active-env
# testnet
```

Read the deployed system — its version, the storage terms it sells and the horizon they sit inside:

```bash
sui client object 0x3dcce443971e28376d1556ea8a01a0b08477d322692fae00b84914de7de41096
```

Register an account on it. This is the transaction that created the `Registry` and `User` recorded
in [deployment.md](documentation/deployment.md):

```bash
sui client call \
  --package 0x466c3980d0f8603c3c0bfa64a23c88d36c4ee492cd5a62d3a0e95060a1a3d237 \
  --module entry_register --function all_register_user_publicly \
  --args 0x3dcce443971e28376d1556ea8a01a0b08477d322692fae00b84914de7de41096 "warlot-main" 0x6
```

`0x6` is the Sui `Clock`. The username is yours to choose. Registration raises `WalletCreated`,
`UserRegistered` and `UserJoinedSystem`, in that order.

From there, [flows.md](documentation/flows.md) has the call sequences for uploading, creating a
file, writing a revision and renewing.

## Related repositories

Neither service below is required to use the protocol. Renewal is permissionless by design, so
anyone may run their own executor ,  these are reference implementations, not privileged components.

| Repository | Purpose |
|---|---|
| [`warlot-renew-bot`](https://github.com/warlot-lab/warlot-renew-bot) | Executes renewal mandates by submitting `extend_blob` transactions |
| [`warlot-indexer`](https://github.com/warlot-lab/warlot-indexer) | Consumes protocol events and maintains a queryable view |

Every event the protocol raises is declared under `sources/events/` and nowhere else, so one
package-scoped filter returns the whole stream however many modules declare into it. See
[event-stream.md](documentation/event-stream.md).

## Security

Report vulnerabilities privately. Do not open a public issue. See [SECURITY.md](SECURITY.md) for
the process, scope, and testing rules.

This code has not completed an external audit. Until it has, treat any deployment as experimental —
including the testnet one named above.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build conventions, the module architecture rules, and
what a reviewable change looks like. Participation is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Licence

Licensed under the Apache Licence, Version 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Third-party components and their licences are recorded in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Links

- [Walrus](https://www.walrus.xyz/), the storage layer
- [Sui](https://sui.io/), the execution layer
- [Walrus documentation](https://docs.wal.app/)
- [Sui Move documentation](https://docs.sui.io/concepts/sui-move-concepts)
