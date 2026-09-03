/// Declares the events a user raises: registration, system membership, their
/// wallet, and the capabilities they delegate.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::identity_events;

// === Imports ===

use std::string::String;
use sui::event;

// === Events ===

/// A registry was minted for an address, naming the user record it identifies.
public struct UserRegistered has copy, drop, store {
    system_id: ID,
    user_id: ID,
    registry_id: ID,
    user: address,
    public_username: String,
    created_at: u64,
    decay_at: u64,
}

/// A user record was attached to a system.
///
/// Separate from `UserRegistered` because the two are separate state changes:
/// migration detaches an existing record from one system and attaches it to
/// another without minting anything.
public struct UserJoinedSystem has copy, drop, store {
    system_id: ID,
    user: address,
    user_id: ID,
}

/// A user record was detached from a system.
public struct UserLeftSystem has copy, drop, store {
    system_id: ID,
    user: address,
    user_id: ID,
}

/// A registry's public username was replaced.
public struct UsernameUpdated has copy, drop, store {
    system_id: ID,
    registry_id: ID,
    user: address,
    public_username: String,
}

/// A registry was repointed from one system to another.
///
/// `system_id` is the system joined, so that the field means the same thing here
/// as it does everywhere else: the system this record now belongs to.
public struct RegistryMigrated has copy, drop, store {
    system_id: ID,
    previous_system: ID,
    registry_id: ID,
    user: address,
    updated_at: u64,
}

/// A wallet was created for a user.
public struct WalletCreated has copy, drop, store {
    system_id: ID,
    wallet_id: ID,
    user: address,
    created_at: u64,
}

/// A user funded their internal wallet.
public struct WalletDeposited has copy, drop, store {
    system_id: ID,
    user: address,
    coin_type: String,
    amount: u64,
    new_balance: u64,
}

/// A user drew from their internal wallet.
public struct WalletWithdrawn has copy, drop, store {
    system_id: ID,
    user: address,
    coin_type: String,
    amount: u64,
    new_balance: u64,
}

/// A user delegated capability bits to another address.
public struct PermissionGranted has copy, drop, store {
    system_id: ID,
    owner: address,
    delegate: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
    can_set_root: bool,
}

/// A user withdrew every capability bit from an address.
public struct PermissionRevoked has copy, drop, store {
    system_id: ID,
    owner: address,
    delegate: address,
}

/// A user delegated capability bits to the system operator role.
///
/// The counterpart to `PermissionGranted`, naming no address: the grant is to
/// whichever capability the system's operator set holds at the time of the call,
/// so a backend key that is added, retired or rotated later inherits or loses it
/// with no further act by the user.
public struct OperatorRoleGranted has copy, drop, store {
    system_id: ID,
    owner: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    /// Always false. The field is kept so this event and `PermissionGranted`
    /// stay the same shape, and so a consumer reading the operator's authority
    /// sees the refusal rather than having to know about it.
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
    can_set_root: bool,
}

/// A user withdrew every capability bit from the system operator role.
public struct OperatorRoleRevoked has copy, drop, store {
    system_id: ID,
    owner: address,
}

// === Package functions ===

/// Announce a newly registered user.
public(package) fun emit_user_registered(
    system_id: ID,
    user_id: ID,
    registry_id: ID,
    user: address,
    public_username: String,
    created_at: u64,
    decay_at: u64,
) {
    event::emit(UserRegistered {
        system_id,
        user_id,
        registry_id,
        user,
        public_username,
        created_at,
        decay_at,
    })
}

/// Announce a user record attached to a system.
public(package) fun emit_user_joined_system(system_id: ID, user: address, user_id: ID) {
    event::emit(UserJoinedSystem { system_id, user, user_id })
}

/// Announce a user record detached from a system.
public(package) fun emit_user_left_system(system_id: ID, user: address, user_id: ID) {
    event::emit(UserLeftSystem { system_id, user, user_id })
}

/// Announce a replaced public username.
public(package) fun emit_username_updated(
    system_id: ID,
    registry_id: ID,
    user: address,
    public_username: String,
) {
    event::emit(UsernameUpdated { system_id, registry_id, user, public_username })
}

/// Announce a registry repointed at another system.
public(package) fun emit_registry_migrated(
    system_id: ID,
    previous_system: ID,
    registry_id: ID,
    user: address,
    updated_at: u64,
) {
    event::emit(RegistryMigrated {
        system_id,
        previous_system,
        registry_id,
        user,
        updated_at,
    })
}

/// Announce a newly created wallet.
public(package) fun emit_wallet_created(
    system_id: ID,
    wallet_id: ID,
    user: address,
    created_at: u64,
) {
    event::emit(WalletCreated { system_id, wallet_id, user, created_at })
}

/// Announce a wallet deposit.
public(package) fun emit_wallet_deposited(
    system_id: ID,
    user: address,
    coin_type: String,
    amount: u64,
    new_balance: u64,
) {
    event::emit(WalletDeposited { system_id, user, coin_type, amount, new_balance })
}

/// Announce a wallet withdrawal.
public(package) fun emit_wallet_withdrawn(
    system_id: ID,
    user: address,
    coin_type: String,
    amount: u64,
    new_balance: u64,
) {
    event::emit(WalletWithdrawn { system_id, user, coin_type, amount, new_balance })
}

/// Announce a delegation.
public(package) fun emit_permission_granted(
    system_id: ID,
    owner: address,
    delegate: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
    can_set_root: bool,
) {
    event::emit(PermissionGranted {
        system_id,
        owner,
        delegate,
        add_blob_to_address,
        create_inner_file,
        create_writer_pass,
        can_init_db,
        can_compact,
        can_set_root,
    })
}

/// Announce a withdrawn delegation.
public(package) fun emit_permission_revoked(system_id: ID, owner: address, delegate: address) {
    event::emit(PermissionRevoked { system_id, owner, delegate })
}

/// Announce a delegation to the operator role.
public(package) fun emit_operator_role_granted(
    system_id: ID,
    owner: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
    can_set_root: bool,
) {
    event::emit(OperatorRoleGranted {
        system_id,
        owner,
        add_blob_to_address,
        create_inner_file,
        create_writer_pass,
        can_init_db,
        can_compact,
        can_set_root,
    })
}

/// Announce a withdrawn delegation to the operator role.
public(package) fun emit_operator_role_revoked(system_id: ID, owner: address) {
    event::emit(OperatorRoleRevoked { system_id, owner })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `UserRegistered`, in declaration order.
public fun read_user_registered(e: &UserRegistered): (ID, ID, ID, address, String, u64, u64) {
    let UserRegistered {
        system_id: _system_id,
        user_id: _user_id,
        registry_id: _registry_id,
        user: _user,
        public_username: _public_username,
        created_at: _created_at,
        decay_at: _decay_at,
    } = e;

    (*_system_id, *_user_id, *_registry_id, *_user, *_public_username, *_created_at, *_decay_at)
}

#[test_only]
/// Every field of `UserJoinedSystem`, in declaration order.
public fun read_user_joined_system(e: &UserJoinedSystem): (ID, address, ID) {
    let UserJoinedSystem {
        system_id: _system_id,
        user: _user,
        user_id: _user_id,
    } = e;

    (*_system_id, *_user, *_user_id)
}

#[test_only]
/// Every field of `UserLeftSystem`, in declaration order.
public fun read_user_left_system(e: &UserLeftSystem): (ID, address, ID) {
    let UserLeftSystem {
        system_id: _system_id,
        user: _user,
        user_id: _user_id,
    } = e;

    (*_system_id, *_user, *_user_id)
}

#[test_only]
/// Every field of `UsernameUpdated`, in declaration order.
public fun read_username_updated(e: &UsernameUpdated): (ID, ID, address, String) {
    let UsernameUpdated {
        system_id: _system_id,
        registry_id: _registry_id,
        user: _user,
        public_username: _public_username,
    } = e;

    (*_system_id, *_registry_id, *_user, *_public_username)
}

#[test_only]
/// Every field of `RegistryMigrated`, in declaration order.
public fun read_registry_migrated(e: &RegistryMigrated): (ID, ID, ID, address, u64) {
    let RegistryMigrated {
        system_id: _system_id,
        previous_system: _previous_system,
        registry_id: _registry_id,
        user: _user,
        updated_at: _updated_at,
    } = e;

    (*_system_id, *_previous_system, *_registry_id, *_user, *_updated_at)
}

#[test_only]
/// Every field of `WalletCreated`, in declaration order.
public fun read_wallet_created(e: &WalletCreated): (ID, ID, address, u64) {
    let WalletCreated {
        system_id: _system_id,
        wallet_id: _wallet_id,
        user: _user,
        created_at: _created_at,
    } = e;

    (*_system_id, *_wallet_id, *_user, *_created_at)
}

#[test_only]
/// Every field of `WalletDeposited`, in declaration order.
public fun read_wallet_deposited(e: &WalletDeposited): (ID, address, String, u64, u64) {
    let WalletDeposited {
        system_id: _system_id,
        user: _user,
        coin_type: _coin_type,
        amount: _amount,
        new_balance: _new_balance,
    } = e;

    (*_system_id, *_user, *_coin_type, *_amount, *_new_balance)
}

#[test_only]
/// Every field of `WalletWithdrawn`, in declaration order.
public fun read_wallet_withdrawn(e: &WalletWithdrawn): (ID, address, String, u64, u64) {
    let WalletWithdrawn {
        system_id: _system_id,
        user: _user,
        coin_type: _coin_type,
        amount: _amount,
        new_balance: _new_balance,
    } = e;

    (*_system_id, *_user, *_coin_type, *_amount, *_new_balance)
}

#[test_only]
/// Every field of `PermissionGranted`, in declaration order.
public fun read_permission_granted(e: &PermissionGranted): (
    ID,
    address,
    address,
    bool,
    bool,
    bool,
    bool,
    bool,
    bool,
) {
    let PermissionGranted {
        system_id: _system_id,
        owner: _owner,
        delegate: _delegate,
        add_blob_to_address: _add_blob_to_address,
        create_inner_file: _create_inner_file,
        create_writer_pass: _create_writer_pass,
        can_init_db: _can_init_db,
        can_compact: _can_compact,
        can_set_root: _can_set_root,
    } = e;

    (
        *_system_id,
        *_owner,
        *_delegate,
        *_add_blob_to_address,
        *_create_inner_file,
        *_create_writer_pass,
        *_can_init_db,
        *_can_compact,
        *_can_set_root,
    )
}

#[test_only]
/// Every field of `PermissionRevoked`, in declaration order.
public fun read_permission_revoked(e: &PermissionRevoked): (ID, address, address) {
    let PermissionRevoked {
        system_id: _system_id,
        owner: _owner,
        delegate: _delegate,
    } = e;

    (*_system_id, *_owner, *_delegate)
}

#[test_only]
/// Every field of `OperatorRoleGranted`, in declaration order.
public fun read_operator_role_granted(e: &OperatorRoleGranted): (
    ID,
    address,
    bool,
    bool,
    bool,
    bool,
    bool,
    bool,
) {
    let OperatorRoleGranted {
        system_id: _system_id,
        owner: _owner,
        add_blob_to_address: _add_blob_to_address,
        create_inner_file: _create_inner_file,
        create_writer_pass: _create_writer_pass,
        can_init_db: _can_init_db,
        can_compact: _can_compact,
        can_set_root: _can_set_root,
    } = e;

    (
        *_system_id,
        *_owner,
        *_add_blob_to_address,
        *_create_inner_file,
        *_create_writer_pass,
        *_can_init_db,
        *_can_compact,
        *_can_set_root,
    )
}

#[test_only]
/// Every field of `OperatorRoleRevoked`, in declaration order.
public fun read_operator_role_revoked(e: &OperatorRoleRevoked): (ID, address) {
    let OperatorRoleRevoked { system_id: _system_id, owner: _owner } = e;

    (*_system_id, *_owner)
}
