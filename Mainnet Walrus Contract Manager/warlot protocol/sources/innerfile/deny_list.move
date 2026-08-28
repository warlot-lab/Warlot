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
use warlot::pass_events;

// === Errors ===

#[error]
const INVALIDTIME: vector<u8> = b"enter valid time";
#[error]
const EAlreadyDenied: vector<u8> = b"THIS WRITER IS ALREADY DENIED ON THIS FILE";
#[error]
const ENotDenied: vector<u8> = b"THIS WRITER IS NOT DENIED ON THIS FILE";

// === Constants ===

/// Dynamic object field key for a file's deny list.
const DENYLISTKEY: vector<u8> = b"deny list";

// === Structs ===

/// The addresses denied the right to modify a file, each with the timestamp in
/// ms until which the denial holds. A period of zero denies indefinitely.
///
/// Revoked pass ids are attached alongside, keyed by `ID` rather than by
/// `address`, so the two records share the object without colliding.
///
/// The object carries no fields of its own: the denials *are* the dynamic
/// fields, and the running count that used to sit here was written on every
/// change and read by nothing. A consumer that wants the count counts the
/// `WriterDenied` and `WriterUndenied` events.
///
/// It is attached on the first denial rather than at the file's creation. Most
/// files never deny anybody, and an empty list still costs an object header and
/// a field entry.
public struct DenyList has key, store {
    id: UID,
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

// === Package functions ===

/// Whether `file_uid` has ever had a deny list attached.
///
/// A file that has never denied anybody and never revoked a pass holds none, so
/// every read has to ask this first.
public(package) fun attached(file_uid: &UID): bool {
    ofields::exists_<vector<u8>>(file_uid, DENYLISTKEY)
}

/// The deny list attached to `file_uid`.
public(package) fun borrow(file_uid: &UID): &DenyList {
    ofields::borrow<vector<u8>, DenyList>(file_uid, DENYLISTKEY)
}

/// Mutable access to the deny list attached to `file_uid`.
public(package) fun borrow_mut(file_uid: &mut UID): &mut DenyList {
    ofields::borrow_mut<vector<u8>, DenyList>(file_uid, DENYLISTKEY)
}

/// Mutable access to `file_uid`'s deny list, attaching an empty one first if the
/// file has never held one.
///
/// Only the three calls that record something reach for this. Lifting a denial
/// that was never made does not, so a file cannot be given a deny list by
/// somebody asking it to forget one.
public(package) fun borrow_mut_or_attach(file_uid: &mut UID, ctx: &mut TxContext): &mut DenyList {
    if (!ofields::exists_<vector<u8>>(file_uid, DENYLISTKEY)) {
        ofields::add<vector<u8>, DenyList>(file_uid, DENYLISTKEY, DenyList { id: object::new(ctx) });
    };

    ofields::borrow_mut<vector<u8>, DenyList>(file_uid, DENYLISTKEY)
}

/// Deny `writer`, who is not already denied, until `period` ,  or indefinitely
/// when `period` is zero.
///
/// Refuses a writer who already holds a denial. Making a denial and moving one
/// are different acts on this record: a denial made against a writer who already
/// had one would overwrite their deadline, so an owner reaching for the blunt
/// instrument could shorten a denial they meant to leave alone, and see the same
/// success either way. Moving a deadline is `redeny`.
public(package) fun deny(
    deny_obj: &mut DenyList,
    writer: address,
    period: u64,
    now_ms: u64,
    system_id: ID,
    file_id: ID,
    denied_by: address,
) {
    assert!(period == 0 || period > now_ms, INVALIDTIME);
    assert!(!dfield::exists_(&deny_obj.id, writer), EAlreadyDenied);

    dfield::add<address, u64>(&mut deny_obj.id, writer, period);

    pass_events::emit_writer_denied(system_id, file_id, writer, period, denied_by);
}

/// Move an existing denial's deadline to `period`, or to indefinite when zero.
///
/// Refuses a writer who holds no denial, so moving a deadline cannot silently
/// create one. It adds no denial, so the count the events carry stays where it
/// is; the deadline moving is still a change and is announced as one.
public(package) fun redeny(
    deny_obj: &mut DenyList,
    writer: address,
    period: u64,
    now_ms: u64,
    system_id: ID,
    file_id: ID,
    denied_by: address,
) {
    assert!(period == 0 || period > now_ms, INVALIDTIME);
    assert!(dfield::exists_(&deny_obj.id, writer), ENotDenied);

    *dfield::borrow_mut<address, u64>(&mut deny_obj.id, writer) = period;

    pass_events::emit_writer_denied(system_id, file_id, writer, period, denied_by);
}

/// Drop `writer`'s denial, or do nothing when they hold none.
///
/// Lifting a denial that was never recorded leaves the caller with exactly the
/// state they asked for, so it is not an error.
public(package) fun undeny(
    deny_obj: &mut DenyList,
    writer: address,
    system_id: ID,
    file_id: ID,
    undenied_by: address,
) {
    if (!dfield::exists_(&deny_obj.id, writer)) {
        return
    };

    let _ = dfield::remove<address, u64>(&mut deny_obj.id, writer);

    // Only a denial that was actually there is announced. Announcing the no-op
    // would report a state change that did not happen.
    pass_events::emit_writer_undenied(system_id, file_id, writer, undenied_by);
}

/// Revoke the pass `pass_id`, permanently.
///
/// There is no counterpart that lifts this. A pass is revoked because it is in
/// the wrong hands, and an unrevoke would hand whoever holds it a second chance.
/// The owner mints a replacement instead.
public(package) fun revoke_pass(
    deny_obj: &mut DenyList,
    pass_id: ID,
    system_id: ID,
    file_id: ID,
    revoked_by: address,
) {
    if (dfield::exists_<ID>(&deny_obj.id, pass_id)) {
        return
    };

    dfield::add<ID, bool>(&mut deny_obj.id, pass_id, true);

    pass_events::emit_writer_pass_revoked(system_id, file_id, pass_id, revoked_by);
}
