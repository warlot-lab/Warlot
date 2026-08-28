/// Declares the events a system object raises: its creation, its configuration,
/// and the capabilities that administer it.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::system_events;

// === Imports ===

use sui::event;

// === Events ===

/// A system was created: the first at publication, every later one by minting.
public struct SystemCreated has copy, drop, store {
    system_id: ID,
    /// The system this one descends from; the zero id for the first.
    previous_system: ID,
    minted_by: address,
    version: u64,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
}

/// A system named its successor, closing the mint chain behind it.
public struct SystemSucceeded has copy, drop, store {
    system_id: ID,
    next_system: ID,
    minted_by: address,
}

/// The registry modification fees were replaced.
public struct SystemFeesChanged has copy, drop, store {
    system_id: ID,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    changed_by: address,
}

/// The storage terms a system sells were replaced.
public struct SystemTiersChanged has copy, drop, store {
    system_id: ID,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    changed_by: address,
}

/// A system was raised to the package version.
public struct SystemVersionMigrated has copy, drop, store {
    system_id: ID,
    version: u64,
    migrated_by: address,
}

/// An admin capability reached an account.
///
/// Emitted where custody is handed over rather than where the capability is
/// built, so the holder is always named ,  a capability nobody holds is not
/// authority over anything.
public struct AdminCapMinted has copy, drop, store {
    system_id: ID,
    admin_cap: ID,
    /// `0` for an original capability, `1` for a duplicate.
    state: u8,
    total_system: u8,
    recipient: address,
    minted_by: address,
}

/// A capability was given a slot it did not hold before.
///
/// The slot is the whole of the grant a backend key holds at the system level:
/// the id it names, when it stops being accepted, and whether it may ask to skip
/// a file's draft queue. Moving the capability to another wallet raises nothing
/// here, because nothing here changes.
public struct SystemOperatorEnrolled has copy, drop, store {
    system_id: ID,
    admin_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    enrolled_by: address,
}

/// A slot a capability already held was given new terms.
///
/// Distinct from the enrolment for the same reason the two calls are: a consumer
/// reading "enrolled" for a deadline being moved would record a key arriving that
/// had been there all along.
public struct SystemOperatorRefreshed has copy, drop, store {
    system_id: ID,
    admin_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    refreshed_by: address,
}

/// A capability lost its slot in the system's operator set.
///
/// Raised only where a slot was actually removed. Retiring an id that holds none
/// is a no-op and announces nothing, so a retirement in the stream is always a
/// retirement that happened.
public struct SystemOperatorRetired has copy, drop, store {
    system_id: ID,
    admin_cap: ID,
    retired_by: address,
}

// === Package functions ===

/// Announce a newly created system.
public(package) fun emit_system_created(
    system_id: ID,
    previous_system: ID,
    minted_by: address,
    version: u64,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
) {
    event::emit(SystemCreated {
        system_id,
        previous_system,
        minted_by,
        version,
        tier_table,
        max_epochs_ahead,
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
    })
}

/// Announce a system naming its successor.
public(package) fun emit_system_succeeded(system_id: ID, next_system: ID, minted_by: address) {
    event::emit(SystemSucceeded { system_id, next_system, minted_by })
}

/// Announce replaced registry modification fees.
public(package) fun emit_system_fees_changed(
    system_id: ID,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    changed_by: address,
) {
    event::emit(SystemFeesChanged {
        system_id,
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
        changed_by,
    })
}

/// Announce a replaced storage-term ladder.
public(package) fun emit_system_tiers_changed(
    system_id: ID,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    changed_by: address,
) {
    event::emit(SystemTiersChanged {
        system_id,
        tier_table,
        max_epochs_ahead,
        changed_by,
    })
}

/// Announce a system raised to the package version.
public(package) fun emit_system_version_migrated(
    system_id: ID,
    version: u64,
    migrated_by: address,
) {
    event::emit(SystemVersionMigrated { system_id, version, migrated_by })
}

/// Announce an admin capability reaching an account.
public(package) fun emit_admin_cap_minted(
    system_id: ID,
    admin_cap: ID,
    state: u8,
    total_system: u8,
    recipient: address,
    minted_by: address,
) {
    event::emit(AdminCapMinted {
        system_id,
        admin_cap,
        state,
        total_system,
        recipient,
        minted_by,
    })
}

/// Announce a capability taking a slot it did not hold.
public(package) fun emit_system_operator_enrolled(
    system_id: ID,
    admin_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    enrolled_by: address,
) {
    event::emit(SystemOperatorEnrolled {
        system_id,
        admin_cap,
        until_ms,
        may_bypass_draft,
        enrolled_by,
    })
}

/// Announce a held slot being given new terms.
public(package) fun emit_system_operator_refreshed(
    system_id: ID,
    admin_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    refreshed_by: address,
) {
    event::emit(SystemOperatorRefreshed {
        system_id,
        admin_cap,
        until_ms,
        may_bypass_draft,
        refreshed_by,
    })
}

/// Announce an operator slot retired.
public(package) fun emit_system_operator_retired(
    system_id: ID,
    admin_cap: ID,
    retired_by: address,
) {
    event::emit(SystemOperatorRetired { system_id, admin_cap, retired_by })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `SystemCreated`, in declaration order.
public fun read_system_created(e: &SystemCreated): (
    ID,
    ID,
    address,
    u64,
    vector<u32>,
    u32,
    u64,
    u64,
    u64,
    u64,
) {
    let SystemCreated {
        system_id: _system_id,
        previous_system: _previous_system,
        minted_by: _minted_by,
        version: _version,
        tier_table: _tier_table,
        max_epochs_ahead: _max_epochs_ahead,
        cost_change_apikey_forms: _cost_change_apikey_forms,
        cost_to_migrate_system: _cost_to_migrate_system,
        cost_to_update_name: _cost_to_update_name,
        cost_to_delete: _cost_to_delete,
    } = e;

    (
        *_system_id,
        *_previous_system,
        *_minted_by,
        *_version,
        *_tier_table,
        *_max_epochs_ahead,
        *_cost_change_apikey_forms,
        *_cost_to_migrate_system,
        *_cost_to_update_name,
        *_cost_to_delete,
    )
}

#[test_only]
/// Every field of `SystemSucceeded`, in declaration order.
public fun read_system_succeeded(e: &SystemSucceeded): (ID, ID, address) {
    let SystemSucceeded {
        system_id: _system_id,
        next_system: _next_system,
        minted_by: _minted_by,
    } = e;

    (*_system_id, *_next_system, *_minted_by)
}

#[test_only]
/// Every field of `SystemFeesChanged`, in declaration order.
public fun read_system_fees_changed(e: &SystemFeesChanged): (ID, u64, u64, u64, u64, address) {
    let SystemFeesChanged {
        system_id: _system_id,
        cost_change_apikey_forms: _cost_change_apikey_forms,
        cost_to_migrate_system: _cost_to_migrate_system,
        cost_to_update_name: _cost_to_update_name,
        cost_to_delete: _cost_to_delete,
        changed_by: _changed_by,
    } = e;

    (
        *_system_id,
        *_cost_change_apikey_forms,
        *_cost_to_migrate_system,
        *_cost_to_update_name,
        *_cost_to_delete,
        *_changed_by,
    )
}

#[test_only]
/// Every field of `SystemTiersChanged`, in declaration order.
public fun read_system_tiers_changed(e: &SystemTiersChanged): (ID, vector<u32>, u32, address) {
    let SystemTiersChanged {
        system_id: _system_id,
        tier_table: _tier_table,
        max_epochs_ahead: _max_epochs_ahead,
        changed_by: _changed_by,
    } = e;

    (*_system_id, *_tier_table, *_max_epochs_ahead, *_changed_by)
}

#[test_only]
/// Every field of `SystemVersionMigrated`, in declaration order.
public fun read_system_version_migrated(e: &SystemVersionMigrated): (ID, u64, address) {
    let SystemVersionMigrated {
        system_id: _system_id,
        version: _version,
        migrated_by: _migrated_by,
    } = e;

    (*_system_id, *_version, *_migrated_by)
}

#[test_only]
/// Every field of `AdminCapMinted`, in declaration order.
public fun read_admin_cap_minted(e: &AdminCapMinted): (ID, ID, u8, u8, address, address) {
    let AdminCapMinted {
        system_id: _system_id,
        admin_cap: _admin_cap,
        state: _state,
        total_system: _total_system,
        recipient: _recipient,
        minted_by: _minted_by,
    } = e;

    (*_system_id, *_admin_cap, *_state, *_total_system, *_recipient, *_minted_by)
}

#[test_only]
/// Every field of `SystemOperatorEnrolled`, in declaration order.
public fun read_system_operator_enrolled(e: &SystemOperatorEnrolled): (ID, ID, u64, bool, address) {
    let SystemOperatorEnrolled {
        system_id: _system_id,
        admin_cap: _admin_cap,
        until_ms: _until_ms,
        may_bypass_draft: _may_bypass_draft,
        enrolled_by: _enrolled_by,
    } = e;

    (*_system_id, *_admin_cap, *_until_ms, *_may_bypass_draft, *_enrolled_by)
}

#[test_only]
/// Every field of `SystemOperatorRefreshed`, in declaration order.
public fun read_system_operator_refreshed(e: &SystemOperatorRefreshed): (ID, ID, u64, bool, address) {
    let SystemOperatorRefreshed {
        system_id: _system_id,
        admin_cap: _admin_cap,
        until_ms: _until_ms,
        may_bypass_draft: _may_bypass_draft,
        refreshed_by: _refreshed_by,
    } = e;

    (*_system_id, *_admin_cap, *_until_ms, *_may_bypass_draft, *_refreshed_by)
}

#[test_only]
/// Every field of `SystemOperatorRetired`, in declaration order.
public fun read_system_operator_retired(e: &SystemOperatorRetired): (ID, ID, address) {
    let SystemOperatorRetired {
        system_id: _system_id,
        admin_cap: _admin_cap,
        retired_by: _retired_by,
    } = e;

    (*_system_id, *_admin_cap, *_retired_by)
}
