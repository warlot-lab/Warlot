/// An admin capability is authority over one system, not authority in general.
/// Since minting a successor and migrating users between systems are both
/// supported operations, a capability that carried across systems would leave
/// the isolation those two rely on with nothing behind it.
#[test_only]
module warlot::admin_tests;

use sui::test_scenario as ts;
use wal::wal::WAL;
use warlot::{admin_cap::AdminCap, entry_admin, system_config::{Self, SystemConfig}};

// === Constants ===

const ADMIN: address = @0xADA;
const OUTSIDER: address = @0xB0B;
const FEE: u64 = 100;
const NEW_FEE: u64 = 250;
const AMOUNT: u64 = 1;

// === Test-only helpers ===

/// A system, the successor it minted, and the original capability for the first
/// of them. The successor carries its own capability, which stays in the
/// admin's account.
fun two_systems(sc: &mut ts::Scenario): (SystemConfig, SystemConfig, AdminCap) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ADMIN);
    let mut cap = sc.take_from_sender<AdminCap>();
    let mut first = sc.take_shared<SystemConfig>();

    entry_admin::mint_system(&mut cap, &mut first, FEE, FEE, FEE, FEE, sc.ctx());
    let successor_id = *option::borrow(first.next_system());

    sc.next_tx(ADMIN);
    let second = ts::take_shared_by_id<SystemConfig>(sc, successor_id);

    (first, second, cap)
}

#[test]
fun a_matching_cap_is_accepted() {
    let mut sc = ts::begin(ADMIN);
    let (mut first, second, mut cap) = two_systems(&mut sc);

    entry_admin::update_cost(&mut cap, &mut first, NEW_FEE, NEW_FEE, NEW_FEE);
    assert!(first.cost_to_update_name() == NEW_FEE, 0);

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun cap_bound_to_system() {
    let mut sc = ts::begin(ADMIN);
    let (first, mut second, mut cap) = two_systems(&mut sc);

    entry_admin::update_cost(&mut cap, &mut second, NEW_FEE, NEW_FEE, NEW_FEE);

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun a_foreign_cap_cannot_withdraw_wal() {
    let mut sc = ts::begin(ADMIN);
    let (first, mut second, mut cap) = two_systems(&mut sc);

    entry_admin::withdraw_system_wal(&mut second, &mut cap, AMOUNT, sc.ctx());

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun a_foreign_cap_cannot_withdraw_a_coin() {
    let mut sc = ts::begin(ADMIN);
    let (first, mut second, mut cap) = two_systems(&mut sc);

    entry_admin::withdraw_system_coin<WAL>(&mut second, &mut cap, AMOUNT, sc.ctx());

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun a_foreign_cap_cannot_add_a_coin_type() {
    let mut sc = ts::begin(ADMIN);
    let (first, mut second, mut cap) = two_systems(&mut sc);

    entry_admin::add_coin_type<WAL>(&mut cap, &mut second);

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun a_foreign_cap_cannot_remove_a_coin_type() {
    let mut sc = ts::begin(ADMIN);
    let (first, mut second, mut cap) = two_systems(&mut sc);

    entry_admin::remove_supported_coin<WAL>(&mut cap, &mut second);

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun a_foreign_cap_cannot_mint_a_system() {
    let mut sc = ts::begin(ADMIN);
    let (first, mut second, mut cap) = two_systems(&mut sc);

    entry_admin::mint_system(&mut cap, &mut second, FEE, FEE, FEE, FEE, sc.ctx());

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ECapForAnotherSystem)]
fun a_foreign_cap_cannot_mint_an_admin() {
    let mut sc = ts::begin(ADMIN);
    let (first, second, cap) = two_systems(&mut sc);

    entry_admin::mint_admin(&second, OUTSIDER, &cap, sc.ctx());

    sc.return_to_sender(cap);
    ts::return_shared(first);
    ts::return_shared(second);
    sc.end();
}
