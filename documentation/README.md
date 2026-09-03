# Warlot protocol documentation

For someone arriving with no context. The `docs/` folder inside each package is reference material for
people who already know the design; this is the part that explains it.

## Start here

Warlot sits on top of [Walrus](https://www.walrus.xyz/). Walrus stores bytes and hands back a `Blob`
object carrying prepaid storage that expires at a fixed epoch. Warlot is the layer that keeps that
storage from expiring, on a mandate the user sets once and **anyone** can execute.

That last word is the design. A user states what they want renewed, how far ahead and how many times;
the mandate lives on chain in public; and `renew_blob` takes no capability and no allowlist. If Warlot
disappears, the user, a competitor or a community bot keeps every blob alive without our cooperation.

Three things follow from it, and most of the rest of this documentation is consequences:

- **The chain holds authority, value and commitments — and nothing else.** No file bytes, no names,
  no counters. See [architecture.md](architecture.md).
- **Every delegation is granular and revocable**, and the levers are meant to be pulled
  independently. See [permissions.md](permissions.md).
- **There is no pause switch, no admin delete and no way for a delegate to withdraw.** Those are not
  omissions. See [refusals.md](refusals.md).

## The documents

**The shape of the thing**

| | |
|---|---|
| [architecture.md](architecture.md) | What the contract holds, the domain ladder, and why the dependency rule is shaped that way |
| [objects.md](objects.md) | Every stored object: what is inside it, what attaches to it and when, what can destroy it, and who may act on it |
| [bounds.md](bounds.md) | Every limit in the protocol, with the reason for it and what raising it would buy |

**Who may do what**

| | |
|---|---|
| [permissions.md](permissions.md) | The six bits, the dependency chain between them, and the two independent places a grant lives |
| [operators.md](operators.md) | The credential a rotating backend signs with: three independent gates, and who revokes each |
| [custody.md](custody.md) | Who owns a `BlobConfig` on every path that creates one, how custody moves, and why deletion is not delegable |
| [entry-points.md](entry-points.md) | All 62 public functions, each section shaped like its subject |
| [refusals.md](refusals.md) | What the contract will not do, and why |

**Building against it**

| | |
|---|---|
| [flows.md](flows.md) | Worked call sequences, with the events each raises, in order |
| [event-stream.md](event-stream.md) | What a consumer can rely on, and the three things that will otherwise cost you an afternoon |
| [commitments.md](commitments.md) | The three Merkle constructions, their exact preimages, and their test vectors |

**Operating it**

| | |
|---|---|
| [upgrades.md](upgrades.md) | What an upgrade may and may not change, and the migration path when it may not |
| [deployment.md](deployment.md) | Every on-chain object a deployment depends on, per network, with its custody |

## If you are

**writing an indexer** — [event-stream.md](event-stream.md), then [flows.md](flows.md) for the
orderings, then each package's `docs/events.md` for the fields.

**recomputing a root off chain** — [commitments.md](commitments.md), and nothing else until it
matches.

**running a renewal bot** — [event-stream.md](event-stream.md) § *Keeping storage alive*. You need two
event types and no notion of custody at all.

**integrating a backend that signs for users** — [operators.md](operators.md), then
[permissions.md](permissions.md), then [custody.md](custody.md) for the one row that surprises people.

**auditing** — [objects.md](objects.md) and [refusals.md](refusals.md), then
[entry-points.md](entry-points.md) for the gate on each call.
