# Contributing

Thank you for considering a contribution. This document covers how the codebase is organised, what
a reviewable change looks like, and what will get a change sent back.

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Security issues go to
[SECURITY.md](SECURITY.md), never to a public issue or pull request.

## Before you start

**Open an issue first** for anything beyond a typo or a comment fix. On-chain code is expensive to
change after deployment, and a design discussion before implementation is cheaper for everyone than
a rejected pull request afterwards.

Please state, in the issue: what problem you are solving, why it belongs on chain rather than in a
consumer of the protocol, and what it costs ,  in bytes stored, in objects created, and in whether
it puts a shared object on a hot path.

## Getting set up

```bash
sui --version                                  # confirm your toolchain
cd "Mainnet Walrus Contract Manager/warlot protocol"
sui move build
sui move test
```

Changes to the Move sources must be mirrored into `Testnet Walrus Contract Manager/`. The two are
one package with two dependency resolutions; their sources are kept identical and only `Move.toml`
differs. A change that lands in one and not the other will be sent back.

## Architecture rules

These are not style preferences. They exist because the previous structure produced defects that
review did not catch.

**One module, one responsibility.** If a module's purpose does not fit in one sentence, it is two
modules. Over roughly 250 lines, justify it or split it.

**Dependencies point one way.** `entry` may import any domain; domains import downward only and
never import `entry`. `events` imports nothing internal, so it can never create a cycle. A change
that adds a sideways or upward import will be sent back.

**No junk drawers.** Every directory has a single domain. A `utils/` folder holding unrelated logic
is not acceptable.

**All events are declared in one module.** Sui's event filters match the module where an event type
is *defined*, and no package-wide filter exists ,  so a single declaring module is what lets a
consumer subscribe to the whole protocol with one filter. Emit *call sites* stay at the point of
state change, never hoisted into `entry`.

**Every loop is bounded by the caller.** No traversal of a global collection, no unbounded `vector`
on an object. Sui caps a single object at 250 KB and a transaction at 50 SUI of gas; an unbounded
structure is a latent deadlock, not a performance concern.

## Move conventions

Follow the [Sui Move best practices](https://docs.sui.io/develop/write-move/move-best-practices).
In particular:

- Section order within a module: imports, errors, constants, structs, events, method aliases,
  public functions, view functions, admin functions, package functions, private functions,
  test-only helpers. Mark them with `// === Section ===`.
- Error constants are PascalCase after an `E` prefix: `EInvalidTier`, `ENotOwner`. Abort with a
  named error, never a bare integer.
- Abilities are declared in the order `key, copy, drop, store`.
- Capability parameters come second: `config.withdraw(&cap, amount, ctx)`.
- A capability is **validated against the object it acts on**, never merely presented.
- No `transfer::transfer` inside core functions. Return the object and let the caller decide
  custody.
- `///` doc comments on every public function and struct field.

## Comments

Write comments a maintainer will need in a year. Do not comment the obvious, and do not narrate the
diff ,  no `FIXED`, `NEW`, `UPDATED`, or first-person ownership tags. Version control records what
changed; comments record why the code is the way it is.

## Tests

**Every behavioural change needs a test that fails without it.** A test that passes both before and
after proves nothing.

For a bug fix, write the failing test first and include it in the pull request. For anything
touching authority ,  permissions, capabilities, passes, deny lists ,  include the negative case:
prove the unauthorised party is *refused*, not merely that the authorised one succeeds.

## Pull requests

Keep them to one concern. A pull request that restructures code *and* changes behaviour cannot be
reviewed properly, because the reader cannot tell which diff hunks are moves and which are changes.
Split them.

In the description, state: what changed, why, what you tested, and anything you deliberately did
not do. If your change alters a public function signature, an object layout, or an event schema,
say so explicitly ,  those are breaking changes for every consumer of the protocol.

## What gets sent back

- Behaviour changed without a test that fails without it.
- A restructure and a behaviour change in the same pull request.
- An unbounded loop, or an unbounded `vector` stored on an object.
- A new field on an on-chain object with no stated reason it must be on chain.
- A sideways or upward import between domains.
- Mainnet and testnet sources left out of sync.
- A capability accepted but not validated against its target.
- A security issue submitted publicly.

## Licence

By contributing, you agree that your contributions are licensed under the
[Apache Licence 2.0](LICENSE), the same terms that cover this project.
