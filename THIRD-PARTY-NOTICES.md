# Third-Party Notices

Warlot Protocol depends on the components below. Each is distributed under its own licence, which
governs that component only and confers no rights in Warlot Protocol itself.

This file records the dependencies of the Move packages in this repository. It is maintained by
hand; when a dependency is added, changed, or removed, update it in
the same change.

---

## Move packages

### Walrus, `wal`, `walrus`

- **Source:** <https://github.com/MystenLabs/walrus>
- **Copyright:** Walrus Foundation
- **Licence:** Apache Licence 2.0
- **Used for:** the `Blob` and `Storage` resources this protocol manages, and the `extend_blob`
  entry point renewal calls.

Declared in each package's `Move.toml` as `license = "Apache-2.0"`, with
`SPDX-License-Identifier: Apache-2.0` on the source files.

### Sui Framework, `sui`, `std` (MoveStdlib)

- **Source:** <https://github.com/MystenLabs/sui>
- **Copyright:** Mysten Labs, Inc.
- **Licence:** Apache Licence 2.0
- **Used for:** the Move standard library and the Sui object model, resolved implicitly by the Sui
  CLI as framework dependencies.

---

## Off-chain services

The renewal executor and the event indexer live in separate repositories and carry their own
third-party notices:

- [`warlot-renew-bot`](https://github.com/warlot-lab/warlot-renew-bot)
- [`warlot-indexer`](https://github.com/warlot-lab/warlot-indexer)

Nothing in this repository depends on them, and they confer no rights in this project.

---

## Reporting an omission

If a component is used here and is not listed, or is listed with the wrong licence, that is a
defect. Report it as described in [SECURITY.md](SECURITY.md) or open an issue.
