/// Holds `User`, the per-user state container attached to `SystemConfig`.
module warlot::user;

// === Imports ===

use std::string::String;
use sui::{clock::Clock, dynamic_object_field as ofields};
use warlot::{
    identity_events,
    operator::OperatorAuth,
    permission,
    registry,
    system_config::{Self, SystemConfig},
    wallet::{Self, Wallet},
};

// === Errors ===

#[error]
const EUserExist: vector<u8> = b"USER ALREADY EXISTS";
#[error]
const EUserNotFound: vector<u8> = b"USER IS NOT REGISTERED ON THIS SYSTEM";

// === Structs ===

/// A registered entity's on-chain state.
public struct User has key, store {
    id: UID,
    /// The address that controls this user.
    owner: address,
    /// The user's internal balances.
    wallet: Wallet,
}

// === Public functions ===

/// Assert the sender may store blobs under `user_obj`.
///
/// `operator` is the proof that the sender presented a live operator credential,
/// and is `none` on every path where none was offered. It is carried rather than
/// resolved here because the capability is an argument to the entry point and
/// this is several frames below it.
public fun check_permission_add_blob(
    user_obj: &User,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    permission::check_add_blob(&user_obj.id, user_obj.owner, operator, ctx);
}

/// Assert the sender may create inner files owned by `user_obj`.
public fun check_permission_inner_file(
    user_obj: &User,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    permission::check_inner_file(&user_obj.id, user_obj.owner, operator, ctx);
}

/// Assert the sender may mint writer passes on `user_obj`'s files.
public fun check_permission_writer_pass(
    user_obj: &User,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    permission::check_writer_pass(&user_obj.id, user_obj.owner, operator, ctx);
}

/// Assert the sender may initialise `user_obj`'s database.
public fun check_permission_can_init_db(
    user_obj: &User,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    permission::check_can_init_db(&user_obj.id, user_obj.owner, operator, ctx);
}

/// Assert the sender may register a compaction layout against `user_obj`'s
/// configs.
public fun check_permission_can_compact(
    user_obj: &User,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    permission::check_can_compact(&user_obj.id, user_obj.owner, operator, ctx);
}

/// Whether `writer` holds an address-keyed grant to store blobs under `user_obj`.
public(package) fun grants_add_blob(user_obj: &User, writer: address): bool {
    permission::grants_add_blob(&user_obj.id, user_obj.owner, writer)
}

// === View functions ===

/// Immutable access to a registered user, or an abort if they are not registered.
public fun get_user(system_cfg: &SystemConfig, user: address): &User {
    assert!(check_user(system_cfg, user), EUserNotFound);

    ofields::borrow<address, User>(system_config::uid(system_cfg), user)
}

/// Whether `user` is registered on this system.
public fun check_user(system_cfg: &SystemConfig, user: address): bool {
    ofields::exists_(system_config::uid(system_cfg), user)
}

/// The address that controls this user.
public(package) fun owner(user: &User): address {
    user.owner
}

/// The user's UID, so sibling modules can reach the objects attached to it.
public(package) fun uid(user: &User): &UID {
    &user.id
}

/// Mutable access to the user's UID, so sibling modules can attach objects to it.
public(package) fun uid_mut(user: &mut User): &mut UID {
    &mut user.id
}

/// The user's internal wallet.
public(package) fun get_wallet(user: &mut User): &mut Wallet {
    &mut user.wallet
}

// === Package functions ===

/// Build a user with an empty wallet, the operator role granted every bit when
/// `grant_operator_role` is set, and a registry transferred to the sender.
public(package) fun create_user(
    public_username: String,
    system_id: ID,
    clock: &Clock,
    grant_operator_role: bool,
    ctx: &mut TxContext,
): User {
    let safe_vault: Wallet = wallet::create_wallet(system_id, clock, ctx);

    let mut new_user = User {
        id: object::new(ctx),
        owner: ctx.sender(),
        wallet: safe_vault,
    };

    let owner = new_user.owner;

    permission::open_delegations(
        &mut new_user.id,
        system_id,
        owner,
        grant_operator_role,
    );

    registry::create_registry(
        public_username,
        object::id(&new_user),
        system_id,
        option::none(),
        clock,
        ctx,
    );

    new_user
}

/// Attach `user` to the system under the sender's address.
///
/// Membership is the dynamic field itself, which `check_user` reads directly. The
/// append-only address list and the address-to-index map that used to be
/// maintained alongside it cost two objects per user forever and existed only for
/// a global loop that no longer exists.
public(package) fun add_user(system_cfg: &mut SystemConfig, user: User, ctx: &TxContext) {
    let new_user = ctx.sender();
    assert!(!ofields::exists_(system_config::uid(system_cfg), new_user), EUserExist);

    let user_id = object::id(&user);

    ofields::add<address, User>(system_config::uid_mut(system_cfg), new_user, user);

    identity_events::emit_user_joined_system(object::id(system_cfg), new_user, user_id);
}

/// Detach `user` from the system.
public(package) fun remove_user(system_cfg: &mut SystemConfig, user: address): User {
    // `dynamic_object_field` wraps its keys, so a record attached with it has to be
    // detached with it; `dynamic_field` looks in a different key space and finds
    // nothing.
    let removed = ofields::remove<address, User>(system_config::uid_mut(system_cfg), user);

    identity_events::emit_user_left_system(
        object::id(system_cfg),
        user,
        object::id(&removed),
    );

    removed
}

/// Mutable access to a registered user.
public(package) fun get_user_mut(system_cfg: &mut SystemConfig, user: address): &mut User {
    assert!(check_user(system_cfg, user), EUserNotFound);

    ofields::borrow_mut<address, User>(system_config::uid_mut(system_cfg), user)
}
