/// A pass is a delegation of authorship, not a login, so it ends three ways: it
/// runs out, the address holding it is denied, or the pass itself is revoked. A
/// pass the system does not decay is exempt from the first and from neither of
/// the others.
///
/// An **admin** pass also cannot be minted on its own. A pass that writes
/// straight into a file's history never sufficed by itself ,  the store
/// underneath it checks `add_blob` too ,  and the mint said nothing about that,
/// so the pass granted strictly less than it appeared to. The last three tests
/// pin the refusal that closed it, and its edge: a **draft-only** pass is refused
/// nothing, because a queued write is custodied by whoever pushed it and stores
/// under their own address, where no grant on the owner's account is read at all.
#[test_only]
module warlot::writer_pass_tests;

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use warlot::{
    entry_file_access,
    entry_file_create,
    entry_file_write,
    entry_permission,
    entry_register,
    fixtures,
    inner_file::{Self, InnerFile},
    permission,
    system_config::{Self, SystemConfig},
    user,
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
        fixtures::commit_for(b"first"),
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, sc.ctx());

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
        fixtures::commit_for(b"first"),
        &mut funds,
        &clk,
        sc.ctx(),
    );

    // A pass the system does not decay, held by an address the owner then denies.
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_file_access::create_pass(
        &sys,
        &file,
        BOB,
        writer_pass::immortal_duration(),
        false,
        sc.ctx(),
    );
    entry_file_access::deny_writer(&sys, &mut file, BOB, FOREVER, &clk, sc.ctx());

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
        fixtures::commit_for(b"first"),
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
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, sc.ctx());

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    let bob_pass_id = object::id(&bob_pass);

    // The pass is still in Bob's account, and stays there. The record on the
    // file is the whole of the revocation.
    sc.next_tx(ALICE);
    entry_file_access::revoke_pass(&sys, &mut file, bob_pass_id, sc.ctx());
    assert!(file.is_pass_revoked(bob_pass_id), 0);

    sc.next_tx(BOB);
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
        fixtures::commit_for(b"a change the owner never accepted"),
        vector[],
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
    entry_file_create::create_file(
        &sys,
        ALICE,
        5,
        3,
        vector[raw_blob],
        fixtures::file_epoch_set(),
        fixtures::file_cycles(),
        &clk,
        fixtures::commit_for(b"first"),
        1,
        true,
        true,
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
#[expected_failure(abort_code = warlot::creation::EInvalidPassDuration)]
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
    entry_file_create::create_file(
        &sys,
        ALICE,
        5,
        3,
        vector[raw_blob],
        fixtures::file_epoch_set(),
        fixtures::file_cycles(),
        &clk,
        fixtures::commit_for(b"first"),
        1,
        true,
        true,
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

#[test]
#[expected_failure(abort_code = warlot::entry_file_access::ENoAddBlobGrant)]
fun a_pass_cannot_be_minted_to_an_address_that_cannot_store() {
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

    // Bob holds nothing on Alice's account. The pass would mint, and then fail at
    // its first write with an error naming a grant nobody mentioned at the mint.
    sc.next_tx(ALICE);
    let file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, true, sc.ctx());

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun a_granted_recipient_gets_a_pass_and_can_use_it() {
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

    // The order the refusal makes load-bearing: grant, then mint.
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, sc.ctx());
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, true, sc.ctx());

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    let revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );

    // And the pass now grants what it appears to: the write lands.
    entry_file_write::write_(
        &mut file,
        &bob_pass,
        false,
        option::none(),
        &clk,
        &sys,
        vector[revision],
        fixtures::commit_for(b"second"),
        vector[],
        sc.ctx(),
    );

    assert!(file.track_back().length() == 2, 0);

    destroy(bob_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
/// A draft-only pass needs no grant on the owner's account, and the write it
/// authorises lands.
///
/// The refusal above is conditional for a reason that is visible here: Bob stores
/// the draft's blobs under *his own* address, so the only account whose
/// permissions are consulted is his. Requiring Alice to grant him `add_blob`
/// would give him authority to store under hers, which is strictly more than this
/// pass can use and the opposite of what coupling the two was for.
fun a_draft_only_pass_needs_no_grant() {
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

    // Bob's own account, because a draft's blobs stay with the writer who pushed
    // them. Nothing is granted to him on Alice's.
    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, sc.ctx());

    assert!(!permission::has_delegate(user::get_user(&sys, ALICE).uid(), BOB), 0);

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    let proposed = fixtures::certified_blob(
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
        vector[proposed],
        fixtures::commit_for(b"a proposal"),
        vector[],
        sc.ctx(),
    );

    // The draft landed, and the file's own history is untouched until Alice
    // merges it.
    assert!(file.has_draft_queue(), 1);
    assert!(file.track_back().length() == 1, 2);

    destroy(bob_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}
