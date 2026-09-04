/// Holds the framework capability that governs this package's own code, so that
/// replacing the code answers to the same key as the treasury and the operator
/// set.
///
/// Publishing mints a `sui::package::UpgradeCap` and hands it to the sender.
/// Nothing in Move can intercept that: `init` accepts a one-time witness and a
/// `TxContext` and nothing else, so the capability cannot be wrapped at birth.
/// Left where publishing puts it, it is a loose object in a wallet, and whoever
/// holds it may replace every check the contract makes without presenting an
/// `AdminCap`, without the system being at any particular version, and without
/// the stream saying so.
///
/// Taking custody is therefore a second transaction, and it is the one that
/// closes the gap: from then on the capability lives here, the object is shared
/// so no wallet holds it, and the only way to reach it is an entry point that
/// demands the **original** capability for the system named below.
module warlot::upgrade;

// === Imports ===

use sui::package::{Self, UpgradeCap, UpgradeReceipt, UpgradeTicket};
use warlot::upgrade_events;

// === Structs ===

/// The package's upgrade capability, under a system's authority.
///
/// Shared rather than owned, and deliberately. An owned wrapper would mean an
/// upgrade needs two things ,  the original `AdminCap` and whatever address the
/// wrapper was last sent to ,  so a misdirected transfer would end the package's
/// upgradability while the admin key was still perfectly good. Shared, custody
/// is not a factor and the capability is the whole of the authority, which is
/// the property this module exists to establish.
///
/// `key` without `store`, so no other module can wrap it, transfer it, or take
/// the `UpgradeCap` back out into a wallet. The only exit is `destroy`.
public struct UpgradeAuthority has key {
    id: UID,
    /// The system whose original capability authorises through here.
    system: ID,
    /// The framework capability. Never lent out by reference.
    cap: UpgradeCap,
}

// === View functions ===

/// The system whose original capability authorises through here.
public fun system(authority: &UpgradeAuthority): ID {
    authority.system
}

/// The framework capability this authority holds.
public fun upgrade_cap(authority: &UpgradeAuthority): ID {
    object::id(&authority.cap)
}

/// The package this authority governs.
///
/// The zero id while an upgrade is authorised and not yet committed, because
/// that is how the framework marks a capability with a ticket outstanding. No
/// transaction can observe it: the ticket has no abilities, so it cannot outlive
/// the transaction that issued it, and a transaction that fails to consume it
/// does not commit at all.
public fun package_id(authority: &UpgradeAuthority): ID {
    package::upgrade_package(&authority.cap)
}

/// The capability's version counter, `1` for a package never yet upgraded.
public fun version(authority: &UpgradeAuthority): u64 {
    package::version(&authority.cap)
}

/// The most permissive upgrade this authority still allows: `0` compatible,
/// `128` additive, `192` dependency-only.
public fun policy(authority: &UpgradeAuthority): u8 {
    package::upgrade_policy(&authority.cap)
}

// === Package functions ===

/// Take custody of `cap` on behalf of `system`, and share the result.
public(package) fun new(cap: UpgradeCap, system: ID, created_by: address, ctx: &mut TxContext) {
    let authority = UpgradeAuthority {
        id: object::new(ctx),
        system,
        cap,
    };

    upgrade_events::emit_upgrade_authority_created(
        system,
        object::id(&authority),
        object::id(&authority.cap),
        package::upgrade_package(&authority.cap),
        package::version(&authority.cap),
        package::upgrade_policy(&authority.cap),
        created_by,
    );

    transfer::share_object(authority);
}

/// Issue a ticket authorising an upgrade to the build `digest` names.
///
/// The policy is read from the capability rather than taken from the caller.
/// `package::authorize_upgrade` accepts any `u8` at least as restrictive as the
/// capability's own, which means it also accepts the values between the three
/// the framework defines, and what a validator makes of one of those is not
/// something this package can check. Reading it back from the capability leaves
/// exactly one place a policy is ever chosen ,  the ratchet ,  and that place
/// only accepts the framework's own constants.
public(package) fun authorise(
    authority: &mut UpgradeAuthority,
    digest: vector<u8>,
    authorised_by: address,
): UpgradeTicket {
    let policy = package::upgrade_policy(&authority.cap);

    // Read before the call: authorising zeroes the capability's package id.
    let package_id = package::upgrade_package(&authority.cap);

    let ticket = package::authorize_upgrade(&mut authority.cap, policy, digest);

    upgrade_events::emit_upgrade_authorised(
        authority.system,
        object::id(authority),
        package_id,
        policy,
        *package::ticket_digest(&ticket),
        authorised_by,
    );

    ticket
}

/// Consume the receipt the upgrade produced, moving the authority onto the new
/// package.
public(package) fun commit(
    authority: &mut UpgradeAuthority,
    receipt: UpgradeReceipt,
    committed_by: address,
) {
    package::commit_upgrade(&mut authority.cap, receipt);

    upgrade_events::emit_upgrade_committed(
        authority.system,
        object::id(authority),
        package::upgrade_package(&authority.cap),
        package::version(&authority.cap),
        committed_by,
    );
}

/// Restrict future upgrades to additions and dependency changes.
public(package) fun restrict_to_additive(
    authority: &mut UpgradeAuthority,
    restricted_by: address,
) {
    package::only_additive_upgrades(&mut authority.cap);

    // Read back rather than assumed, so the announcement is the capability's
    // state and not the intent of the call that changed it.
    upgrade_events::emit_upgrade_policy_restricted(
        authority.system,
        object::id(authority),
        package::upgrade_policy(&authority.cap),
        restricted_by,
    );
}

/// Restrict future upgrades to dependency changes alone.
public(package) fun restrict_to_dep_only(authority: &mut UpgradeAuthority, restricted_by: address) {
    package::only_dep_upgrades(&mut authority.cap);

    upgrade_events::emit_upgrade_policy_restricted(
        authority.system,
        object::id(authority),
        package::upgrade_policy(&authority.cap),
        restricted_by,
    );
}

/// Destroy the authority and the capability inside it, freezing the package.
///
/// Terminal for the package, not just for this object: `package::make_immutable`
/// deletes the capability, and nothing can mint another for a package already
/// published.
public(package) fun destroy(authority: UpgradeAuthority, destroyed_by: address) {
    let UpgradeAuthority { id, system, cap } = authority;

    upgrade_events::emit_upgrade_authority_destroyed(
        system,
        id.to_inner(),
        package::upgrade_package(&cap),
        package::version(&cap),
        destroyed_by,
    );

    id.delete();
    package::make_immutable(cap);
}
