# The three commitments

`commit::root`, `file_set::root` and `id_set::root` look alike and are deliberately not
interchangeable. Anyone recomputing a root off chain needs this exactly right: getting it subtly
wrong reads as tampering rather than as a formatting difference, because the chain has no way to
tell the two apart.

All three are SHA-256 binary Merkle trees, 32 bytes wide, folding a level by pairing left to right
and duplicating the last node when the level is odd. **Everything else about them differs**, and
each difference is load-bearing.

---

## The differences, in one place

| | `commit::root` | `file_set::root` | `id_set::root` |
|---|---|---|---|
| Attests | a **sequence** of operations | a **set** of `(path, content_hash)` pairs | a **set** of object ids |
| Input | `&vector<vector<u8>>`, by reference | `vector<FileEntry>`, by value | `vector<ID>`, by value |
| Sorted before folding | **never** | yes, ascending on raw path bytes | yes, ascending on raw id bytes |
| Leaf prefix | `0x00` | `0x00` | **`0x02`** |
| Node prefix | `0x01` | `0x01` | `0x01` |
| Duplicates | not checked | refused, `EDuplicatePath` | refused, `EDuplicateId` |
| Empty input | **aborts**, `EEmptyCommit` | 32 zero bytes | 32 zero bytes |
| Size cap | none in the module | 666, `EFileSetTooLarge` | 666, `EIdSetTooLarge` |
| Computed on chain | **no** — only its width is checked | yes, once, in `compaction::register` | yes, once, in `compaction::register` |

The input is taken **by value** in the two set constructions precisely because they sort: the root
is a function of the set, so two servers that replayed the same uploads in a different order have to
agree. `commit::root` takes a reference and never reorders, because the sequence of operations is
itself part of what is being attested — two histories that applied the same operations in a
different order must not share a root.

---

## The preimages

Read these as byte concatenations. `||` is concatenation, `H` is SHA-256, and every hash and root is
exactly 32 raw bytes — never hex, never base64, at the point it is hashed.

### `commit` — a revision's commitment

```
leaf(op_hash)  =  H( 0x00 || op_hash )                       op_hash is exactly 32 bytes
node(l, r)     =  H( 0x01 || l || r )
```

Fold in the order given. Never sort. An empty input has no root and aborts.

### `file_set` — what a name resolves to

```
leaf(path, content_hash)  =  H( 0x00 || u32_be(len(path)) || path || content_hash )
node(l, r)                =  H( 0x01 || l || r )
```

`u32_be(n)` is `n` as four big-endian bytes; the path is bounded at 1024 bytes so it always fits.
`content_hash` is exactly 32 bytes. Sort ascending on raw path bytes, refuse a repeat, then fold.

**The length prefix is what stops `("docs/a", H)` and `("docs", "/a" || H)` serialising to the same
bytes.** Without it the pair separator would be ambiguous and two different mappings could share a
root.

### `id_set` — what a compaction replaced

```
leaf(id)    =  H( 0x02 || id_bytes )                          id_bytes is exactly 32 bytes
node(l, r)  =  H( 0x01 || l || r )
```

Sort ascending on raw id bytes, refuse a repeat, then fold.

---

## Why `id_set` alone has a different leaf prefix

An object id is exactly as wide as an operation hash. With a `0x00` prefix, a leaf over an id would
be **byte-identical** to a commit leaf over the same 32 bytes:

```
commit leaf   H( 0x00 || X )     X: 32 bytes
id_set leaf   H( 0x00 || X )     the same 32 bytes — the same hash
```

So `id_set::root([a, b])` and `commit::root([a, b])` over the same values in the same order would be
the same 32 bytes, and two attestations that mean entirely different things would be
indistinguishable. `0x02` separates them.

`file_set` needs no such change even though it shares `0x00`, and the reason is structural rather
than lucky: a commit leaf's preimage is exactly 33 bytes, while a file-set leaf's is
`1 + 4 + len(path) + 32` with `len(path) ≥ 1`, so at least 38. The two preimage spaces cannot
overlap.

Interior nodes keep `0x01` in all three, because a node's preimage is already separated from every
leaf's by the prefix its children carry.

The leaf/node separation itself is RFC 6962's, and it is load-bearing rather than decorative: leaves
and interior nodes are hashed in disjoint spaces so that no leaf can be presented as a subtree and no
subtree as a leaf.

---

## The empty set, and why one of them refuses it

`file_set` and `id_set` both return **32 zero bytes** for an empty input — not the hash of nothing,
and not an empty vector. A scope holding no files is a state the chain has to be able to attest to
(a project opens committed to exactly this), and a config may legitimately carry a layout that
supersedes nothing.

`commit::root` aborts instead. A revision is a change, and a commit over no operations attests to
nothing that happened.

---

## Where each root lives, and which ones the chain derives

This is the distinction most easily missed. **Only the compaction receipt carries roots the chain
computed.** Everywhere else a root is a value the caller supplies and the chain checks the width of.

| Root | Stored on | Set by | Chain derives it? |
|---|---|---|---|
| `FileData.commit` | a revision — the head, the window, the fallback, a draft | every write, from the `commit` argument | **no** — `commit::assert_valid_root` checks 32 bytes and nothing more |
| `Project.file_set_root` | a project | `set_file_set_root[_as_operator]` | **no** — `file_set::assert_valid_root`, a width check |
| `Layout.file_set_root` | a compacted config | `compaction::register` | **yes**, from the `paths` and `content_hashes` the call carries |
| `Layout.superseded_root` | the same | `compaction::register` | **yes**, from the ids `supersede` actually read |

`commit::root` is a public helper with **no call site in `sources/`**. The set it folds — the
operation log — lives off chain and can be far larger than a transaction, so the service computes
the root and the chain stores it. That is precisely why the construction is frozen and published:
the contract cannot check it, so the format is the only thing holding the two sides together.

The two roots on a `Layout` are the opposite case and are deliberately so. Neither is an argument, so
neither can be asserted, and a layout that does not match what was submitted cannot be registered.
That is what makes it a receipt rather than a claim.

`Project.file_set_root` opens at `file_set::empty_root()` and is length-checked on every move; the
event carries `previous_root`, so the change stays auditable even though the value it replaced is
gone.

---

## Recomputing one, and proving one member

`leaf` and `node` are public in both set constructions so that a holder of **one** entry can check it
against the root on chain by folding an audit path, without being handed every other member of the
set. `commit`'s are private — the log's operations are the service's, and there is no on-chain root
to fold against that the service did not supply.

Two ordering helpers exist for callers who assemble a set themselves:

- `file_set::assert_ascending_paths(paths)` and `id_set::assert_ascending(ids)` check the order in one
  pass, and `id_set::is_before(a, b)` compares two ids.
- They exist because the internal sorts are **insertion sorts** and therefore quadratic. Measured
  against the Move test runner's execution bound, a set of 666 entries in arbitrary order does not
  finish while the same 666 already in order does. `compaction::register` therefore requires
  `paths` ascending, and `compaction::supersede` requires predecessors named in ascending id order —
  a caller who has to supply the set anyway is the cheaper side of that trade.

Requiring the caller's order to be the canonical one has a second effect: the list the event carries
*is* the order the root was folded in, so a consumer recomputing the commitment has nothing left to
infer.

---

## Paths are checked, never normalised

`file_set::new_entry` refuses a path that is not already canonical rather than repairing it. Two
callers who disagreed about whether `docs//a.txt` and `docs/a.txt` are the same path would compute
different roots for the same files.

| Rule | Abort |
|---|---|
| Not empty | `EEmptyPath` |
| At most 1024 bytes | `EPathTooLong` |
| No leading or trailing `/`, no repeated `/`, no `.` or `..` segment | `EPathNotCanonical` |
| Every byte above `0x1F` and not `0x7F` | `EPathControlCharacter` |
| Content hash exactly 32 bytes | `EInvalidContentHash` |

`/` (`0x2F`) is the only separator; nothing else is one.

**Unicode normalisation is the caller's.** NFC is not decidable in Move at any sensible cost, so it
is applied before the bytes arrive or not at all.

Ordering is on **raw bytes**, and that matters more than it looks: `Z` is `0x5A` and `a` is `0x61`, so
a byte-wise order puts `Z` first, where a case-insensitive collation would not. A database sorting
under a non-C collation disagrees with this construction, which is exactly why the format pins raw
bytes.

---

## Test vectors

The constructions are held to published vectors rather than to a description of the algorithm,
because the whole point is that somebody else recomputes them independently and lands on the same 32
bytes. All three sets live in the packages' test suites:
`tests/regression/commit_root_tests.move`, `file_set_root_tests.move` and `layout_tests.move`.

The three-entry case is the one that matters in each: it is the only vector that exercises the
odd-level duplication rule, and an implementation that gets that wrong still passes the one- and
two-entry cases. For the two set constructions it exercises the sort at the same time.

### `commit`, over `sha2_256("op1")`, `"op2"`, `"op3"` in that order

```
op1                    7d3c6b8d51ac8ec79a2adbf98045944f934c1279a57f689cd5ce997fc223b48e
root(op1)              690f5b1479190da0d494b1b813f3a0d67a087e7f968451d01bd50c5218750bcf
root(op1, op2)         4b10fba8cae3423c4999ca7516223b79f6ae73148d7aa87145c82115f9a3bbae
root(op1, op2, op3)    30b053da8def73ef2fab82f86514ff5943be50ff336c2251201466cd0d1d0b95
```

Reversing the order changes the root. That is the property being pinned.

### `file_set`, over three files whose contents are the single bytes `A`, `B`, `C`

```
docs/a.txt → sha2_256("A") = 559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd
docs/b.txt → sha2_256("B") = df7e70e5021544f4834bbee64a9e3789febc4be81470df629cad6ddb03320a5c
img/c.png  → sha2_256("C") = 6b23c0d5f35d1b11f9b683f0b0a617355deb11277d91ae091d399c655b87940d

leaf(docs/a.txt)       c99258cf99b88e0eff05a66a1604eb6dfe8ba4be824ea89293fc16b504f7cb66
leaf(docs/b.txt)       d72257f9161f0a3bdd6878201df632cd409715d3fe0a40bc076d73f96ad12e20
leaf(img/c.png)        6e8a1ffed1380919964deb6130d595fe5ea1b812c20c70c87a1f85c69f012af1

root()                 0000000000000000000000000000000000000000000000000000000000000000
root(a)                c99258cf99b88e0eff05a66a1604eb6dfe8ba4be824ea89293fc16b504f7cb66
root(a, b)             7e8e4fba1248d0edc9f3069f57fb53efecb6ed206a60eb35157b1cfd087884af
root(a, b, c)          f54b57602bd89af3a5e9271c664b77641b176665c51d604e277e1a85e62ae60b
```

Every arrival order gives the same three-entry root. Swapping which content each path resolves to
moves it, and so does renaming one file — the commitment binds the pairing, not either half.

### `id_set`, over the same three 32-byte values read as object ids

```
id_a = sha2_256("A")   id_b = sha2_256("B")   id_c = sha2_256("C")
sorted ascending on raw bytes, that is a, c, b

leaf(id_a)             10db190a64af4a4158e0aa8567952a731aff3827e175c6e190246f3f2a4761b8
leaf(id_b)             2d261e26ed5741759d68b371cecc45695531bbaefa0277271baf14a4844fb4fd
leaf(id_c)             e680b41655206ff60b20e1b3304eff634006671a65d640532468462f4c394132

root()                 0000000000000000000000000000000000000000000000000000000000000000
root(id_a)             10db190a64af4a4158e0aa8567952a731aff3827e175c6e190246f3f2a4761b8
root(id_a, id_b)       f43c1b9481a3fc458dea6a940fdff48666d726dc4f0a6f6ea6cb49bf1d7ee879
root(id_a, id_b, id_c) ed11bb3b80fe70343318515f0be1f931ed330d2caddfc118b26bae5c23b59fa7
```

Compare the leaves here against `file_set`'s: the same 32 bytes go in and different bytes come out,
which is the `0x02` prefix doing its one job.

---

## On the wire

Every root above is a `vector<u8>` in Move, and **a `vector<u8>` arrives from Sui as a base64
string**, not as an array of numbers and not as hex. That applies to every `commit` field, both root
fields on the project events, and on `LayoutRegistered` both roots plus every element of `paths` and
`content_hashes` — a `vector<vector<u8>>` is a JSON array of base64 strings. A decoder must
base64-decode them before comparing against anything computed locally. See
[event-stream.md](event-stream.md).
