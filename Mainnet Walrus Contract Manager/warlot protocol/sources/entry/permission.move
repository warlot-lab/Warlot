/// Composes a user's delegation surface: the grant and the revoke.
module warlot::entry_permission;

// === Imports ===

use warlot::{permission, system_config::SystemConfig, user};

// === Errors ===

#[error]
const ENotAccountOwner: vector<u8> = b"ONLY THE ACCOUNT OWNER MAY DELEGATE";

// === Public functions ===

/// Delegate the listed capabilities on `owner`'s account to an address that
/// holds none.
///
/// Refuses an address that already holds a delegation. Changing one is
/// `replace_grant`: the bits are written wholesale, so a grant made against an
/// address that already had one would silently take away whatever the caller did
/// not happen to name, and would report the same success as a first grant.
public fun grant(
    system_cfg: &mut SystemConfig,
    owner: address,
    delegate: address,
    add_blob: bool,
    inner_file: bool,
    writer_pass: bool,
    init_db: bool,
    compact: bool,
    set_root: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::create_permission_state(
        user_obj.uid_mut(),
        system_id,
        owner,
        delegate,
        add_blob,
        inner_file,
        writer_pass,
        init_db,
        compact,
        set_root,
        ctx,
    );
}

/// Replace the capabilities `delegate` already holds on `owner`'s account.
///
/// Refuses an address holding no delegation, so a replacement cannot silently
/// become a first grant. The bits are set wholesale, so one call always leaves
/// the delegate holding exactly what the caller named.
public fun replace_grant(
    system_cfg: &mut SystemConfig,
    owner: address,
    delegate: address,
    add_blob: bool,
    inner_file: bool,
    writer_pass: bool,
    init_db: bool,
    compact: bool,
    set_root: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::replace_permission_state(
        user_obj.uid_mut(),
        system_id,
        owner,
        delegate,
        add_blob,
        inner_file,
        writer_pass,
        init_db,
        compact,
        set_root,
    );
}

/// Withdraw every capability `delegate` holds on `owner`'s account.
public fun revoke(
    system_cfg: &mut SystemConfig,
    owner: address,
    delegate: address,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::revoke_permission_state(user_obj.uid_mut(), system_id, owner, delegate);
}

/// Delegate the listed capabilities on `owner`'s account to the system operator
/// role, which must not already hold one.
///
/// The grant names no address. It is honoured for whichever capability holds a
/// live slot in the system's operator set at the moment of the call, so the
/// backend can enrol, retire or rotate a signing key without a write against this
/// account. An address grant made with `grant` is unaffected by this one and
/// keeps working on its own.
///
/// Refuses an account that has already granted the role, for the reason `grant`
/// refuses an address that already holds one. Changing it is
/// `replace_operator_role`.
///
/// There is no writer-pass argument, unlike `grant`. A pass binds to one address
/// and the operator credential rotates between wallets, so the role cannot hold
/// pass-minting authority in any form that could be exercised. Taking the bit
/// and storing `false` would announce an authority that does not exist, so the
/// parameter is absent instead and the refusal is by signature.
public fun grant_operator_role(
    system_cfg: &mut SystemConfig,
    owner: address,
    add_blob: bool,
    inner_file: bool,
    init_db: bool,
    compact: bool,
    set_root: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::create_operator_role_state(
        user_obj.uid_mut(),
        system_id,
        owner,
        add_blob,
        inner_file,
        init_db,
        compact,
        set_root,
    );
}

/// Replace the capabilities the system operator role already holds on `owner`'s
/// account.
///
/// This is how an account narrows what the operator may do without withdrawing
/// the role outright. Refuses an account that never granted it.
///
/// Narrowing `set_root` alone freezes the account's project commitments at their
/// last honest value while leaving storing, file creation, database
/// initialisation and compaction running. That is the precision the bit exists
/// for, and it is why it is not folded into `init_db`.
public fun replace_operator_role(
    system_cfg: &mut SystemConfig,
    owner: address,
    add_blob: bool,
    inner_file: bool,
    init_db: bool,
    compact: bool,
    set_root: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::replace_operator_role_state(
        user_obj.uid_mut(),
        system_id,
        owner,
        add_blob,
        inner_file,
        init_db,
        compact,
        set_root,
    );
}

/// Withdraw every capability the system operator role holds on `owner`'s account.
///
/// Leaves address grants alone: an operator that also holds one keeps acting on
/// the strength of that, which is the point of the two being separate.
public fun revoke_operator_role(
    system_cfg: &mut SystemConfig,
    owner: address,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::revoke_operator_role_state(user_obj.uid_mut(), system_id, owner);
}
