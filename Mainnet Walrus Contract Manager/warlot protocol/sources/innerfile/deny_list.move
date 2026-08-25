/// Records the writers an inner file's owner has denied, and the passes they have
/// revoked.
///
/// The two are separate revocations. Denying a writer refuses an address whatever
/// pass it presents; revoking a pass refuses one pass whoever presents it. A pass
/// lives in its holder's account and cannot be reached, let alone deleted, by the
/// file's owner, so the record kept here is the only revocation an owner has.
module warlot::deny_list;

// === Imports ===

use sui::{dynamic_field as dfield, dynamic_object_field as ofields};

// === Errors ===

#[error]
const INVALIDTIME: vector<u8> = b"enter valid time";

// === Constants ===

/// Dynamic object field key for a file's deny list.
const DENYLISTKEY: vector<u8> = b"deny list";

// === Structs ===

/// The addresses denied the right to modify a file, each with the timestamp in
/// ms until which the denial holds. A period of zero denies indefinitely.
///
/// Revoked pass ids are attached alongside, keyed by `ID` rather than by
/// `address`, so the two records share the object without colliding.
public struct DenyList has key, store {
    id: UID,
    numbers_of_deny: u64,
}

// === View functions ===

/// Whether `writer` has a denial recorded.
public(package) fun contains(deny_obj: &DenyList, writer: address): bool {
    dfield::exists_(&deny_obj.id, writer)
}

/// The timestamp in ms until which `writer` is denied; zero means indefinitely.
public(package) fun period(deny_obj: &DenyList, writer: address): u64 {
    *dfield::borrow<address, u64>(&deny_obj.id, writer)
}

/// Whether the pass `pass_id` has been revoked.
public(package) fun is_pass_revoked(deny_obj: &DenyList, pass_id: ID): bool {
    dfield::exists_<ID>(&deny_obj.id, pass_id)
}

/// How many writers are currently denied.
public(package) fun numbers_of_deny(deny_obj: &DenyList): u64 {
    deny_obj.numbers_of_deny
}

// === Package functions ===

/// Attach an empty deny list to `file_uid`.
public(package) fun attach(file_uid: &mut UID, ctx: &mut TxContext) {
    let default_deny_list = DenyList {
        id: object::new(ctx),
        numbers_of_deny: 0,
    };

    ofields::add<vector<u8>, DenyList>(file_uid, DENYLISTKEY, default_deny_list);
}

/// The deny list attached to `file_uid`.
public(package) fun borrow(file_uid: &UID): &DenyList {
    ofields::borrow<vector<u8>, DenyList>(file_uid, DENYLISTKEY)
}

/// Mutable access to the deny list attached to `file_uid`.
public(package) fun borrow_mut(file_uid: &mut UID): &mut DenyList {
    ofields::borrow_mut<vector<u8>, DenyList>(file_uid, DENYLISTKEY)
}

/// Deny `writer` until `period`, or indefinitely when `period` is zero.
public(package) fun deny(
    deny_obj: &mut DenyList,
    writer: address,
    period: u64,
    now_ms: u64,
) {
    assert!(period == 0 || period > now_ms, INVALIDTIME);
    if (dfield::exists_(&deny_obj.id, writer)) {
        // Re-denying an already denied writer moves their deadline; it does not
        // add a denial, so the count stays where it is.
        *dfield::borrow_mut<address, u64>(&mut deny_obj.id, writer) = period;
        return
    };

    dfield::add<address, u64>(&mut deny_obj.id, writer, period);

    let old_d_o = deny_obj.numbers_of_deny;
    deny_obj.numbers_of_deny = 1 + old_d_o;
}

/// Drop `writer`'s denial, or do nothing when they hold none.
///
/// Lifting a denial that was never recorded leaves the caller with exactly the
/// state they asked for, so it is not an error.
public(package) fun undeny(deny_obj: &mut DenyList, writer: address) {
    if (!dfield::exists_(&deny_obj.id, writer)) {
        return
    };

    let _ = dfield::remove<address, u64>(&mut deny_obj.id, writer);

    let old_d_o = deny_obj.numbers_of_deny;
    deny_obj.numbers_of_deny = old_d_o - 1;
}

/// Revoke the pass `pass_id`, permanently.
///
/// There is no counterpart that lifts this. A pass is revoked because it is in
/// the wrong hands, and an unrevoke would hand whoever holds it a second chance.
/// The owner mints a replacement instead.
public(package) fun revoke_pass(deny_obj: &mut DenyList, pass_id: ID) {
    if (dfield::exists_<ID>(&deny_obj.id, pass_id)) {
        return
    };

    dfield::add<ID, bool>(&mut deny_obj.id, pass_id, true);
}
