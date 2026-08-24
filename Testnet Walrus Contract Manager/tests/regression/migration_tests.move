/// C-3b: `remove_user` aborts, because `add_user` stores the user with
/// `dynamic_object_field` while `remove_user` reads it with `dynamic_field`.
/// System migration therefore always fails.
#[test_only]
module warlot::migration_tests;

// === Imports ===

use sui::{clock, test_scenario as ts, test_utils};
use warlot::{entry_register, system_config::{Self, SystemConfig}, user};

// === Constants ===

const ALICE: address = @0xA11CE;

// === Test-only helpers ===

#[test]
#[expected_failure]
fun remove_user_aborts_on_field_api_mismatch() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());
    sc.next_tx(ALICE);

    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    entry_register::all_register_user_publicly(
        &mut sys,
        b"alice".to_string(),
        &clk,
        sc.ctx(),
    );

    let u = user::remove_user(&mut sys, ALICE); // aborts here

    test_utils::destroy(u);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
