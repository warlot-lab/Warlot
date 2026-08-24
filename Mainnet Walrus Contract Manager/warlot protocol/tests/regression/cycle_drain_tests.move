/// A renewal cycle is spent only once an extension has actually happened, so a call
/// that does no work leaves the mandate exactly as it found it. What bounds a
/// caller is *when* the cycle is charged, not *who* they are: renewal stays open to
/// any address, which the last test here pins.
#[test_only]
module warlot::cycle_drain_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, coin, test_scenario as ts};
use wal::wal::WAL;
use walrus::blob;
use warlot::{blob_config::{Self, BlobConfig}, entry_renew, fixtures};

// === Constants ===

const ALICE: address = @0xA11CE;
const MALLORY: address = @0xBAD;
const SET: u32 = 13;
/// Short of `SET`, so a renewal has work to do.
const SHORT_EPOCHS: u32 = 5;
/// Past `SET`, so a renewal has nothing to do.
const LONG_EPOCHS: u32 = 20;
const CYCLES: u64 = 2;
/// Enough repetitions that a per-call leak of one cycle could not hide.
const ATTEMPTS: u64 = 100;

// === Test-only helpers ===

#[test]
#[expected_failure(abort_code = warlot::renew::EInvalidAhead)]
fun a_zero_horizon_is_refused() {
    let mut sc = ts::begin(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
        &mut wsys,
        ALICE,
        SET,
        option::some(CYCLES),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(MALLORY);
    let mut zero = coin::zero<WAL>(sc.ctx());
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&mut wsys, &mut config, &mut zero, 0);

    destroy(config);
    destroy(zero);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    sc.end();
}

#[test]
fun a_renewal_that_does_no_work_spends_no_cycle() {
    let mut sc = ts::begin(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    // The blob is already paid past the horizon, so there is nothing to extend.
    let config_id = fixtures::shared_config(
        &mut wsys,
        ALICE,
        SET,
        option::some(CYCLES),
        LONG_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(MALLORY);
    let mut zero = coin::zero<WAL>(sc.ctx());
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    let mut i = 0;
    while (i < ATTEMPTS) {
        entry_renew::renew_blob(&mut wsys, &mut config, &mut zero, SET);
        i = i + 1;
    };

    assert!(config.cycle_limit().borrow() == CYCLES, 0);
    assert!(zero.value() == 0, 1);

    ts::return_shared(config);
    destroy(zero);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    sc.end();
}

#[test]
fun an_exhausted_mandate_renews_nothing_and_aborts_nothing() {
    let mut sc = ts::begin(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
        &mut wsys,
        ALICE,
        SET,
        option::some(0),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(MALLORY);
    let mut zero = coin::zero<WAL>(sc.ctx());
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&mut wsys, &mut config, &mut zero, SET);

    assert!(config.cycle_limit().borrow() == 0, 0);
    assert!(zero.value() == 0, 1);

    sc.next_tx(ALICE);
    let blobs = blob_config::unwrap(config, sc.ctx());
    blobs.do_ref!(|held| assert!(blob::storage(held).end_epoch() == SHORT_EPOCHS, 2));

    destroy(blobs);
    destroy(zero);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    sc.end();
}

#[test]
fun an_unrelated_address_renews_another_users_blobs() {
    let mut sc = ts::begin(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let clk = clock::create_for_testing(sc.ctx());
    let mut alice_funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
        &mut wsys,
        ALICE,
        SET,
        option::some(CYCLES),
        SHORT_EPOCHS,
        &mut alice_funds,
        &clk,
        sc.ctx(),
    );

    // Mallory owns nothing here, holds no capability and is not even registered.
    // She pays, and that is the whole of her entitlement to renew.
    sc.next_tx(MALLORY);
    let mut mallory_funds = fixtures::wal(sc.ctx());
    let before = mallory_funds.value();
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&mut wsys, &mut config, &mut mallory_funds, SET);

    assert!(config.cycle_limit().borrow() == CYCLES - 1, 0);
    assert!(mallory_funds.value() < before, 1);

    sc.next_tx(ALICE);
    let blobs = blob_config::unwrap(config, sc.ctx());
    blobs.do_ref!(|renewed| assert!(blob::storage(renewed).end_epoch() == SET, 2));

    destroy(blobs);
    destroy(mallory_funds);
    destroy(alice_funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    sc.end();
}
