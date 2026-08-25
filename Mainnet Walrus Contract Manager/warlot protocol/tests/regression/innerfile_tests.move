/// The fallback is what makes a delegated write reversible. A file starts with
/// none, so the first call to record one has nothing to displace ,  and the
/// sequence the protocol exists to survive is: delegate, get overwritten,
/// revoke, roll back.
#[test_only]
module warlot::innerfile_tests;

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use warlot::{
    entry_innerfile,
    entry_permission,
    file_data,
    fixtures,
    inner_file::{Self, InnerFile},
    system_config::{Self, SystemConfig},
    writer_pass::WriterPass,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

/// The timestamp a delegated pass in these tests decays at.
const PASS_EXPIRY_MS: u64 = 5_000;

// === Test-only helpers ===

#[test]
fun root_change_can_be_set() {
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

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let mut owner_pass = sc.take_from_sender<WriterPass>();
    let head = file_data::blob_config_id(vector::borrow(file.track_back(), 0));

    assert!(!file.has_root_change(), 0);

    entry_innerfile::set_root_change(&mut file, &mut owner_pass, b"first", head, &clk, sc.ctx());

    assert!(file.has_root_change(), 1);
    assert!(file_data::commit(file.root_change()) == b"first", 2);

    // And the second call takes the swap branch rather than the fill branch.
    entry_innerfile::set_root_change(&mut file, &mut owner_pass, b"second", head, &clk, sc.ctx());

    assert!(file_data::commit(file.root_change()) == b"second", 3);

    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun recovery_sequence() {
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

    // The state Alice will come back to.
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let mut owner_pass = sc.take_from_sender<WriterPass>();
    let known_good = file_data::blob_config_id(vector::borrow(file.track_back(), 0));

    // Alice delegates to Bob: the account bit that lets him store under her
    // address, and a pass that lets him skip the draft queue.
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, sc.ctx());
    entry_innerfile::create_pass(&file, BOB, PASS_EXPIRY_MS, true, sc.ctx());

    // Bob is compromised and writes straight into the history.
    sc.next_tx(BOB);
    let mut bob_pass = sc.take_from_sender<WriterPass>();
    let bob_pass_id = object::id(&bob_pass);
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
        false,
        0,
        false,
        &clk,
        &sys,
        vector[raw_blob],
        b"unreviewed rewrite",
        sc.ctx(),
    );

    assert!(file_data::commit_by(vector::borrow(file.track_back(), 0)) == BOB, 0);

    // Alice takes both delegations back. The pass object never leaves Bob's
    // account; the record on the file is what stops it being accepted.
    sc.next_tx(ALICE);
    entry_innerfile::revoke_pass(&mut file, bob_pass_id, sc.ctx());
    entry_permission::revoke(&mut sys, ALICE, BOB, sc.ctx());

    assert!(file.is_pass_revoked(bob_pass_id), 1);

    // And she names the revision she does accept.
    entry_innerfile::set_root_change(
        &mut file,
        &mut owner_pass,
        b"first",
        known_good,
        &clk,
        sc.ctx(),
    );

    assert!(file.has_root_change(), 2);
    assert!(file_data::commit(file.root_change()) == b"first", 3);
    assert!(file_data::blob_config_id(file.root_change()) == known_good, 4);

    destroy(bob_pass);
    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}
