/// A renewal cycle is spent only once an extension has actually happened, so a call
/// that does no work leaves the mandate exactly as it found it. What bounds a
/// caller is *when* the cycle is charged, not *who* they are: renewal stays open to
/// any address, which `an_unrelated_address_renews_another_users_blobs` pins.
///
/// A mandate also comes in two kinds, and the last two tests here are about the
/// second. `none` is *renew this for as long as it is paid for*, and it is a
/// different statement from any count, however large ,  `some(0)` already means
/// *store this and never renew it*, so a number was never able to say "no limit".
/// The mode reaches the chain through the file's own term, which is why it is
/// tested from the entry point down rather than on a config built directly.
#[test_only]
module warlot::cycle_drain_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, coin, test_scenario as ts};
use wal::wal::WAL;
use walrus::blob;
use warlot::{
    blob_config::{Self, BlobConfig},
    entry_file_create,
    entry_file_write,
    entry_register,
    entry_renew,
    file_data,
    fixtures,
    inner_file::InnerFile,
    system_config::{Self, SystemConfig},
    writer_pass::WriterPass,
};

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
fun a_zero_term_is_refused() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    // Built directly, because the upload path refuses a term the system does not
    // sell and zero is not one of them. The guard below is what stands behind that.
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        0,
        option::some(CYCLES),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(MALLORY);
    let mut zero = coin::zero<WAL>(sc.ctx());
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut zero, sc.ctx());

    destroy(config);
    destroy(zero);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun a_renewal_that_does_no_work_spends_no_cycle() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    // The blob is already paid past the horizon, so there is nothing to extend.
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
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
        entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut zero, sc.ctx());
        i = i + 1;
    };

    let cycles = CYCLES;
    assert!(config.cycle_limit().borrow() == cycles, 0);
    assert!(zero.value() == 0, 1);

    ts::return_shared(config);
    destroy(zero);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun an_exhausted_mandate_renews_nothing_and_aborts_nothing() {
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
        option::some(0),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(MALLORY);
    let mut zero = coin::zero<WAL>(sc.ctx());
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut zero, sc.ctx());

    assert!(config.cycle_limit().borrow() == 0, 0);
    assert!(zero.value() == 0, 1);

    sc.next_tx(ALICE);
    let blobs = blob_config::unwrap(config, object::id(&sys), sc.ctx());
    blobs.do_ref!(|held| assert!(blob::storage(held).end_epoch() == SHORT_EPOCHS, 2));

    destroy(blobs);
    destroy(zero);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun an_unrelated_address_renews_another_users_blobs() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut alice_funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
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

    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut mallory_funds, sc.ctx());

    assert!(config.cycle_limit().borrow() == CYCLES - 1, 0);
    assert!(mallory_funds.value() < before, 1);

    sc.next_tx(ALICE);
    let blobs = blob_config::unwrap(config, object::id(&sys), sc.ctx());
    blobs.do_ref!(|renewed| assert!(blob::storage(renewed).end_epoch() == SET, 2));

    destroy(blobs);
    destroy(mallory_funds);
    destroy(alice_funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun an_indefinite_mandate_renews_without_draining() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    let first = fixtures::certified_blob(&mut wsys, fixtures::blob_size(), SHORT_EPOCHS, &mut funds, sc.ctx());

    // Through the entry point, with no limit. This is the whole finding: the mode
    // existed and was honoured everywhere below, and nothing outside the package
    // could ask for it.
    let file_id = entry_file_create::create_file(
        &sys,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[first],
        SET,
        option::none(),
        &clk,
        fixtures::commit_for(b"for as long as it is paid for"),
        1,
        true,
        true,
        true,
        false,
        0,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let owner_pass = sc.take_from_sender<WriterPass>();
    assert!(file.cycle_end().is_none(), 0);

    let head = file_data::blob_config_id(vector::borrow(file.track_back(), 0));
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, head);
    assert!(config.cycle_limit().is_none(), 1);

    // A renewal that does real work ,  the blob is short of the term ,  and the
    // mandate is exactly where it started afterwards.
    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut funds, sc.ctx());
    assert!(config.cycle_limit().is_none(), 2);

    // ATTEMPTS more, so a per-call leak of one cycle could not hide. A counted
    // mandate would have been spent long before this returns.
    ATTEMPTS.do!(|_| entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut funds, sc.ctx()));
    assert!(config.cycle_limit().is_none(), 3);

    // And the file carries the mode forward: a revision written later is bought on
    // the same indefinite mandate, because the term is the file's own.
    sc.next_tx(ALICE);
    let next = fixtures::certified_blob(&mut wsys, fixtures::blob_size(), SHORT_EPOCHS, &mut funds, sc.ctx());
    entry_file_write::write_(
        &mut file,
        &owner_pass,
        false,
        option::none(),
        &clk,
        &sys,
        vector[next],
        fixtures::commit_for(b"second"),
        vector[],
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let new_head = file_data::blob_config_id(vector::borrow(file.track_back(), 0));
    let new_config = ts::take_shared_by_id<BlobConfig>(&sc, new_head);
    assert!(new_config.cycle_limit().is_none(), 4);

    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(new_config);
    ts::return_shared(config);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}
