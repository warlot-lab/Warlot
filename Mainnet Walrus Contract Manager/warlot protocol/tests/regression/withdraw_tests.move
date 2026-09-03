/// Withdrawal consumes the shared config itself, so there is no bookkeeping to
/// repair and no path on which it can fail for the owner. A user holding several
/// configs takes every one of them back, and only that user can.
#[test_only]
module warlot::withdraw_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, event, test_scenario as ts};
use walrus::blob::Blob;
use warlot::{
    blob_config::BlobConfig,
    entry_register,
    entry_withdraw,
    fixtures,
    store,
    storage_events::BlobWithdrawn,
    system_config::{Self, SystemConfig},
};

// === Constants ===

const ALICE: address = @0xA11CE;
const MALLORY: address = @0xBAD;
const SET: u32 = 13;
const START_EPOCHS: u32 = 5;
const CYCLES: u64 = 2;
const CONFIG_COUNT: u64 = 3;
const BLOB_SIZE: u64 = 1_024;

// === Test-only helpers ===

#[test]
fun owner_withdraws_every_config() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    // Three separate stores through the real upload path.
    let mut ids = vector<ID>[];
    let mut i = 0;
    while (i < CONFIG_COUNT) {
        let raw_blob = fixtures::certified_blob(
            &mut wsys,
            BLOB_SIZE,
            START_EPOCHS,
            &mut funds,
            sc.ctx(),
        );
        let (config_id, _) = store::store_blob_internal(
            &sys,
            vector[raw_blob],
            SET,
            CYCLES,
            ALICE,
            option::none(),
            &clk,
            sc.ctx(),
        );
        ids.push_back(config_id);
        i = i + 1;
    };

    sc.next_tx(ALICE);
    ids.do_ref!(|id| {
        let config = ts::take_shared_by_id<BlobConfig>(&sc, *id);
        entry_withdraw::self_withdraw_blob(&sys, config, sc.ctx());
    });

    // Every blob is back in Alice's own account, owned outright.
    sc.next_tx(ALICE);
    let returned = ts::ids_for_sender<Blob>(&sc);
    assert!(returned.length() == CONFIG_COUNT, 0);
    returned.do_ref!(|id| destroy(ts::take_from_sender_by_id<Blob>(&sc, *id)));

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun the_batch_clears_every_config_in_one_call() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    let mut ids = vector<ID>[];
    let mut i = 0;
    while (i < CONFIG_COUNT) {
        let raw_blob = fixtures::certified_blob(
            &mut wsys,
            BLOB_SIZE,
            START_EPOCHS,
            &mut funds,
            sc.ctx(),
        );
        let (config_id, _) = store::store_blob_internal(
            &sys,
            vector[raw_blob],
            SET,
            CYCLES,
            ALICE,
            option::none(),
            &clk,
            sc.ctx(),
        );
        ids.push_back(config_id);
        i = i + 1;
    };

    // Every config is still named as a transaction input, so this saves the
    // per-call overhead rather than lifting the shared-object input limit.
    sc.next_tx(ALICE);
    let mut configs = vector<BlobConfig>[];
    ids.do_ref!(|id| configs.push_back(ts::take_shared_by_id<BlobConfig>(&sc, *id)));
    entry_withdraw::self_withdraw_blobs(&sys, configs, sc.ctx());

    // One withdrawal per config, not one for the call. A consumer replaying the
    // stream sees each row disappear separately, which is what it has to do to
    // keep a per-config table honest.
    let withdrawn = event::events_by_type<BlobWithdrawn>();
    assert!(withdrawn.length() == CONFIG_COUNT, 0);

    // Every config is gone from the shared pool, so nothing is left holding
    // custody of anything.
    assert!(!ts::has_most_recent_shared<BlobConfig>(), 1);

    sc.next_tx(ALICE);
    let returned = ts::ids_for_sender<Blob>(&sc);
    assert!(returned.length() == CONFIG_COUNT, 2);
    returned.do_ref!(|id| destroy(ts::take_from_sender_by_id<Blob>(&sc, *id)));

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENotOwner)]
fun a_stranger_cannot_withdraw() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        SET,
        option::some(CYCLES),
        START_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    // The config is shared, so Mallory can reach it; `owner` is what stops her.
    sc.next_tx(MALLORY);
    let config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_withdraw::self_withdraw_blob(&sys, config, sc.ctx());

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
