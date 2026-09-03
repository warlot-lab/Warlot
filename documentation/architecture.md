# Architecture

## What the contract holds

Three things, and deliberately nothing else.

| | |
|---|---|
| **Authority** | who may act on whose behalf, and what they may do — granular and revocable |
| **Value** | per-user balances and the protocol treasury |
| **Commitments** | the cryptographic anchors that make off-chain data verifiable |

It does not hold file bytes; Walrus does. It does not hold file names, descriptions or aggregate
counters. Those are labels and running totals no contract reads, so they belong in a database, and
putting them on chain would mean paying consensus for them and keeping them consistent for ever.

What the chain holds in their place is a **commitment**: a 32-byte Merkle root binding logical
paths to the content hashes they resolve to. A database can serve `project/bucket/config.json`
quickly; the root is what stops it serving the wrong bytes. This is also why an operator holding
`can_set_root` is the most carefully fenced credential in the protocol — it is the one that decides
which content answers to which name.

## The objects

| Object | Ownership | Holds |
|---|---|---|
| `SystemConfig` | shared | fees, storage tiers, the vault, the version, the operator set, and every `User` as a dynamic object field |
| `Registry` | owned by the user | the user's public label and which system they belong to |
| `User` | dynamic object field on `SystemConfig` | delegations, the operator role, the wallet, the project-holder marker |
| `BlobConfig` | shared | the blobs, their storage term, the renewal mandate, the owner, and any standing custody offer |
| `InnerFile` | shared | a mutable document's head, its bounded rollback window, its fallback, and its terms for operators |
| `WriterPass` | owned by the delegate | authority to write one named file |
| `AdminCap` | owned | administers one system; `original` or `duplicate` |
| `ProjectHolder` | shared | one account's projects, each with its database and its file-set root |

**Almost nothing is owned by Sui.** `BlobConfig`, `InnerFile`, `ProjectHolder` and `SystemConfig`
are all shared objects carrying an `owner` or `admin` **field** that is the real authority. The
reason is mechanical and worth stating once: an owned object can only enter a transaction its owner
signed, and one transaction cannot take two different addresses' owned objects. An owned
`ProjectHolder` could therefore never appear in a delegate's or an operator's transaction at all —
which is the whole surface built on top of it. Sui ownership would have made delegation impossible.

The exceptions are the two credentials, `WriterPass` and `AdminCap`, and they are owned precisely
because holding one *is* the authority. A pass in a delegate's account cannot be reached by the file
owner, which is why revocation is a record kept on the **file** rather than a destruction of the
pass.

## The domain ladder

```
sources/
├── entry/        the only surface a client calls
├── events/       every event struct and its emitter
├── system/       configuration, admin capability, treasury, version
├── identity/     registry, user, delegated permissions, wallet
├── storage/      blob configs, tiers, renewal accounting, compaction
├── innerfile/    mutable-state anchoring on immutable storage
└── product/      projects, their databases and their commitments
```

```
entry     ──► events, system, identity, storage, innerfile, product
innerfile ──► storage, identity, system
product   ──► storage
storage   ──► identity, system
identity  ──► system
system    ──► version
events    ──► (sui::event only)
```

Three invariants, each checked by `scripts/check-events.sh` rather than left to review:

1. **No domain imports `entry`.** The entry layer composes domains; a domain that reached back up
   into it would make the composition circular and the entry surface untestable in isolation.
2. **No domain imports sideways or upward.** `identity` never imports `storage`. Where two domains
   must be composed — registration touches `identity` and `system`, upload touches `identity` and
   `storage` — that composition happens in `entry`.
3. **`events` imports nothing internal**, so any module may import it without risking a cycle. This
   is what lets a module announce from the point of state change rather than returning a value up
   to the entry layer for the entry layer to announce.

`innerfile` and `product` are peers, not a stack: both sit directly above `storage`, and neither
imports the other. `product` reaches `storage` for `file_set`, the Merkle commitment a project's
file set resolves against.

### Why every event lives under `sources/events/`

One package-scoped event-type filter returns the protocol's whole history, however many modules
declare into it. An event declared in a domain module would still be emitted and still be indexed,
but it would sit outside the surface `docs/events.md` describes — so a consumer that had built
against that document would silently miss it. `check-events.sh` refuses any `event::emit` outside
`sources/events/`, and refuses any emitter with no call site.

## The version gate

Every public entry point taking a `SystemConfig` asserts the stored version against the package's
before it does anything else. After a package upgrade the whole surface is closed until an admin
calls `migrate_version`. See [upgrades.md](upgrades.md).
