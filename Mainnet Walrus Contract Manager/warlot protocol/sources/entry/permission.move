/// Composes a user's delegation surface: the grant and the revoke.
module warlot::entry_permission;

// === Imports ===

use warlot::{permission, system_config::SystemConfig, user};

// === Errors ===

#[error]
const ENotAccountOwner: vector<u8> = b"ONLY THE ACCOUNT OWNER MAY DELEGATE";

// === Public functions ===

/// Delegate the listed capabilities on `owner`'s account to `delegate`,
/// replacing whatever that address held before.
///
/// The bits are set wholesale rather than added to, so one call always leaves
/// the delegate holding exactly what the caller named.
public fun grant(
    system_cfg: &mut SystemConfig,
    owner: address,
    delegate: address,
    add_blob: bool,
    inner_file: bool,
    writer_pass: bool,
    init_db: bool,
    compact: bool,
    ctx: &mut TxContext,
) {
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::create_permission_state(
        user_obj.uid_mut(),
        owner,
        delegate,
        add_blob,
        inner_file,
        writer_pass,
        init_db,
        compact,
    );
}

/// Withdraw every capability `delegate` holds on `owner`'s account.
public fun revoke(
    system_cfg: &mut SystemConfig,
    owner: address,
    delegate: address,
    ctx: &mut TxContext,
) {
    let user_obj = user::get_user_mut(system_cfg, owner);
    assert!(user_obj.owner() == ctx.sender(), ENotAccountOwner);

    permission::revoke_permission_state(user_obj.uid_mut(), owner, delegate);
}
