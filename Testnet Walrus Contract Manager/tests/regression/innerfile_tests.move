/// The fallback is what makes a delegated write reversible. A file starts with
/// none, so the first call to record one has nothing to displace ,  and the
/// sequence the protocol exists to survive is: delegate, get overwritten,
/// revoke, roll back.
///
/// The rollback window is finite, so writing past its depth pushes revisions out
/// of it. What leaves the window is content somebody is still paying for, so it
/// comes back to its owner rather than being dropped on the floor.
#[test_only]
module warlot::innerfile_tests;

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use walrus::blob::Blob;
use warlot::{
    blob_config::{Self, BlobConfig},
    entry_file_access,
    entry_file_draft,
    entry_file_fallback,
    entry_file_write,
    entry_permission,
    entry_register,
    file_data,
    fixtures,
    inner_file::InnerFile,
    system_config::{Self, SystemConfig},
    writer_pass::WriterPass,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

/// The timestamp a delegated pass in these tests decays at.
const PASS_EXPIRY_MS: u64 = 5_000;

/// How far past the rollback window's depth `no_leak` keeps writing.
const WRITES_PAST_THE_WINDOW: u64 = 5;

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
        fixtures::commit_for(b"first"),
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let owner_pass = sc.take_from_sender<WriterPass>();
    let head = file_data::blob_config_id(vector::borrow(file.track_back(), 0));
    let head_config = ts::take_shared_by_id<BlobConfig>(&sc, head);

    assert!(!file.has_root_change(), 0);

    entry_file_fallback::set_root_change(
        &sys,
        &mut file,
        &owner_pass,
        fixtures::commit_for(b"first"),
        &head_config,
        &clk,
        sc.ctx(),
    );

    assert!(file.has_root_change(), 1);
    assert!(file_data::commit(file.root_change()) == fixtures::commit_for(b"first"), 2);

    // And the second call takes the swap branch rather than the fill branch.
    entry_file_fallback::set_root_change(
        &sys,
        &mut file,
        &owner_pass,
        fixtures::commit_for(b"second"),
        &head_config,
        &clk,
        sc.ctx(),
    );

    assert!(file_data::commit(file.root_change()) == fixtures::commit_for(b"second"), 3);

    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(head_config);
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
        fixtures::commit_for(b"first"),
        &mut funds,
        &clk,
        sc.ctx(),
    );

    // The state Alice will come back to.
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let owner_pass = sc.take_from_sender<WriterPass>();
    let known_good = file_data::blob_config_id(vector::borrow(file.track_back(), 0));

    // Alice delegates to Bob: the account bit that lets him store under her
    // address, and a pass that lets him skip the draft queue.
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, false, sc.ctx());
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, true, sc.ctx());

    // Bob is compromised and writes straight into the history.
    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    let bob_pass_id = object::id(&bob_pass);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_file_write::write_(
        &mut file,
        &bob_pass,
        false,
        option::none(),
        &clk,
        &sys,
        vector[raw_blob],
        fixtures::commit_for(b"unreviewed rewrite"),
        vector[],
        sc.ctx(),
    );

    assert!(file_data::commit_by(vector::borrow(file.track_back(), 0)) == BOB, 0);

    // Alice takes both delegations back. The pass object never leaves Bob's
    // account; the record on the file is what stops it being accepted.
    sc.next_tx(ALICE);
    entry_file_access::revoke_pass(&sys, &mut file, bob_pass_id, sc.ctx());
    entry_permission::revoke(&mut sys, ALICE, BOB, sc.ctx());

    assert!(file.is_pass_revoked(bob_pass_id), 1);

    // And she names the revision she does accept.
    let known_good_config = ts::take_shared_by_id<BlobConfig>(&sc, known_good);
    entry_file_fallback::set_root_change(
        &sys,
        &mut file,
        &owner_pass,
        fixtures::commit_for(b"first"),
        &known_good_config,
        &clk,
        sc.ctx(),
    );

    assert!(file.has_root_change(), 2);
    assert!(file_data::commit(file.root_change()) == fixtures::commit_for(b"first"), 3);
    assert!(file_data::blob_config_id(file.root_change()) == known_good, 4);

    destroy(bob_pass);
    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(known_good_config);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun no_leak() {
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
        fixtures::commit_for(b"first"),
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let owner_pass = sc.take_from_sender<WriterPass>();

    let depth = fixtures::file_track_back() as u64;
    let writes = depth + WRITES_PAST_THE_WINDOW;

    let mut released = 0;
    let mut i = 0;
    while (i < writes) {
        sc.next_tx(ALICE);

        // Once the window is full every write pushes one revision out of it, and
        // the caller has to hand over the config that revision names. Which one
        // that is is not a guess: it is the last entry in the window.
        let window = file.track_back();
        let full = window.length() >= depth;
        let evicted = if (full) {
            let oldest = file_data::blob_config_id(vector::borrow(window, window.length() - 1));
            released = released + 1;
            vector[ts::take_shared_by_id<BlobConfig>(&sc, oldest)]
        } else {
            vector<BlobConfig>[]
        };

        let raw_blob = fixtures::certified_blob(
            &mut wsys,
            fixtures::blob_size(),
            fixtures::blob_epochs_ahead(),
            &mut funds,
            sc.ctx(),
        );

        entry_file_write::force_write_innerfile(
            &mut file,
            &owner_pass,
            &clk,
            &sys,
            vector[raw_blob],
            fixtures::commit_for(b"revision"),
            evicted,
            sc.ctx(),
        );

        i = i + 1;
    };

    // The window holds exactly its depth, however many writes went through it.
    assert!(file.track_back().length() == depth, 0);
    assert!(released == writes - (depth - 1), 1);

    // And every revision that left it came back to Alice as a blob she owns
    // outright, rather than staying in a config nothing references.
    sc.next_tx(ALICE);
    let returned = ts::ids_for_sender<Blob>(&sc);
    assert!(returned.length() == released, 2);
    returned.do_ref!(|id| destroy(ts::take_from_sender_by_id<Blob>(&sc, *id)));

    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun merge_reparents() {
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
        fixtures::commit_for(b"first"),
        &mut funds,
        &clk,
        sc.ctx(),
    );

    // Bob registers on his own account, because a draft's content is stored under
    // the writer who proposed it.
    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let owner_pass = sc.take_from_sender<WriterPass>();
    // Bob only ever drafts here, and a draft's content is stored under Bob, so
    // he does not need to be able to store under Alice to do it. `create_pass`
    // asks for the grant anyway: it refuses any pass minted to an address that
    // cannot store for the owner, without asking which half of the pass the
    // recipient means to use.
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, false, sc.ctx());
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, sc.ctx());

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_file_write::write_(
        &mut file,
        &bob_pass,
        true,
        option::none(),
        &clk,
        &sys,
        vector[raw_blob],
        fixtures::commit_for(b"a proposal"),
        vector[],
        sc.ctx(),
    );

    // The draft's content is Bob's while it is only a proposal.
    sc.next_tx(ALICE);
    let draft_config_id = ts::most_recent_id_shared<BlobConfig>().destroy_some();
    let mut draft_config = ts::take_shared_by_id<BlobConfig>(&sc, draft_config_id);
    assert!(blob_config::owner(&draft_config) == BOB, 0);

    entry_file_draft::merge_draft_into_file(
        &sys,
        &mut file,
        &owner_pass,
        &mut draft_config,
        0,
        true,
        vector[],
        &clk,
        sc.ctx(),
    );

    // Accepting it moves custody to the owner who accepted it, in the same call.
    assert!(blob_config::owner(&draft_config) == ALICE, 1);
    assert!(
        file_data::blob_config_id(vector::borrow(file.track_back(), 0)) == draft_config_id,
        2,
    );
    assert!(file_data::commit_by(vector::borrow(file.track_back(), 0)) == BOB, 3);

    destroy(bob_pass);
    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(draft_config);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}
