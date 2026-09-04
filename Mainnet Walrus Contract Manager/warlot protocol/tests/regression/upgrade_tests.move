/// The package's own code is the one thing the authority model did not reach.
/// Every privileged call in the protocol answers to the original `AdminCap`, and
/// until the capability publication mints is taken into custody, replacing all of
/// those checks answers to nothing but whichever wallet holds one loose object.
///
/// These pin the boundary: who may authorise, who may not, that the policy
/// ratchet turns one way, and that freezing the package ends it.
#[test_only]
module warlot::upgrade_tests;

// === Imports ===

use sui::{package::{Self, UpgradeCap}, test_scenario as ts};
use warlot::{
    admin_cap::AdminCap,
    entry_admin,
    entry_upgrade,
    replay,
    system_config::{Self, SystemConfig},
    upgrade::UpgradeAuthority
};

// === Constants ===

const ADMIN: address = @0xADA;
const BACKEND: address = @0xB0B;

/// Stands in for the id publication would give the package.
const PACKAGE: address = @0xFACADE;

/// The framework's own policy constants, which are `0`, `128` and `192` and not
/// the `1`, `2`, `3` the documentation site gives.
const COMPATIBLE: u8 = 0;
const ADDITIVE: u8 = 128;
const DEP_ONLY: u8 = 192;

const DIGEST: vector<u8> = b"a build that was reviewed";
const FEE: u64 = 100;

// === Test-only helpers ===

/// A system whose upgrade capability is already under its authority ,  the state
/// the transaction after publication leaves behind.
///
/// The capability is transferred to the publisher first and taken back out of
/// their account, because that is what publication actually does, and it is what
/// lets the custody test show the wallet is empty afterwards.
fun under_authority(sc: &mut ts::Scenario): (UpgradeAuthority, AdminCap) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ADMIN);
    let admin_cap = sc.take_from_sender<AdminCap>();
    transfer::public_transfer(
        package::test_publish(object::id_from_address(PACKAGE), sc.ctx()),
        ADMIN,
    );

    sc.next_tx(ADMIN);
    let published = sc.take_from_sender<UpgradeCap>();
    entry_upgrade::take_custody(published, &admin_cap, sc.ctx());

    sc.next_tx(ADMIN);
    let authority = sc.take_shared<UpgradeAuthority>();

    (authority, admin_cap)
}

// === Tests ===

#[test]
fun custody_leaves_no_loose_capability() {
    let mut sc = ts::begin(ADMIN);
    let (authority, admin_cap) = under_authority(&mut sc);

    assert!(authority.package_id() == object::id_from_address(PACKAGE), 0);
    assert!(authority.policy() == COMPATIBLE, 1);
    assert!(authority.system() == admin_cap.system_config_id(), 2);

    // The whole point of the scope: after custody there is no capability in the
    // wallet, so no path to replace the code that does not pass through here.
    assert!(!ts::has_most_recent_for_sender<UpgradeCap>(&sc), 3);

    sc.return_to_sender(admin_cap);
    ts::return_shared(authority);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ENotOriginalCap)]
fun a_duplicate_cannot_take_custody() {
    let mut sc = ts::begin(ADMIN);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ADMIN);
    let admin_cap = sc.take_from_sender<AdminCap>();
    let sys = sc.take_shared<SystemConfig>();
    entry_admin::mint_admin(&sys, BACKEND, &admin_cap, sc.ctx());

    sc.next_tx(BACKEND);
    let duplicate = sc.take_from_sender<AdminCap>();
    let published = package::test_publish(object::id_from_address(PACKAGE), sc.ctx());

    entry_upgrade::take_custody(published, &duplicate, sc.ctx());

    abort
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ENotOriginalCap)]
fun a_duplicate_cannot_authorise() {
    let mut sc = ts::begin(ADMIN);
    let (mut authority, admin_cap) = under_authority(&mut sc);

    let sys = sc.take_shared<SystemConfig>();
    entry_admin::mint_admin(&sys, BACKEND, &admin_cap, sc.ctx());

    // A backend key is a duplicate holding an operator slot. It signs for users
    // all day and it does not get to replace the code it is signing against.
    sc.next_tx(BACKEND);
    let duplicate = sc.take_from_sender<AdminCap>();

    let ticket = entry_upgrade::authorise_upgrade(
        &mut authority,
        &duplicate,
        DIGEST,
        sc.ctx(),
    );

    entry_upgrade::commit_upgrade(
        &mut authority,
        &duplicate,
        package::test_upgrade(ticket),
        sc.ctx(),
    );

    abort
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun a_cap_for_another_system_cannot_authorise() {
    let mut sc = ts::begin(ADMIN);
    let (mut authority, mut admin_cap) = under_authority(&mut sc);

    let mut sys = sc.take_shared<SystemConfig>();
    entry_admin::mint_system(&mut admin_cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());

    // The successor's capability is an original, and it is an original for the
    // wrong system. `mint_system` and `migrate_system` are the reason that has to
    // be refused rather than merely unusual.
    sc.next_tx(ADMIN);
    let successor_cap = sc.take_from_sender<AdminCap>();

    let ticket = entry_upgrade::authorise_upgrade(
        &mut authority,
        &successor_cap,
        DIGEST,
        sc.ctx(),
    );

    entry_upgrade::commit_upgrade(
        &mut authority,
        &successor_cap,
        package::test_upgrade(ticket),
        sc.ctx(),
    );

    abort
}

#[test]
fun the_ratchet_tightens() {
    let mut sc = ts::begin(ADMIN);
    let (mut authority, admin_cap) = under_authority(&mut sc);

    entry_upgrade::restrict_to_additive(&mut authority, &admin_cap, sc.ctx());
    assert!(authority.policy() == ADDITIVE, 0);

    entry_upgrade::restrict_to_dep_only(&mut authority, &admin_cap, sc.ctx());
    assert!(authority.policy() == DEP_ONLY, 1);

    sc.return_to_sender(admin_cap);
    ts::return_shared(authority);
    sc.end();
}

#[test]
#[expected_failure(abort_code = sui::package::ETooPermissive)]
fun the_ratchet_does_not_loosen() {
    let mut sc = ts::begin(ADMIN);
    let (mut authority, admin_cap) = under_authority(&mut sc);

    entry_upgrade::restrict_to_dep_only(&mut authority, &admin_cap, sc.ctx());
    entry_upgrade::restrict_to_additive(&mut authority, &admin_cap, sc.ctx());

    abort
}

#[test]
fun an_upgrade_round_trip() {
    let mut sc = ts::begin(ADMIN);
    let (mut authority, admin_cap) = under_authority(&mut sc);

    let before = authority.version();

    let ticket = entry_upgrade::authorise_upgrade(&mut authority, &admin_cap, DIGEST, sc.ctx());

    // The ticket is bound to the build, not merely to the package: this is what a
    // reviewer compares against the digest of what they reviewed.
    assert!(*ticket.digest() == DIGEST, 0);
    assert!(ticket.policy() == COMPATIBLE, 1);

    entry_upgrade::commit_upgrade(
        &mut authority,
        &admin_cap,
        package::test_upgrade(ticket),
        sc.ctx(),
    );

    assert!(authority.version() == before + 1, 2);
    assert!(authority.package_id() != object::id_from_address(PACKAGE), 3);

    sc.return_to_sender(admin_cap);
    ts::return_shared(authority);
    sc.end();
}

#[test]
#[expected_failure(abort_code = sui::package::EAlreadyAuthorized)]
fun one_ticket_at_a_time() {
    let mut sc = ts::begin(ADMIN);
    let (mut authority, admin_cap) = under_authority(&mut sc);

    let first = entry_upgrade::authorise_upgrade(&mut authority, &admin_cap, DIGEST, sc.ctx());
    let second = entry_upgrade::authorise_upgrade(&mut authority, &admin_cap, DIGEST, sc.ctx());

    entry_upgrade::commit_upgrade(
        &mut authority,
        &admin_cap,
        package::test_upgrade(first),
        sc.ctx(),
    );
    entry_upgrade::commit_upgrade(
        &mut authority,
        &admin_cap,
        package::test_upgrade(second),
        sc.ctx(),
    );

    abort
}

#[test]
fun freezing_is_terminal() {
    let mut sc = ts::begin(ADMIN);
    let (authority, admin_cap) = under_authority(&mut sc);

    entry_upgrade::make_immutable(authority, &admin_cap, sc.ctx());

    sc.next_tx(ADMIN);

    // Nothing holds the capability now, here or anywhere: the authority is gone
    // and the framework deleted the capability with it.
    assert!(!ts::has_most_recent_shared<UpgradeAuthority>(), 0);
    assert!(!ts::has_most_recent_for_sender<UpgradeCap>(&sc), 1);

    sc.return_to_sender(admin_cap);
    sc.end();
}

#[test]
fun the_stream_rebuilds_the_authority() {
    let mut sc = ts::begin(ADMIN);
    let mut ledger = replay::new();

    system_config::init_for_testing(sc.ctx());
    ledger.absorb();

    sc.next_tx(ADMIN);
    let admin_cap = sc.take_from_sender<AdminCap>();
    transfer::public_transfer(
        package::test_publish(object::id_from_address(PACKAGE), sc.ctx()),
        ADMIN,
    );
    ledger.absorb();

    sc.next_tx(ADMIN);
    let published = sc.take_from_sender<UpgradeCap>();
    entry_upgrade::take_custody(published, &admin_cap, sc.ctx());
    ledger.absorb();

    sc.next_tx(ADMIN);
    let mut authority = sc.take_shared<UpgradeAuthority>();
    let authority_id = object::id(&authority);

    entry_upgrade::restrict_to_additive(&mut authority, &admin_cap, sc.ctx());
    ledger.absorb();

    sc.next_tx(ADMIN);
    let ticket = entry_upgrade::authorise_upgrade(&mut authority, &admin_cap, DIGEST, sc.ctx());
    entry_upgrade::commit_upgrade(
        &mut authority,
        &admin_cap,
        package::test_upgrade(ticket),
        sc.ctx(),
    );
    ledger.absorb();

    // Written from the chain side: every field of the authority the chain holds
    // has to come back out of the stream alone.
    let row = ledger.upgrade(authority_id);
    assert!(row.upgrade_system() == authority.system(), 0);
    assert!(row.upgrade_package() == authority.package_id(), 1);
    assert!(row.upgrade_version() == authority.version(), 2);
    assert!(row.upgrade_policy() == authority.policy(), 3);
    assert!(row.upgrade_live(), 4);

    sc.next_tx(ADMIN);
    entry_upgrade::make_immutable(authority, &admin_cap, sc.ctx());
    ledger.absorb();

    // A consumer that only ever added rows would still be showing an upgradable
    // package here, which is the case the stream has to be able to close.
    assert!(!ledger.upgrade(authority_id).upgrade_live(), 5);

    sc.return_to_sender(admin_cap);
    sc.end();
}
