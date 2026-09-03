# Warlot protocol documentation

For someone arriving with no context. The `docs/` folder inside each package is reference material
for people who already know the design; this is the part that explains it.

| | |
|---|---|
| [architecture.md](architecture.md) | What the contract holds, the domain ladder, and why the dependency rule is shaped that way |
| [permissions.md](permissions.md) | The six bits, what each confers, and the difference between an address delegation and the operator role |
| [operators.md](operators.md) | The credential a rotating backend signs with: three independent gates, and who revokes each |
| [custody.md](custody.md) | Who owns a `BlobConfig` on every path that creates one, how custody moves, and why deletion is not delegable |
| [flows.md](flows.md) | Worked call sequences, with the events each raises |
| [entry-points.md](entry-points.md) | Every public entry point, with what authorises it and what it refuses |
| [refusals.md](refusals.md) | What the contract will not do, and why |
| [upgrades.md](upgrades.md) | What an upgrade may and may not change, and the migration path when it may not |
| [deployment.md](deployment.md) | Every on-chain object a deployment depends on, per network, with its custody |

## Start here

Warlot sits on top of [Walrus](https://www.walrus.xyz/). Walrus stores bytes and hands back a
`Blob` object carrying prepaid storage that expires at a fixed epoch. Warlot is the layer that
keeps that storage from expiring, on a mandate the user sets once and **anyone** can execute.

That last word is the design. A user states what they want renewed, how far ahead and how many
times; the mandate lives on chain in public; and `renew_blob` takes no capability and no allowlist.
If Warlot disappears, the user, a competitor or a community bot keeps every blob alive without our
cooperation.

Three things follow from it, and most of the rest of this documentation is consequences:

- **The chain holds authority, value and commitments — and nothing else.** No file bytes, no names,
  no counters. See [architecture.md](architecture.md).
- **Every delegation is granular and revocable**, and the levers are meant to be pulled
  independently. See [permissions.md](permissions.md).
- **There is no pause switch, no admin delete and no way for a delegate to withdraw.** Those are
  not omissions. See [refusals.md](refusals.md).
