# Warlot Protocol

Sui Move contracts for storage-lifecycle management on [Walrus](https://www.walrus.xyz/).

Walrus stores bytes and issues a `Blob` object carrying a prepaid storage resource that expires at
a fixed epoch. Warlot is the layer that keeps that resource from expiring, on a mandate the user
sets once, executable by anyone.

> **Status: pre-release.** Under active development and not deployed to Sui mainnet. Interfaces,
> object layouts and the event schema are all still changing. Do not build against this yet.

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

## Repository layout

| Path | Contents |
|---|---|
| `Mainnet Walrus Contract Manager/warlot protocol/` | The protocol package. Source of truth. |
| `Testnet Walrus Contract Manager/` | The same package, resolved against Walrus testnet contracts. |
| `Mainnet Walrus Contract Manager/WLT/` | Reserved. Not implemented. |
| `waitlist/` | Independent NFT waitlist package. Not part of the protocol. |

The two contract folders are one package with two dependency resolutions, mainnet Walrus
contracts for one, testnet for the other. Their sources are kept identical; only `Move.toml`
differs.

## Building

Requires the [Sui CLI](https://docs.sui.io/references/cli). Verify your toolchain first:

```bash
sui --version
```

```bash
cd "Mainnet Walrus Contract Manager/warlot protocol"
sui move build
sui move test
```

The package depends on the Walrus `wal` and `walrus` Move packages, fetched from
[MystenLabs/walrus](https://github.com/MystenLabs/walrus) at a pinned revision. Build output goes
to `build/`, which is not tracked.

## Related repositories

Neither service below is required to use the protocol. Renewal is permissionless by design, so
anyone may run their own executor — these are reference implementations, not privileged components.

| Repository | Purpose |
|---|---|
| [`warlot-renew-bot`](https://github.com/warlot-lab/warlot-renew-bot) | Executes renewal mandates by submitting `extend_blob` transactions |
| [`warlot-indexer`](https://github.com/warlot-lab/warlot-indexer) | Consumes protocol events and maintains a queryable view |

All protocol events are declared in a single Move module, so a consumer can subscribe to the entire
event stream with one filter.

## Security

Report vulnerabilities privately. Do not open a public issue. See [SECURITY.md](SECURITY.md) for
the process, scope, and testing rules.

This code has not completed an external audit. Until it has, and until the status banner above
changes, treat any deployment as experimental.

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
