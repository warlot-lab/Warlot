/// The user record is attached and detached through the same dynamic-field family,
/// so it can be taken back out. `remove_user` completes, and with it the migration
/// that is the only reason it exists.
#[test_only]
module warlot::migration_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, coin, test_scenario as ts};
use wal::wal::WAL;
use warlot::{
    admin_cap::AdminCap,
    entry_admin,
    entry_register,
    registry::Registry,
    system_config::{Self, SystemConfig},
    user,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const MIGRATION_COST: u64 = 100;

// === Test-only helpers ===

#[test]
fun remove_user_returns_the_user_record() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    let alice = user::remove_user(&mut sys, ALICE);
    assert!(!user::check_user(&sys, ALICE), 0);

    destroy(alice);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun migrate_system_moves_a_user_between_systems() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    // Mint the successor system the registry will be repointed at.
    sc.next_tx(ALICE);
    let mut current = sc.take_shared<SystemConfig>();
    let mut admin_cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_system(
        &mut admin_cap,
        &mut current,
        MIGRATION_COST,
        MIGRATION_COST,
        MIGRATION_COST,
        MIGRATION_COST,
        sc.ctx(),
    );
    let next_id = *current.next_system().borrow();

    sc.next_tx(ALICE);
    let mut next = ts::take_shared_by_id<SystemConfig>(&sc, next_id);
    let clk = clock::create_for_testing(sc.ctx());
    entry_register::all_register_user_publicly(
        &mut current,
        b"alice".to_string(),
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let mut registry = sc.take_from_sender<Registry>();
    let mut fee = coin::mint_for_testing<WAL>(MIGRATION_COST, sc.ctx());

    entry_register::migrate_system(
        &mut registry,
        &mut current,
        &mut next,
        &mut fee,
        &clk,
        sc.ctx(),
    );

    assert!(!user::check_user(&current, ALICE), 0);
    assert!(user::check_user(&next, ALICE), 1);
    assert!(registry.get_system() == next_id, 2);

    destroy(fee);
    destroy(registry);
    destroy(admin_cap);
    clock::destroy_for_testing(clk);
    ts::return_shared(current);
    ts::return_shared(next);
    sc.end();
}
