# Third-Party Notices

Warlot Protocol depends on the components below. Each is distributed under its own licence, which
governs that component only and confers no rights in Warlot Protocol itself.

This file records dependencies of the Move packages and of the off-chain services in this
repository. It is maintained by hand; when a dependency is added, changed, or removed, update it in
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

The services in `RenewBot/` and `sui-indexer/` are Go modules. Their complete, resolved dependency
sets are recorded in their respective `go.mod` and `go.sum` files, which are authoritative.
Principal direct dependencies:

| Component | Version | Licence | Used by |
|---|---|---|---|
| [`github.com/lib/pq`](https://github.com/lib/pq) | v1.10.9 | MIT | both |
| [`github.com/joho/godotenv`](https://github.com/joho/godotenv) | v1.5.1 | MIT | RenewBot |
| [`github.com/block-vision/sui-go-sdk`](https://github.com/block-vision/sui-go-sdk) | v1.0.8 | Apache-2.0 | RenewBot |
| [`github.com/resend/resend-go/v2`](https://github.com/resend/resend-go) | v2.20.0 | MIT | RenewBot |

Licences above were read from the resolved module cache, not inferred from the project pages.

To regenerate the full transitive list for either service:

```bash
cd RenewBot && go list -m -json all
```

---

## Reporting an omission

If a component is used here and is not listed, or is listed with the wrong licence, that is a
defect. Report it as described in [SECURITY.md](SECURITY.md) or open an issue.
