/// A pass is a delegation of authorship, not a login, so it ends three ways: it
/// runs out, the address holding it is denied, or the pass itself is revoked. A
/// pass the system does not decay is exempt from the first and from neither of
/// the others.
#[test_only]
module warlot::writer_pass_tests;

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use warlot::{
    entry_innerfile,
    entry_permission,
    entry_register,
    fixtures,
    inner_file::{Self, InnerFile},
    system_config::{Self, SystemConfig},
    writer_pass::{Self, WriterPass},
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

/// The timestamp a delegated pass in these tests decays at.
const PASS_EXPIRY_MS: u64 = 5_000;

/// A moment after `PASS_EXPIRY_MS`.
const PAST_EXPIRY_MS: u64 = 6_000;

/// Deny indefinitely.
const FOREVER: u64 = 0;

// === Test-only helpers ===

#[test]
#[expected_failure(abort_code = warlot::inner_file::DECAYEXCEEDED)]
fun expires() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let file_id = fixtures::inner_file(
        &mut wsys,
        &mut sys,
        ALICE,
        b"alice",
        b"first",
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_innerfile::create_pass(&file, BOB, PASS_EXPIRY_MS, false, sc.ctx());

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();

    // Nobody has denied Bob and nobody has revoked the pass. The clock alone
    // ends it.
    clk.set_for_testing(PAST_EXPIRY_MS);
    inner_file::verify_pass(&file, BOB, &bob_pass, &clk);

    destroy(bob_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::INVALIDWRITER)]
fun immortal_is_deniable() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let file_id = fixtures::inner_file(
        &mut wsys,
        &mut sys,
        ALICE,
        b"alice",
        b"first",
        &mut funds,
        &clk,
        sc.ctx(),
    );

    // A pass the system does not decay, held by an address the owner then denies.
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_innerfile::create_pass(&file, BOB, writer_pass::immortal_duration(), false, sc.ctx());
    entry_innerfile::deny_writer(&mut file, BOB, FOREVER, &clk, sc.ctx());

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    assert!(bob_pass.is_immortal(), 0);

    inner_file::verify_pass(&file, BOB, &bob_pass, &clk);

    destroy(bob_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::EPassRevoked)]
fun revoked_pass_refused() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let file_id = fixtures::inner_file(
        &mut wsys,
        &mut sys,
        ALICE,
        b"alice",
        b"first",
        &mut funds,
        &clk,
        sc.ctx(),
    );

    // A draft's blobs stay with the writer who pushed them, so Bob needs an
    // account of his own to push one.
    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_innerfile::create_pass(&file, BOB, PASS_EXPIRY_MS, false, sc.ctx());

    sc.next_tx(BOB);
    let mut bob_pass = sc.take_from_sender<WriterPass>();
    let bob_pass_id = object::id(&bob_pass);

    // The pass is still in Bob's account, and stays there. The record on the
    // file is the whole of the revocation.
    sc.next_tx(ALICE);
    entry_innerfile::revoke_pass(&mut file, bob_pass_id, sc.ctx());
    assert!(file.is_pass_revoked(bob_pass_id), 0);

    sc.next_tx(BOB);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_innerfile::write_(
        &mut file,
        &mut bob_pass,
        true,
        0,
        false,
        &clk,
        &sys,
        vector[raw_blob],
        b"a change the owner never accepted",
        sc.ctx(),
    );

    destroy(bob_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun delegated_pass_has_duration() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, true, false, false, sc.ctx());

    // Bob creates the file on Alice's behalf and keeps a pass to it.
    sc.next_tx(BOB);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_innerfile::create_file(
        &sys,
        ALICE,
        5,
        3,
        vector[raw_blob],
        fixtures::file_epoch_set(),
        fixtures::file_cycles(),
        &clk,
        b"first",
        1,
        true,
        PASS_EXPIRY_MS,
        sc.ctx(),
    );

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    assert!(!bob_pass.is_immortal(), 0);
    assert!(bob_pass.duration() == PASS_EXPIRY_MS, 1);

    destroy(bob_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::entry_innerfile::EInvalidPassDuration)]
fun a_delegated_pass_cannot_be_immortal() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, true, false, false, sc.ctx());

    sc.next_tx(BOB);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_innerfile::create_file(
        &sys,
        ALICE,
        5,
        3,
        vector[raw_blob],
        fixtures::file_epoch_set(),
        fixtures::file_cycles(),
        &clk,
        b"first",
        1,
        true,
        writer_pass::immortal_duration(),
        sc.ctx(),
    );

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
