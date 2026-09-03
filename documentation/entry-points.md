# Every entry point

All 61 public functions in `sources/entry/`, with what authorises each and what it refuses.

**Every one of them asserts the system's version first**, aborting `EWrongPackageVersion` against a
system the package has moved past — except `migrate_version`, which is the call that clears that
state, and `supersede`, which takes no system. That gate is not repeated per row;
`scripts/check-events.sh` section 6 proves the coverage, and `version_tests.move` has one test per
row.

"Owner" below means the `owner` **field** on the object, not Sui ownership. Refusals list the named
aborts a caller can reasonably hit, not every abort reachable from every frame beneath.

---

## `entry_admin` — the system and its capabilities

Every one requires the **original** `AdminCap` for that system, asserted by
`assert_original_cap_for`, which refuses a duplicate and refuses a capability minted for a different
system.

| Call | Refuses |
|---|---|
| `withdraw_system_wal` | not the original cap; more than the vault holds |
| `withdraw_system_coin<T>` | as above; a coin type the vault does not accept |
| `add_coin_type<T>` | not the original cap |
| `remove_supported_coin<T>` | as above — balances already held stay withdrawable |
| `mint_system` | `ESuccessorAlreadyMinted` — the chain is linear, one successor only |
| `update_cost` | not the original cap |
| `update_tier_table` | as above |
| `migrate_version` | as above. **Not version-gated**, deliberately |
| `mint_admin` | as above — mints a *duplicate* for an operator wallet |
| `enrol_operator` | `EOperatorSetFull` (16), `EAlreadyAnOperator`, `EInvalidOperatorExpiry`, `ENotDuplicateCap`, `ECapForAnotherSystem` |
| `refresh_operator` | `ENotAnOperator` — refreshing moves a deadline, it does not create a slot |
| `retire_operator` | **cannot abort on a missing slot** — removing a credential must always succeed |

## `entry_register` — accounts

| Call | Authorised by | Refuses |
|---|---|---|
| `all_register_user_publicly` | the sender, for themselves | an address already registered here |
| `all_register_user_with_system_permission` | the same, and grants the operator role every bit | as above |
| `update_username` | the sender's own `Registry` | `ERegistryForAnotherSystem`, insufficient payment |
| `migrate_system` | the sender's own `Registry` | `ERegistryForAnotherSystem`, `EInsufficientPayment`, `ENotRegisteredHere`, `EAlreadyRegisteredThere`. Gates on **both** systems' versions |

## `entry_permission` — delegation

All six are gated on the **sender being the account owner** (`ENotAccountOwner`). A delegation is
the account's to give, and nothing else can give it.

| Call | Refuses |
|---|---|
| `grant` | `EAlreadyDelegated` — moving an existing row is `replace_grant` |
| `replace_grant` | `ENotDelegated` |
| `revoke` | `ENotDelegated` |
| `grant_operator_role` | `EOperatorRoleAlreadyGranted`. Takes **five** bits — never `create_writer_pass` |
| `replace_operator_role` | `EOperatorRoleNotGranted` |
| `revoke_operator_role` | `EOperatorRoleNotGranted` |

## `entry_wallet` — internal balances

| Call | Authorised by | Refuses |
|---|---|---|
| `deposit_coin<T>` | the sender, into their own wallet | a coin type the vault does not accept |
| `withdraw_wal` | the sender's own wallet, reached by their address | more than the balance |
| `withdraw_all_wal` | as above | — |

The wallet is reached through the user record keyed by `ctx.sender()`, so the lookup **is** the
authorisation: no address can name another's wallet.

## `entry_upload` — adoption

| Call | Authorised by | Refuses |
|---|---|---|
| `foreign_blob_add` | `add_blob_to_address` on `owner`, or sender is `owner` | `EBatchTooLarge` (>100), a term the system does not sell, no blobs |
| `foreign_blob_add_as_operator` | the same bit, via the operator role | as above, plus every operator gate |

## `entry_renew` — the permissionless call

| Call | Authorised by | Refuses |
|---|---|---|
| `renew_blob` | **nobody — anyone may call it** | nothing about the caller. Raises `RenewSkipped` rather than aborting when there is nothing to do |

The mandate is `epoch_set` and `cycle_limit` on the config, and the executor pays. This is the call
the whole design exists to make possible.

## `entry_withdraw` — the only way content leaves

| Call | Authorised by | Refuses |
|---|---|---|
| `self_withdraw_blob` | `ENotOwner` unless the sender owns the config | — the config is taken by value and destroyed |
| `self_withdraw_blobs` | the same, **per config** | as above. Configs with different owners may be handed in together |

Not delegable, and no operator sibling. See [refusals.md](refusals.md).

## `entry_transfer` — custody handover

| Call | Authorised by | Refuses |
|---|---|---|
| `offer` | sender is the current owner (`ENotOwner`) | `EOfferToSelf` |
| `accept` | sender is the named recipient | `ENoStandingOffer`, `ENotTheOfferedRecipient`, `ENotRegistered` |
| `cancel` | sender is the current owner | `ENoStandingOffer` — refused rather than passed over silently |

## `entry_compaction` — the additive half

| Call | Authorised by | Refuses |
|---|---|---|
| `plan_compaction` | nobody — opens a hot potato that must be closed this transaction | — |
| `supersede` | nothing; the plan carries the constraints | `ESupersedesItself`, `ETooManySuperseded`, `ESupersededNotAscending`, `ECrossUserQuilt`, `EPolicyNotHomogeneous`. **Takes no system, so has no version gate** |
| `register_layout` | `can_compact` on the target's owner, or sender is that owner | `EOwnerMoved`, `ELayoutAlreadyRegistered`, a generation not above every superseded one |
| `register_layout_as_operator` | the same bit, via the operator role | as above, plus every operator gate |

## `entry_file_create` — files

| Call | Authorised by | Refuses |
|---|---|---|
| `create_file` | `create_inner_file` **and** `add_blob_to_address` on `owner`, or sender is `owner` | `INVALIDTRACKBACKLENGTH` (1–8), `EPolicyOpensNoRoute`, `EInvalidPassDuration` on the delegated-pass branch |
| `create_file_as_operator` | the same bits via the operator role | as above, minus the pass branch. **Takes no policy** — the file is born admitting its creator |

## `entry_file_write` — revisions

| Call | Authorised by | Refuses |
|---|---|---|
| `force_write_innerfile` | sender is the file's owner, holding a valid pass | `INVALIDACCESS`, `ACCESSDENIED`, plus the eviction rules |
| `write_` | a valid `WriterPass` on this file | `ACCESSDENIED` when a pass without the privilege asks to skip the queue; `INVALIDPASS`, `DECAYEXCEEDED`, `EPassRevoked`, `INVALIDWRITER`, `EDraftLimitReached` |
| `write_as_operator` | the operator role's `add_blob_to_address` (history only), plus all three operator gates | `EOperatorsRefused`, `EOperatorDraftsRefused`, `EOperatorSlotCannotBypass`, `ENoAddBlobGrant`, `EPassRevoked`, `INVALIDWRITER` |

Both writing calls also enforce the eviction rules: `EEvictedConfigRequired` when the window is
full and no config was passed, `EUnexpectedConfig` when one was passed and nothing is retired, and
`EWrongConfig` when it is not the one the retired revision names.

## `entry_file_draft` — resolving proposals

All three are gated on the sender being the **file's owner** (`INVALIDACCESS`) and holding a valid
pass. No operator siblings.

| Call | Refuses |
|---|---|
| `merge_draft_into_file` | `EWrongDraftConfig`, `ENoDraftQueue`, plus the eviction rules |
| `delete_draft` | `ENoDraftQueue`, an index that names no standing draft |
| `clear_drafts` | as above, over the range the caller names |

## `entry_file_fallback` — the known-good revision

| Call | Authorised by | Refuses |
|---|---|---|
| `set_root_change` | sender is the file's owner, holding a valid pass | `INVALIDACCESS`, `ENotOwnersConfig` |
| `remove_root_change` | as above | `INVALIDACCESS` |

## `entry_file_access` — one file's terms

All seven are gated on the sender being the file's owner (`ENotFileOwner`), **on the sender and
never on a pass** — a pass that could flip these would let a delegate re-admit itself.

| Call | Refuses |
|---|---|
| `set_operator_policy` | `ENotFileOwner`, `EPolicyOpensNoRoute` |
| `deny_writer` | `ENotFileOwner`, a writer already denied |
| `redeny_writer` | `ENotFileOwner`, `ENotDenied` |
| `remove_deny_writer` | `ENotFileOwner`. A file with no deny list passes silently — it denies nobody |
| `revoke_pass` | `ENotFileOwner`. An id already refused is passed over |
| `revoke_passes` | as above, over the ids given |
| `create_pass` | `ENotFileOwner`, and `ENoAddBlobGrant` for an **admin** pass to an address that may not store for the owner |

## `entry_file_project` — projects

| Call | Authorised by | Refuses |
|---|---|---|
| `open_project_holder` | the sender, for themselves | `EProjectHolderExists` |
| `open_project_holder_as_operator` | `can_init_db` on `owner`, via the operator role | `EProjectHolderExists`, `INVALIDACCESS`, plus the operator gates. The holder's `admin` is `owner`, never the sender |
| `create_project` | `can_init_db` on the holder's admin | `INVALIDACCESS` — from `permission` for the bit, and from `project_object` for a holder that is not this account's |
| `create_project_as_operator` | the same, via the operator role | as above |
| `set_file_set_root` | **`can_set_root`** on the holder's admin | `INVALIDACCESS`, `ENoSuchProject`, `EInvalidRootLength` |
| `set_file_set_root_as_operator` | the same, via the operator role | as above |
| `initialize_project_file` | `can_init_db`, plus everything `create_file` needs | `DBEXIST` — a project names its database once and cannot name another |
| `initialize_project_file_as_operator` | the same, via the operator role | `DBEXIST`, as above. **Takes no policy** — the database is born writable by its creator |
