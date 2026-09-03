# The permission model

A user delegates by writing a row of six booleans. There are two places a row can live, they are
granted and revoked independently, and a check passes if **either** says yes.

## The six bits

| Bit | Confers | Needs `add_blob_to_address` to be useful? |
|---|---|---|
| `add_blob_to_address` | store blobs billed under the owner's account | — it *is* the root |
| `create_inner_file` | create an `InnerFile` owned by the owner | **yes** |
| `create_writer_pass` | mint a `WriterPass` on the owner's file | **yes**, for an admin pass |
| `can_init_db` | create a project, open a project holder, name a project's database | **yes**, for the database |
| `can_compact` | register a compaction layout against the owner's configs | **yes**, to write the new quilt |
| `can_set_root` | move a project's file-set root | **no** — see below |

### `add_blob_to_address` is the root grant

Every path that causes bytes to be billed under the owner passes through `store::raw_store_blob`,
and that call asks for this bit and no other. So `create_inner_file`, `can_init_db` and a
compaction target are all **inert without it**: each of them stores, and each of those stores is
refused.

Two consequences worth holding on to:

- A grant naming `create_inner_file` while withholding `add_blob_to_address` has granted nothing
  exercisable. It is not an error, and nothing warns about it.
- **Revoking `add_blob_to_address` alone stops every delegated write on the account.** It is the
  one lever that does.

### `can_set_root` is the deliberate exception

Moving a root replaces a 32-byte commitment and stores nothing, so it neither needs
`add_blob_to_address` nor is stopped by withdrawing it. That gives an account two independent
levers, which is the entire reason it is a bit of its own rather than a reuse of `can_init_db`:

| Revoke | Stops | Keeps running |
|---|---|---|
| `add_blob_to_address` | every delegated write | root moves, renewal, reads |
| `can_set_root` | root moves — the commitment freezes at its last honest value | every write, renewal, reads, database anchoring |

Under attack you usually want the second. Folding the root into `can_init_db` would have meant
revoking it also stopped project creation and database initialisation — coarser than you need, in
exactly the moment you need precision.

The reasoning is the codebase's own: `can_compact` is delegable *because writing a new quilt is
additive* — it destroys nothing and supersedes nothing until the owner acts. `set_file_set_root`
**overwrites** the previous root. By that same test it is the less delegable of the two, and the
less delegable thing gets the finer switch.

## The two places a row lives

### An address delegation

```move
entry_permission::grant(system, owner, delegate, add_blob, inner_file, writer_pass, init_db, compact, set_root, ctx)
entry_permission::replace_grant(…)   // wholesale, so one call leaves exactly what you named
entry_permission::revoke(system, owner, delegate, ctx)
```

Keyed by the delegate's **address**, stored in a `Table` attached to the `User` on first use. It
works with no capability at all and is unaffected by keys entering or leaving the operator set.
`grant` refuses an address that already holds a row (`EAlreadyDelegated`); moving an existing row is
`replace_grant`. The two are separate so that reaching for the blunt instrument cannot quietly widen
a delegation the owner meant to leave alone.

### The operator role

```move
entry_permission::grant_operator_role(system, owner, add_blob, inner_file, init_db, compact, set_root, ctx)
entry_permission::replace_operator_role(…)
entry_permission::revoke_operator_role(system, owner, ctx)
```

Keyed by **nothing** — that is the point. It is a single row attached to the `User`, and it counts
only when the caller presented a live operator credential. A backend rotating through sixteen
wallets satisfies it with any of them, and adding a seventeenth needs no user to act.

Note it takes **five** bits, not six: `create_writer_pass` is absent, because an operator can never
mint a pass. See [operators.md](operators.md).

`all_register_user_with_system_permission` grants the role every bit it can hold at registration,
so the ordinary path is that consent is given once and narrowed later.

## How a check resolves

`permission::effective_bits` reads both rows and **ORs** them:

```
bit = address_row[sender].bit  OR  (operator_presented AND operator_row.bit)
```

Neither row being absent is an error. A caller holding nothing gets every bit false and is refused
by whichever check asked, which is what names the missing bit rather than failing generically.

Two things follow:

- **An address grant survives everything about the operator set.** Retiring every slot does not
  touch it.
- **The two cannot be subtracted from each other.** Revoking the operator role does not remove a bit
  the same address also holds directly, and vice versa. To shut an address out completely, revoke
  both.

## The sender shortcut

`check_permission_add_blob` and its siblings return immediately when `ctx.sender() == owner`. An
account acting on itself consults no table, so a user who has never delegated anything holds no
delegation table at all and pays nothing for the possibility.

## Where file-level authority differs

The six bits are **account**-level. A single file adds two more layers, and neither is one of the
six:

- A `WriterPass`, minted per file by its owner, carrying a duration and optionally the draft-queue
  bypass. Revoked by recording its id on the file, because the pass itself lives in the delegate's
  account where the file owner cannot reach it.
- The file's three operator bits — `operators_allowed`, `operators_may_bypass_draft`,
  `operators_may_draft` — set by the owner and gated on the **sender**, never on a pass. A pass that
  could flip them would let an operator that had been shut out re-admit itself.
