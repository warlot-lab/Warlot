/// Stores, writes and checks the capability bits a user has delegated to another address.
module warlot::permission;

// === Imports ===

use sui::{dynamic_field as dfield, dynamic_object_field as ofields, table::{Self, Table}};
use warlot::{identity_events, operator::OperatorAuth};

// === Errors ===

#[error]
const INVALIDACCESS: vector<u8> = b"permission denied";
#[error]
const EAlreadyDelegated: vector<u8> = b"THIS ADDRESS ALREADY HOLDS A DELEGATION ON THIS ACCOUNT";
#[error]
const ENotDelegated: vector<u8> = b"THIS ADDRESS HOLDS NO DELEGATION ON THIS ACCOUNT";
#[error]
const EOperatorRoleAlreadyGranted: vector<u8> =
    b"THIS ACCOUNT HAS ALREADY GRANTED THE SYSTEM OPERATOR ROLE";
#[error]
const EOperatorRoleNotGranted: vector<u8> =
    b"THIS ACCOUNT HAS NOT GRANTED THE SYSTEM OPERATOR ROLE";

// === Constants ===

/// Dynamic object field key for a user's delegation table.
///
/// Attached by the first delegation rather than at registration. The table is a
/// dynamic object field ,  two objects, counting the field entry ,  and an
/// account that never delegates to a named address never needs one. Every read
/// therefore asks `has_table` first, and answers an absent table the way it
/// answers an empty one.
const ACCEPTANCE_KEY: vector<u8> = b"acceptance key";

/// Dynamic field key for the bits a user has delegated to the operator role.
///
/// A row of its own rather than an entry in the table, because the table is
/// keyed by address and the operator role names none: that is the whole point of
/// it. Attached only when the role is granted, so a user who never delegates to
/// the system pays nothing for the possibility.
const OPERATOR_ROLE_KEY: vector<u8> = b"operator role";

// === Structs ===

/// The capability bits one address has delegated.
///
/// Used for both kinds of grant. Keyed by address in the delegation table it is
/// a delegation to one named key; attached under `OPERATOR_ROLE_KEY` it is the
/// same set of bits delegated to whichever capability the system's operator set
/// holds at the time of the call.
public struct SubPermission has store {
    /// May store blobs under the owner's address.
    add_blob_to_address: bool,
    /// May create inner files owned by the owner.
    create_inner_file: bool,
    /// May mint writer passes on the owner's files.
    create_writer_pass: bool,
    /// May initialise the owner's database.
    can_init_db: bool,
    /// May register a compaction layout against the owner's blob configs.
    can_compact: bool,
}

// === View functions ===

/// Whether `user_uid` has ever held an address-keyed delegation.
public fun has_delegation_table(user_uid: &UID): bool {
    ofields::exists_with_type<vector<u8>, Table<address, SubPermission>>(user_uid, ACCEPTANCE_KEY)
}

/// Whether `user_uid`'s owner has delegated anything to the operator role.
public fun has_operator_role(user_uid: &UID): bool {
    dfield::exists_with_type<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY)
}

/// Whether `writer` may store blobs under `owner` on the strength of an
/// address-keyed grant alone.
///
/// Deliberately blind to the operator role: this answers a question about one
/// named address, and the role names none. `create_pass` is its only caller, and
/// a pass is minted to an address.
public(package) fun grants_add_blob(user_uid: &UID, owner: address, writer: address): bool {
    if (writer == owner) return true;
    if (!has_delegation_table(user_uid)) return false;

    let sub_permission = borrow_table(user_uid);

    if (!sub_permission.contains(writer)) return false;

    sub_permission.borrow(writer).add_blob_to_address
}

// === Package functions ===

/// Open `user_uid`'s delegation surface, granting the operator role every bit
/// when `grant_operator_role` is set.
///
/// Nothing is attached when the flag is clear. The delegation table arrives with
/// the first address grant and the operator role is a dynamic field of its own,
/// so a registration that delegates to nobody creates no container at all.
public(package) fun open_delegations(
    user_uid: &mut UID,
    system_id: ID,
    owner: address,
    grant_operator_role: bool,
) {
    if (grant_operator_role) {
        // A registration that opens with a full delegation is a delegation, and
        // is announced as one. Without this the only silent grant in the
        // protocol would be the one made before the user has done anything.
        create_operator_role_state(user_uid, system_id, owner, true, true, true, true, true);
    };
}

/// Grant the operator role capability bits it does not already hold.
///
/// Refuses an account that has already granted the role. Making a grant and
/// changing one are different acts: a grant that quietly became a replacement
/// would take bits away from a role the account had already widened, and the
/// caller would see the same success either way.
public(package) fun create_operator_role_state(
    user_uid: &mut UID,
    system_id: ID,
    owner: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
) {
    assert!(
        !dfield::exists_with_type<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY),
        EOperatorRoleAlreadyGranted,
    );

    dfield::add<vector<u8>, SubPermission>(
        user_uid,
        OPERATOR_ROLE_KEY,
        SubPermission {
            add_blob_to_address,
            create_inner_file,
            create_writer_pass,
            can_init_db,
            can_compact,
        },
    );

    identity_events::emit_operator_role_granted(
        system_id,
        owner,
        add_blob_to_address,
        create_inner_file,
        create_writer_pass,
        can_init_db,
        can_compact,
    );
}

/// Replace every capability bit the operator role already holds.
///
/// Refuses an account that has not granted the role, so a replacement cannot
/// silently make a grant that was never asked for. The bits are set wholesale
/// rather than added to, so one call always leaves the role holding exactly what
/// the caller named.
public(package) fun replace_operator_role_state(
    user_uid: &mut UID,
    system_id: ID,
    owner: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
) {
    assert!(
        dfield::exists_with_type<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY),
        EOperatorRoleNotGranted,
    );

    let held = dfield::borrow_mut<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY);
    held.add_blob_to_address = add_blob_to_address;
    held.create_inner_file = create_inner_file;
    held.create_writer_pass = create_writer_pass;
    held.can_init_db = can_init_db;
    held.can_compact = can_compact;

    identity_events::emit_operator_role_granted(
        system_id,
        owner,
        add_blob_to_address,
        create_inner_file,
        create_writer_pass,
        can_init_db,
        can_compact,
    );
}

/// Drop the operator role's row, leaving it with no bit to fall back on.
///
/// The row is removed rather than zeroed, for the reason an address revocation
/// is: a revoked grant is refused by the lookup itself and no row survives that
/// could be mistaken for a delegation. Revoking a role that was never granted is
/// not an error.
public(package) fun revoke_operator_role_state(
    user_uid: &mut UID,
    system_id: ID,
    owner: address,
) {
    if (dfield::exists_with_type<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY)) {
        let SubPermission {
            add_blob_to_address: _,
            create_inner_file: _,
            create_writer_pass: _,
            can_init_db: _,
            can_compact: _,
        } = dfield::remove<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY);
    };

    identity_events::emit_operator_role_revoked(system_id, owner);
}

/// Assert the sender may store blobs under `owner`.
public(package) fun check_add_blob(
    user_uid: &UID,
    owner: address,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    if (ctx.sender() == owner) return;
    let (add_blob_to_address, _, _, _, _) = effective_bits(user_uid, operator, ctx);
    assert!(add_blob_to_address, INVALIDACCESS);
}

/// Assert the sender may create inner files owned by `owner`.
public(package) fun check_inner_file(
    user_uid: &UID,
    owner: address,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    if (ctx.sender() == owner) return;
    let (_, create_inner_file, _, _, _) = effective_bits(user_uid, operator, ctx);
    assert!(create_inner_file, INVALIDACCESS);
}

/// Assert the sender may mint writer passes on `owner`'s files.
public(package) fun check_writer_pass(
    user_uid: &UID,
    owner: address,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    if (ctx.sender() == owner) return;
    let (_, _, create_writer_pass, _, _) = effective_bits(user_uid, operator, ctx);
    assert!(create_writer_pass, INVALIDACCESS);
}

/// Assert the sender may initialise `owner`'s database.
public(package) fun check_can_init_db(
    user_uid: &UID,
    owner: address,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    if (ctx.sender() == owner) return;
    let (_, _, _, can_init_db, _) = effective_bits(user_uid, operator, ctx);
    assert!(can_init_db, INVALIDACCESS);
}

/// Assert the sender may register a compaction layout against `owner`'s configs.
///
/// Writing a new quilt is purely additive ,  it destroys nothing and supersedes
/// nothing until the owner acts ,  so it is delegable and backgroundable. The
/// destructive half is withdrawal, which takes the config by value and is
/// refused to anybody but its owner. That is why there is one bit here and no
/// second one for deletion: deletion is not delegable at all.
public(package) fun check_can_compact(
    user_uid: &UID,
    owner: address,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
) {
    if (ctx.sender() == owner) return;
    let (_, _, _, _, can_compact) = effective_bits(user_uid, operator, ctx);
    assert!(can_compact, INVALIDACCESS);
}

/// Delegate capability bits to an address that holds none.
///
/// Refuses an address that already holds a delegation. Widening a grant and
/// making one are different acts, and the bits are written wholesale, so a
/// delegation made against an address that already had one would take away
/// whatever the caller did not happen to name ,  while reporting the same
/// success as a first grant.
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
    ctx: &mut TxContext,
) {
    let sub_permission = borrow_table_mut_or_attach(user_uid, ctx);

    assert!(!sub_permission.contains(privilege_address), EAlreadyDelegated);

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

/// Replace every capability bit an address already holds.
///
/// Refuses an address that holds no delegation, so a replacement cannot silently
/// make a grant nobody asked for. The bits are set wholesale rather than added
/// to, so one call always leaves the delegate holding exactly what the caller
/// named ,  which is the point of asking for this call rather than the one above.
public(package) fun replace_permission_state(
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
    // An account that has never delegated to any address has not delegated to
    // this one, so the missing table answers exactly as an empty one would.
    assert!(has_delegation_table(user_uid), ENotDelegated);

    let sub_permission = borrow_table_mut(user_uid);

    assert!(sub_permission.contains(privilege_address), ENotDelegated);

    let privilege_permission = sub_permission.borrow_mut<address, SubPermission>(
        privilege_address,
    );
    privilege_permission.add_blob_to_address = add_blob_to_address;
    privilege_permission.create_inner_file = create_inner_file;
    privilege_permission.create_writer_pass = create_writer_pass;
    privilege_permission.can_init_db = can_init_db;
    privilege_permission.can_compact = can_compact;

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
    if (has_delegation_table(user_uid)) {
        remove_delegation(user_uid, privilege_address);
    };

    identity_events::emit_permission_revoked(system_id, owner, privilege_address);
}

/// Drop `privilege_address`'s row from a table that exists.
fun remove_delegation(user_uid: &mut UID, privilege_address: address) {
    let sub_permission = borrow_table_mut(user_uid);

    if (sub_permission.contains(privilege_address)) {
        let SubPermission {
            add_blob_to_address: _,
            create_inner_file: _,
            create_writer_pass: _,
            can_init_db: _,
            can_compact: _,
        } = sub_permission.remove(privilege_address);
    };
}

// === Private functions ===

/// The delegation table attached to `user_uid`.
fun borrow_table(user_uid: &UID): &Table<address, SubPermission> {
    ofields::borrow<vector<u8>, Table<address, SubPermission>>(user_uid, ACCEPTANCE_KEY)
}

/// Mutable access to the delegation table attached to `user_uid`.
fun borrow_table_mut(user_uid: &mut UID): &mut Table<address, SubPermission> {
    ofields::borrow_mut<vector<u8>, Table<address, SubPermission>>(user_uid, ACCEPTANCE_KEY)
}

/// The delegation table, attaching an empty one if this is the account's first
/// address grant.
fun borrow_table_mut_or_attach(
    user_uid: &mut UID,
    ctx: &mut TxContext,
): &mut Table<address, SubPermission> {
    if (!has_delegation_table(user_uid)) {
        let sub_permission: Table<address, SubPermission> = table::new(ctx);

        ofields::add<vector<u8>, Table<address, SubPermission>>(
            user_uid,
            ACCEPTANCE_KEY,
            sub_permission,
        );
    };

    borrow_table_mut(user_uid)
}

/// Every capability bit the sender may use on this account, in declaration
/// order.
///
/// The union of two grants that are made independently and revoked
/// independently: the row the account owner wrote against the sender's address,
/// and the row they wrote against the operator role, which counts only when the
/// sender presented a live operator credential. An address grant therefore still
/// works with no capability at all, and is unaffected by a key being added to or
/// pulled from the operator set.
///
/// Neither absence is an error here. A sender holding nothing gets every bit
/// false and is refused by the caller, which is what names the bit that was
/// missing.
fun effective_bits(
    user_uid: &UID,
    operator: Option<OperatorAuth>,
    ctx: &TxContext,
): (bool, bool, bool, bool, bool) {
    let mut add_blob_to_address = false;
    let mut create_inner_file = false;
    let mut create_writer_pass = false;
    let mut can_init_db = false;
    let mut can_compact = false;

    if (has_delegation_table(user_uid) && borrow_table(user_uid).contains(ctx.sender())) {
        let row = borrow_table(user_uid).borrow(ctx.sender());
        add_blob_to_address = row.add_blob_to_address;
        create_inner_file = row.create_inner_file;
        create_writer_pass = row.create_writer_pass;
        can_init_db = row.can_init_db;
        can_compact = row.can_compact;
    };

    if (
        operator.is_some()
        && dfield::exists_with_type<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY)
    ) {
        let row = dfield::borrow<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY);
        add_blob_to_address = add_blob_to_address || row.add_blob_to_address;
        create_inner_file = create_inner_file || row.create_inner_file;
        create_writer_pass = create_writer_pass || row.create_writer_pass;
        can_init_db = can_init_db || row.can_init_db;
        can_compact = can_compact || row.can_compact;
    };

    (
        add_blob_to_address,
        create_inner_file,
        create_writer_pass,
        can_init_db,
        can_compact,
    )
}

// === Test-only helpers ===

#[test_only]
/// Whether `delegate` holds a row in `user_uid`'s delegation table.
public fun has_delegate(user_uid: &UID, delegate: address): bool {
    has_delegation_table(user_uid) && borrow_table(user_uid).contains(delegate)
}

#[test_only]
/// Every capability bit `delegate` holds, in declaration order.
public fun delegate_bits(user_uid: &UID, delegate: address): (bool, bool, bool, bool, bool) {
    let row = borrow_table(user_uid).borrow(delegate);

    (
        row.add_blob_to_address,
        row.create_inner_file,
        row.create_writer_pass,
        row.can_init_db,
        row.can_compact,
    )
}

#[test_only]
/// Every capability bit the operator role holds, in declaration order.
public fun operator_role_bits(user_uid: &UID): (bool, bool, bool, bool, bool) {
    let row = dfield::borrow<vector<u8>, SubPermission>(user_uid, OPERATOR_ROLE_KEY);

    (
        row.add_blob_to_address,
        row.create_inner_file,
        row.create_writer_pass,
        row.can_init_db,
        row.can_compact,
    )
}
