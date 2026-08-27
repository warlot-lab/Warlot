/// Stores, writes and checks the capability bits a user has delegated to another address.
module warlot::permission;

// === Imports ===

use sui::{dynamic_object_field as ofields, table::{Self, Table}};
use warlot::identity_events;

// === Errors ===

#[error]
const INVALIDACCESS: vector<u8> = b"permission denied";

// === Constants ===

/// Dynamic object field key for a user's delegation table.
const ACCEPTANCE_KEY: vector<u8> = b"acceptance key";

// === Structs ===

/// The capability bits one address has delegated to another.
public struct SubPermission has store {
    /// May store blobs under the owner's address.
    add_blob_to_address: bool,
    /// May create inner files owned by the owner.
    create_inner_file: bool,
    /// May mint writer passes on the owner's files.
    create_writer_pass: bool,
    /// May initialise the owner's database.
    can_init_db: bool,
    /// May compact the owner's stored blobs. Reserved; nothing consumes it yet.
    can_compact: bool,
}

// === Test-only helpers ===

#[test_only]
/// Whether `delegate` holds a row in `user_uid`'s delegation table.
public fun has_delegate(user_uid: &UID, delegate: address): bool {
    let sub_permission = ofields::borrow<vector<u8>, Table<address, SubPermission>>(
        user_uid,
        ACCEPTANCE_KEY,
    );

    sub_permission.contains(delegate)
}

#[test_only]
/// Every capability bit `delegate` holds, in declaration order.
public fun delegate_bits(user_uid: &UID, delegate: address): (bool, bool, bool, bool, bool) {
    let sub_permission = ofields::borrow<vector<u8>, Table<address, SubPermission>>(
        user_uid,
        ACCEPTANCE_KEY,
    );
    let row = sub_permission.borrow(delegate);

    (
        row.add_blob_to_address,
        row.create_inner_file,
        row.create_writer_pass,
        row.can_init_db,
        row.can_compact,
    )
}

// === Package functions ===

/// Attach an empty delegation table to `user_uid`, granting every bit to
/// `delegate` when one is supplied.
public(package) fun create_table(
    user_uid: &mut UID,
    system_id: ID,
    owner: address,
    delegate: Option<address>,
    ctx: &mut TxContext,
) {
    let mut sub_permission: Table<address, SubPermission> = table::new(ctx);

    if (option::is_some<address>(&delegate)) {
        let delegate_address = option::destroy_some<address>(delegate);

        table::add<address, SubPermission>(
            &mut sub_permission,
            delegate_address,
            SubPermission {
                add_blob_to_address: true,
                create_inner_file: true,
                create_writer_pass: true,
                can_init_db: true,
                can_compact: true,
            },
        );

        // A registration that opens with a full delegation is a delegation, and
        // is announced as one. Without this the only silent grant in the
        // protocol would be the one made before the user has done anything.
        identity_events::emit_permission_granted(
            system_id,
            owner,
            delegate_address,
            true,
            true,
            true,
            true,
            true,
        );
    } else {
        option::destroy_none<address>(delegate)
    };

    ofields::add<vector<u8>, Table<address, SubPermission>>(
        user_uid,
        ACCEPTANCE_KEY,
        sub_permission,
    );
}

/// Assert the sender may store blobs under `owner`.
public(package) fun check_add_blob(user_uid: &UID, owner: address, ctx: &TxContext) {
    if (ctx.sender() == owner) return;
    assert!(borrow_for_sender(user_uid, ctx).add_blob_to_address, INVALIDACCESS);
}

/// Assert the sender may create inner files owned by `owner`.
public(package) fun check_inner_file(user_uid: &UID, owner: address, ctx: &TxContext) {
    if (ctx.sender() == owner) return;
    assert!(borrow_for_sender(user_uid, ctx).create_inner_file, INVALIDACCESS);
}

/// Assert the sender may mint writer passes on `owner`'s files.
public(package) fun check_writer_pass(user_uid: &UID, owner: address, ctx: &TxContext) {
    if (ctx.sender() == owner) return;
    assert!(borrow_for_sender(user_uid, ctx).create_writer_pass, INVALIDACCESS);
}

/// Assert the sender may initialise `owner`'s database.
public(package) fun check_can_init_db(user_uid: &UID, owner: address, ctx: &TxContext) {
    if (ctx.sender() == owner) return;
    assert!(borrow_for_sender(user_uid, ctx).can_init_db, INVALIDACCESS);
}

/// Set every capability bit for `privilege_address`, creating the entry if absent.
///
/// `owner` is the address whose table this is, and is reported so a delegation
/// can be attributed to the account it was made on rather than to the sender.
public(package) fun create_permission_state(
    user_uid: &mut UID,
    system_id: ID,
    owner: address,
    privilege_address: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
) {
    let sub_permission = ofields::borrow_mut<vector<u8>, Table<address, SubPermission>>(
        user_uid,
        ACCEPTANCE_KEY,
    );
    if (sub_permission.contains(privilege_address)) {
        let privilege_permission = sub_permission.borrow_mut<address, SubPermission>(
            privilege_address,
        );
        privilege_permission.add_blob_to_address = add_blob_to_address;
        privilege_permission.create_inner_file = create_inner_file;
        privilege_permission.create_writer_pass = create_writer_pass;
        privilege_permission.can_init_db = can_init_db;
        privilege_permission.can_compact = can_compact;
    } else {
        sub_permission.add(
            privilege_address,
            SubPermission {
                add_blob_to_address,
                create_inner_file,
                create_writer_pass,
                can_init_db,
                can_compact,
            },
        );
    };

    identity_events::emit_permission_granted(
        system_id,
        owner,
        privilege_address,
        add_blob_to_address,
        create_inner_file,
        create_writer_pass,
        can_init_db,
        can_compact,
    );
}

/// Drop `privilege_address`'s entry, leaving them with no bit to fall back on.
///
/// The entry is removed rather than zeroed, so a revoked delegate is refused by
/// the table lookup itself and no row survives that could be mistaken for a
/// delegation. Revoking an address that holds nothing is not an error: the
/// caller gets the state they asked for either way, and a revocation that can
/// abort is one that can fail at the moment it is most needed.
public(package) fun revoke_permission_state(
    user_uid: &mut UID,
    system_id: ID,
    owner: address,
    privilege_address: address,
) {
    let sub_permission = ofields::borrow_mut<vector<u8>, Table<address, SubPermission>>(
        user_uid,
        ACCEPTANCE_KEY,
    );

    if (sub_permission.contains(privilege_address)) {
        let SubPermission {
            add_blob_to_address: _,
            create_inner_file: _,
            create_writer_pass: _,
            can_init_db: _,
            can_compact: _,
        } = sub_permission.remove(privilege_address);
    };

    identity_events::emit_permission_revoked(system_id, owner, privilege_address);
}

// === Private functions ===

/// The delegation entry for the sender, or an abort if they hold none.
fun borrow_for_sender(user_uid: &UID, ctx: &TxContext): &SubPermission {
    let sub_permission = ofields::borrow<vector<u8>, Table<address, SubPermission>>(
        user_uid,
        ACCEPTANCE_KEY,
    );

    assert!(sub_permission.contains(ctx.sender()), INVALIDACCESS);

    sub_permission.borrow(ctx.sender())
}
