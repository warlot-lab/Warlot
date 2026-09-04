/// Declares the events the package's own upgrade authority raises: the custody of
/// the framework capability, the upgrades it authorises and commits, the policy
/// ratchet, and the one call that ends it.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::upgrade_events;

// === Imports ===

use sui::event;

// === Events ===

/// The framework upgrade capability was placed under a system's authority.
///
/// Until this is raised, the capability the publish transaction created is a
/// loose object in a wallet and the code can be replaced without the contract
/// having any say. The stream therefore carries the moment the package's own
/// upgrade came under the same key as the treasury, and names both objects.
public struct UpgradeAuthorityCreated has copy, drop, store {
    system_id: ID,
    authority_id: ID,
    /// The framework `UpgradeCap` now held inside the authority.
    upgrade_cap: ID,
    /// The package the capability governs, as of custody.
    package: ID,
    /// The capability's version counter. A package that has never been upgraded
    /// reads `1`, not `0` ,  read from testnet on two separate publications ,  and
    /// it rises by one on every commit.
    version: u64,
    /// `0` compatible, `128` additive, `192` dependency-only.
    policy: u8,
    created_by: address,
}

/// An upgrade was authorised: a ticket was issued for one specific set of
/// bytecode.
///
/// The `digest` is what binds the authorisation to the code. A consumer that
/// wants to know an upgrade was the one that was reviewed compares this against
/// the digest of the reviewed build, because nothing else in the stream
/// distinguishes two upgrades of the same package at the same version.
public struct UpgradeAuthorised has copy, drop, store {
    system_id: ID,
    authority_id: ID,
    /// The package the ticket authorises an upgrade of.
    package: ID,
    /// The policy the ticket carries, which is the authority's own.
    policy: u8,
    /// SHA3-256 of the modules and dependencies the upgrade may install.
    digest: vector<u8>,
    authorised_by: address,
}

/// An upgrade was committed: the package the authority governs is now the new
/// one, and its version has advanced by one.
///
/// The largest state change the protocol admits. Every `SystemConfig` is closed
/// at this point until an admin raises it to the new version, so a consumer
/// seeing this and no `SystemVersionMigrated` is looking at a protocol that
/// refuses every call.
public struct UpgradeCommitted has copy, drop, store {
    system_id: ID,
    authority_id: ID,
    /// The package the authority governs from here on.
    package: ID,
    /// The capability's version counter after this upgrade.
    version: u64,
    committed_by: address,
}

/// The upgrade policy was tightened.
///
/// The ratchet only ever moves one way, so this event is a narrowing of what
/// future upgrades may do and never a widening.
public struct UpgradePolicyRestricted has copy, drop, store {
    system_id: ID,
    authority_id: ID,
    /// `128` additive, `192` dependency-only.
    policy: u8,
    restricted_by: address,
}

/// The authority was destroyed and the package made immutable.
///
/// Terminal. No further upgrade of this package is possible by anyone, and no
/// event after this one names this authority.
public struct UpgradeAuthorityDestroyed has copy, drop, store {
    system_id: ID,
    authority_id: ID,
    /// The package that is now frozen.
    package: ID,
    /// The version it is frozen at.
    version: u64,
    destroyed_by: address,
}

// === Package functions ===

/// Announce the upgrade capability coming under a system's authority.
public(package) fun emit_upgrade_authority_created(
    system_id: ID,
    authority_id: ID,
    upgrade_cap: ID,
    package: ID,
    version: u64,
    policy: u8,
    created_by: address,
) {
    event::emit(UpgradeAuthorityCreated {
        system_id,
        authority_id,
        upgrade_cap,
        package,
        version,
        policy,
        created_by,
    })
}

/// Announce a ticket issued for one specific build.
public(package) fun emit_upgrade_authorised(
    system_id: ID,
    authority_id: ID,
    package: ID,
    policy: u8,
    digest: vector<u8>,
    authorised_by: address,
) {
    event::emit(UpgradeAuthorised {
        system_id,
        authority_id,
        package,
        policy,
        digest,
        authorised_by,
    })
}

/// Announce an upgrade taking effect.
public(package) fun emit_upgrade_committed(
    system_id: ID,
    authority_id: ID,
    package: ID,
    version: u64,
    committed_by: address,
) {
    event::emit(UpgradeCommitted { system_id, authority_id, package, version, committed_by })
}

/// Announce the policy being tightened.
public(package) fun emit_upgrade_policy_restricted(
    system_id: ID,
    authority_id: ID,
    policy: u8,
    restricted_by: address,
) {
    event::emit(UpgradePolicyRestricted { system_id, authority_id, policy, restricted_by })
}

/// Announce the authority being destroyed and the package frozen.
public(package) fun emit_upgrade_authority_destroyed(
    system_id: ID,
    authority_id: ID,
    package: ID,
    version: u64,
    destroyed_by: address,
) {
    event::emit(UpgradeAuthorityDestroyed {
        system_id,
        authority_id,
        package,
        version,
        destroyed_by,
    })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `UpgradeAuthorityCreated`, in declaration order.
public fun read_upgrade_authority_created(
    e: &UpgradeAuthorityCreated,
): (ID, ID, ID, ID, u64, u8, address) {
    let UpgradeAuthorityCreated {
        system_id: _system_id,
        authority_id: _authority_id,
        upgrade_cap: _upgrade_cap,
        package: _package,
        version: _version,
        policy: _policy,
        created_by: _created_by,
    } = e;

    (
        *_system_id,
        *_authority_id,
        *_upgrade_cap,
        *_package,
        *_version,
        *_policy,
        *_created_by,
    )
}

#[test_only]
/// Every field of `UpgradeAuthorised`, in declaration order.
public fun read_upgrade_authorised(
    e: &UpgradeAuthorised,
): (ID, ID, ID, u8, vector<u8>, address) {
    let UpgradeAuthorised {
        system_id: _system_id,
        authority_id: _authority_id,
        package: _package,
        policy: _policy,
        digest: _digest,
        authorised_by: _authorised_by,
    } = e;

    (*_system_id, *_authority_id, *_package, *_policy, *_digest, *_authorised_by)
}

#[test_only]
/// Every field of `UpgradeCommitted`, in declaration order.
public fun read_upgrade_committed(e: &UpgradeCommitted): (ID, ID, ID, u64, address) {
    let UpgradeCommitted {
        system_id: _system_id,
        authority_id: _authority_id,
        package: _package,
        version: _version,
        committed_by: _committed_by,
    } = e;

    (*_system_id, *_authority_id, *_package, *_version, *_committed_by)
}

#[test_only]
/// Every field of `UpgradePolicyRestricted`, in declaration order.
public fun read_upgrade_policy_restricted(e: &UpgradePolicyRestricted): (ID, ID, u8, address) {
    let UpgradePolicyRestricted {
        system_id: _system_id,
        authority_id: _authority_id,
        policy: _policy,
        restricted_by: _restricted_by,
    } = e;

    (*_system_id, *_authority_id, *_policy, *_restricted_by)
}

#[test_only]
/// Every field of `UpgradeAuthorityDestroyed`, in declaration order.
public fun read_upgrade_authority_destroyed(
    e: &UpgradeAuthorityDestroyed,
): (ID, ID, ID, u64, address) {
    let UpgradeAuthorityDestroyed {
        system_id: _system_id,
        authority_id: _authority_id,
        package: _package,
        version: _version,
        destroyed_by: _destroyed_by,
    } = e;

    (*_system_id, *_authority_id, *_package, *_version, *_destroyed_by)
}
