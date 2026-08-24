/// Records which writers an inner file's owner has revoked, and for how long.
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

/// How many denials have been recorded.
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
        *dfield::borrow_mut<address, u64>(&mut deny_obj.id, writer) = period;
    } else {
        dfield::add<address, u64>(&mut deny_obj.id, writer, period);
    };

    let old_d_o = deny_obj.numbers_of_deny;
    deny_obj.numbers_of_deny = 1 + old_d_o;
}

/// Drop `writer`'s denial.
public(package) fun undeny(deny_obj: &mut DenyList, writer: address) {
    let _ = dfield::remove<address, u64>(&mut deny_obj.id, writer);
}
