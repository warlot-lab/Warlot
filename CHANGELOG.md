# Changelog

All notable changes to this project are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Because this is on-chain software, note that a published Move package's **on-chain version** is
distinct from the version below. A release entry states both when a deployment occurs.

## [Unreleased]

Nothing yet.

## [0.1.0] - 2026-09-04

First tagged release. **Deployed to Sui testnet; not deployed to mainnet, and not audited.**

| | |
|---|---|
| Package | `0x466c3980d0f8603c3c0bfa64a23c88d36c4ee492cd5a62d3a0e95060a1a3d237` |
| Network | Sui testnet |
| On-chain package version | `1` |
| Upgrade policy | `0`, `COMPATIBLE` |

The mainnet deployment will be a **fresh publish with new ids for everything**, not an upgrade of
the testnet package. Object layouts and public signatures are frozen for the published package,
because Sui's compatibility check refuses to change either.

### Added

- **Storage lifecycle.** Blobs are taken into custody under a `BlobConfig` carrying a storage term
  and a renewal mandate. Renewal is permissionless: anyone may execute a mandate the owner set,
  and nobody may change one they did not set.
- **Indefinite mandates.** A mandate is either a count of renewal cycles or no limit at all.
- **Inner files.** A mutable head with a bounded rollback window, a commit per revision, and a
  draft queue for writes proposed rather than made.
- **Projects.** A `ProjectHolder` whose `admin` is the authorization root a backend reads from
  chain rather than deciding for itself, a database inner file per project, and a file-set root
  committing logical paths to the content that answers to them.
- **Delegation.** Six permission bits, granted per address or to the operator role, each revocable
  by the account that granted it.
- **The operator model.** A credential for a backend that rotates signing keys: three independent
  gates — the capability is live, the account admits it, the object admits it — each revocable by a
  different party. Authority follows the capability slot rather than a wallet, so key rotation
  writes nothing on chain.
- **Compaction.** Many configs superseded by one quilt, under a plan that refuses a target whose
  owner or policy moved between opening and closing it.
- **Custody transfer.** A config is offered and accepted rather than pushed, and any other move of
  ownership voids a standing offer.
- **Upgrade authority.** The `UpgradeCap` publishing mints is held inside a shared
  `UpgradeAuthority`, not in a wallet. Authorising an upgrade, tightening the policy and making the
  package immutable all require the original `AdminCap`, and each step raises an event.
- **Documentation.** Thirteen documents under `documentation/`, covering the architecture, every
  stored object, the permission and operator models, custody, the worked flows, all public entry
  points, every bound and its reason, the three Merkle constructions, the event stream, what the
  protocol refuses, the upgrade boundary, and the deployment state.

### Fixed

- Retuning the tier table no longer freezes files bought on a term it drops. A storage term is
  validated where it is bought, not on every revision of a file whose term cannot be changed.
- `create_pass` refuses a duration already in the past. Zero is the sentinel for a pass that never
  decays, and the path was previously unchecked.
- The `ProjectHolder` domain is reachable. Nothing could construct one before.
- An operator no longer chooses the operator policy of a file it creates.

### Security

- The original `AdminCap` has **no expiry and no revocation**, and it is now also the only key that
  can replace the package. This is recorded in `documentation/deployment.md` as the item to settle
  before mainnet, not as something solved.
- The first package published from this account remains upgradable by that account, outside the
  authority model this release introduces. It governs code nothing points at any more.
- No upgrade has been executed through a validator. The transaction shape parses under preview and
  is documented; the first real upgrade is its test.

[Unreleased]: https://github.com/warlot-lab/Warlot/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/warlot-lab/Warlot/releases/tag/v0.1.0
