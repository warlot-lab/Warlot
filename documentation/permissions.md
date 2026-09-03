# The permission model

Six booleans, and they are not six independent switches. One of them is the root the others hang off,
one is deliberately independent of it, and one gates far less than its name suggests. Getting that
graph right is most of understanding what a delegation actually confers.

There are two places a row of six can live. They are granted and revoked independently, and a check
passes if **either** says yes.

---

## `add_blob_to_address` is the root grant

Every path that causes bytes to be billed under the owner passes through `store::raw_store_blob`, and
that call asks for this bit and no other. So:

```
add_blob_to_address ─── the root. Nothing stores under the owner without it.
      │
      ├── create_inner_file    a file is created *with* its first revision, so the
      │                        creation stores. Without the root the store is refused
      │                        and no file is ever built.
      │
      ├── can_init_db          a project's database is an inner file, created the same
      │                        way. Same store, same refusal. (Opening a holder and
      │                        minting a project store nothing and work without it.)
      │
      └── can_compact          `register_layout` itself stores nothing — but the new
                               quilt it registers had to be stored first, and that
                               store is the one being refused.

can_set_root ─────────── independent. Moves a 32-byte commitment and stores nothing.

create_writer_pass ───── one branch of one call. See below.
```

Three consequences worth holding on to:

- **A grant naming `create_inner_file` while withholding `add_blob_to_address` has granted nothing
  exercisable.** It is not an error, and nothing warns about it.
- **Revoking `add_blob_to_address` alone stops every delegated write on the account.** It is the one
  lever that does.
- **`can_compact` is the partial case, and the wording matters.** A delegate holding it and nothing
  else can still register a receipt onto a config that already exists — the call reads a shared object
  and writes 95 bytes onto it. What they cannot do is *produce* the new quilt to register it onto. The
  additive half of a compaction is still gated by the root; the bookkeeping half is not.

---

## `can_set_root` is the deliberate exception

Moving a root replaces a 32-byte commitment and stores nothing, so it neither needs
`add_blob_to_address` nor is stopped by withdrawing it. That gives an account two independent levers,
which is the entire reason it is a bit of its own rather than a reuse of `can_init_db`:

| Revoke | Stops | Keeps running |
|---|---|---|
| `add_blob_to_address` | every delegated write | root moves, renewal, reads |
| `can_set_root` | root moves — the commitment freezes at its last honest value | every write, renewal, reads, database anchoring |

Under attack you usually want the second.

The reasoning is the codebase's own test, applied consistently: `can_compact` is delegable *because
writing a new quilt is additive* — it destroys nothing and supersedes nothing until the owner acts.
`set_file_set_root` **overwrites** the previous root. By that same test it is the less delegable of the
two, and the less delegable thing gets the finer switch. Folding it into `can_init_db` would have meant
revoking it also stopped project creation and database initialisation — coarser than you need, in
exactly the moment you need precision.

---

## `create_writer_pass` gates one branch of one call

Its name reads as *"may mint a `WriterPass` on the owner's files"*. It is narrower than that, and the
difference is worth knowing before you grant it or rely on withholding it.

`permission::check_writer_pass` has exactly **one** call site in the package: inside
`creation::new_file`, on the branch where `should_include_pass` is set and the caller is **not** the
owner. So the bit confers precisely one thing — *a delegate creating a file on the owner's behalf may
be handed a pass to that new file, in the same call.*

It does **not** gate `entry_file_access::create_pass`. That call is owner-only (`ENotFileOwner`) and
consults a different question entirely: for an **admin** pass it asks whether the recipient already
holds `add_blob_to_address` on the owner, through `grants_add_blob` — which is deliberately blind to
the operator role, because a pass is minted to an address and the role names none.

And the operator role can never hold the bit at all. See below.

---

## The six bits

Now the reference table, with the graph above already in hand.

| Bit | Confers |
|---|---|
| `add_blob_to_address` | store blobs billed under the owner's account — the root |
| `create_inner_file` | create an `InnerFile` owned by the owner; inert without the root |
| `create_writer_pass` | be handed a pass when creating a file on the owner's behalf, and nothing else |
| `can_init_db` | open the owner's project holder, mint projects, and name a project's database; the last is inert without the root |
| `can_compact` | register a compaction layout against the owner's configs; producing the quilt to register needs the root |
| `can_set_root` | move a project's file-set root; independent of the root grant |

These are **account**-level. A single file adds two more layers, and neither is one of the six — see
the end of this document.

---

## The two places a row lives

### An address delegation

```move
entry_permission::grant(system, owner, delegate, add_blob, inner_file, writer_pass, init_db, compact, set_root, ctx)
entry_permission::replace_grant(…)   // wholesale, so one call leaves exactly what you named
entry_permission::revoke(system, owner, delegate, ctx)
```

Keyed by the delegate's **address**, stored in a `Table` attached to the `User` on first use. It works
with no capability at all and is unaffected by keys entering or leaving the operator set.

`grant` refuses an address that already holds a row (`EAlreadyDelegated`); moving an existing row is
`replace_grant`, which refuses one that holds none. The two are separate so that reaching for the blunt
instrument cannot quietly widen — or narrow — a delegation the owner meant to leave alone. The bits are
written wholesale either way, so a grant against an address that already had one would take away
whatever the caller did not happen to name, while reporting the same success as a first grant.

`revoke` **removes the row** rather than zeroing it, so a revoked delegate is refused by the table
lookup itself and no row survives that could be mistaken for a delegation. Revoking an address that
holds nothing is not an error: a revocation that can abort is one that can fail at the moment it is
most needed.

### The operator role

```move
entry_permission::grant_operator_role(system, owner, add_blob, inner_file, init_db, compact, set_root, ctx)
entry_permission::replace_operator_role(…)
entry_permission::revoke_operator_role(system, owner, ctx)
```

Keyed by **nothing** — that is the point. It is a single row attached to the `User`, and it counts only
when the caller presented a live operator credential. A backend rotating through sixteen wallets
satisfies it with any of them, and adding a seventeenth needs no user to act.

Note it takes **five** bits, not six. `create_writer_pass` is not among them and cannot be: the
parameter is absent from both signatures, and `create_operator_role_state` writes `false` into the
field. So no call in the package can express the grant, which is a stronger statement than refusing it
at the entry point. See [operators.md](operators.md).

`all_register_user_with_system_permission` grants the role every bit it can hold at registration, so
the ordinary path is that consent is given once and narrowed later.

---

## How a check resolves

`permission::effective_bits` reads both rows and **ORs** them:

```
bit = address_row[sender].bit  OR  (operator_presented AND operator_row.bit)
```

Neither row being absent is an error. A caller holding nothing gets every bit false and is refused by
whichever check asked, which is what names the missing bit rather than failing generically.

Two things follow:

- **An address grant survives everything about the operator set.** Retiring every slot does not touch
  it.
- **The two cannot be subtracted from each other.** Revoking the operator role does not remove a bit
  the same address also holds directly, and vice versa. To shut an address out completely, revoke both.

There is one deliberate exception to the OR. `grants_add_blob` — the question `create_pass` asks before
minting an admin pass — reads the **address row only**. It answers a question about one named address,
and the operator role names none.

## The sender shortcut

`check_permission_add_blob` and its siblings return immediately when `ctx.sender() == owner`. An
account acting on itself consults no table, so a user who has never delegated anything holds no
delegation table at all and pays nothing for the possibility.

---

## Where file-level authority differs

The six bits are about an account. A single file adds two more layers, and neither is one of the six.

- **A `WriterPass`**, minted per file by its owner, carrying a duration and optionally the draft-queue
  bypass. Revoked by recording its **id** on the file, because the pass itself lives in the delegate's
  account where the file owner cannot reach it.
- **The file's three operator bits** — `operators_allowed`, `operators_may_bypass_draft`,
  `operators_may_draft` — set by the owner and gated on the **sender**, never on a pass. A pass that
  could flip them would let an operator that had been shut out re-admit itself.

The account-level grant of the operator role has already happened by the time a file exists, so the
file's bits are the pin that shuts one file against it. The routing they drive is in
[entry-points.md](entry-points.md).
