/// Delegation is a table the account owner writes and unwrites at will. A grant
/// is what lets a delegate act; a revoke is what stops them; and the owner needs
/// neither, because an account with an empty table still belongs to somebody.
#[test_only]
module warlot::permission_tests;

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use warlot::{
    entry_permission,
    entry_register,
    fixtures,
    store,
    system_config::{Self, SystemConfig},
    user,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const MALLORY: address = @0xBAD;
const SET: u32 = 13;
const CYCLES: u64 = 2;
const START_EPOCHS: u32 = 5;
const BLOB_SIZE: u64 = 1_024;

// === Test-only helpers ===

#[test]
fun grant_then_use() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    // `new_for_testing` runs on a dummy context, so the sender has to be put back.
    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    // Registering publicly leaves the delegation table empty.
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, true, true, false, sc.ctx());

    // Bob now stores under Alice's address, on Alice's account, as himself.
    sc.next_tx(BOB);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        BLOB_SIZE,
        START_EPOCHS,
        &mut funds,
        sc.ctx(),
    );
    let (_, stored_size) = store::store_blob_internal(
        &sys,
        vector[raw_blob],
        SET,
        CYCLES,
        ALICE,
        &clk,
        sc.ctx(),
    );
    assert!(stored_size == BLOB_SIZE, 0);

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
fun a_stranger_cannot_act_without_a_grant() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    sc.next_tx(BOB);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        BLOB_SIZE,
        START_EPOCHS,
        &mut funds,
        sc.ctx(),
    );
    let (_, _) = store::store_blob_internal(
        &sys,
        vector[raw_blob],
        SET,
        CYCLES,
        ALICE,
        &clk,
        sc.ctx(),
    );

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
fun revoke_then_denied() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, true, true, false, sc.ctx());
    entry_permission::revoke(&mut sys, ALICE, BOB, sc.ctx());

    // The same call that succeeds in `grant_then_use`, by the same address.
    sc.next_tx(BOB);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        BLOB_SIZE,
        START_EPOCHS,
        &mut funds,
        sc.ctx(),
    );
    let (_, _) = store::store_blob_internal(
        &sys,
        vector[raw_blob],
        SET,
        CYCLES,
        ALICE,
        &clk,
        sc.ctx(),
    );

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun owner_never_needs_grant() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    // Every gate, against a table that holds nothing at all.
    sc.next_tx(ALICE);
    let alice = user::get_user(&sys, ALICE);
    user::check_permission_add_blob(alice, sc.ctx());
    user::check_permission_inner_file(alice, sc.ctx());
    user::check_permission_writer_pass(alice, sc.ctx());
    user::check_permission_can_init_db(alice, sc.ctx());

    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_permission::ENotAccountOwner)]
fun only_owner_may_grant() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    // Mallory names Alice's account and hands the bits to herself.
    sc.next_tx(MALLORY);
    entry_permission::grant(&mut sys, ALICE, MALLORY, true, true, true, true, true, sc.ctx());

    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
