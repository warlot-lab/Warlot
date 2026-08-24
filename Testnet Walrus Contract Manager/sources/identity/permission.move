/// Stores, writes and checks the capability bits a user has delegated to another address.
module warlot::permission;

// === Imports ===

use sui::{dynamic_object_field as ofields, table::{Self, Table}};

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
}

// === Package functions ===

/// Attach an empty delegation table to `user_uid`, granting every bit to
/// `delegate` when one is supplied.
public(package) fun create_table(
    user_uid: &mut UID,
    delegate: Option<address>,
    ctx: &mut TxContext,
) {
    let mut sub_permission: Table<address, SubPermission> = table::new(ctx);

    if (option::is_some<address>(&delegate)) {
        table::add<address, SubPermission>(
            &mut sub_permission,
            option::destroy_some<address>(delegate),
            SubPermission {
                add_blob_to_address: true,
                create_inner_file: true,
                create_writer_pass: true,
                can_init_db: true,
            },
        )
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
public(package) fun check_writer_pass(user_uid: &UID, ctx: &TxContext) {
    assert!(borrow_for_sender(user_uid, ctx).create_writer_pass, INVALIDACCESS);
}

/// Assert the sender may initialise the owner's database.
public(package) fun check_can_init_db(user_uid: &UID, ctx: &TxContext) {
    assert!(borrow_for_sender(user_uid, ctx).can_init_db, INVALIDACCESS);
}

/// Set every capability bit for `privilege_address`, creating the entry if absent.
public(package) fun create_permission_state(
    user_uid: &mut UID,
    privilege_address: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
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
    } else {
        sub_permission.add(
            privilege_address,
            SubPermission {
                add_blob_to_address,
                create_inner_file,
                create_writer_pass,
                can_init_db,
            },
        );
    };
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
