/// The number of drafts a file may hold open was declared on the file from the
/// beginning and enforced nowhere, so the draft queue was a structure any pass
/// holder could grow without limit. Clearing it walked every index the file had
/// ever issued, which meant a file with enough drafts could never clear them.
#[test_only]
module warlot::draft_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use warlot::{
    draft,
    entry_file_access,
    entry_file_draft,
    entry_file_write,
    entry_permission,
    entry_register,
    fixtures,
    inner_file::{Self, InnerFile},
    system_config::{Self, SystemConfig},
    writer_pass::WriterPass,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const PASS_EXPIRY_MS: u64 = 5_000;

// === Test-only helpers ===

#[test]
#[expected_failure(abort_code = warlot::inner_file::EDraftLimitReached)]
fun writers_length_enforced() {
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

    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let owner_pass = sc.take_from_sender<WriterPass>();
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, sc.ctx());
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, sc.ctx());

    sc.next_tx(BOB);
    let mut bob_pass = sc.take_from_sender<WriterPass>();

    // One draft past the cap the file declares.
    let cap = file.writers_length() as u64;
    let mut i = 0;
    while (i < cap + 1) {
        let raw_blob = fixtures::certified_blob(
            &mut wsys,
            fixtures::blob_size(),
            fixtures::blob_epochs_ahead(),
            &mut funds,
            sc.ctx(),
        );
        entry_file_write::write_(
            &mut file,
            &mut bob_pass,
            true,
            option::none(),
            &clk,
            &sys,
            vector[raw_blob],
            fixtures::commit_for(b"a proposal"),
            vector[],
            sc.ctx(),
        );
        i = i + 1;
    };

    destroy(bob_pass);
    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun clearing_takes_a_range_and_leaves_the_rest() {
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
    let mut owner_pass = sc.take_from_sender<WriterPass>();

    // Three drafts from the owner's own pass, which needs no delegation.
    let mut i = 0u64;
    while (i < 3) {
        let raw_blob = fixtures::certified_blob(
            &mut wsys,
            fixtures::blob_size(),
            fixtures::blob_epochs_ahead(),
            &mut funds,
            sc.ctx(),
        );
        entry_file_write::write_(
            &mut file,
            &mut owner_pass,
            true,
            option::none(),
            &clk,
            &sys,
            vector[raw_blob],
            fixtures::commit_for(b"a proposal"),
            vector[],
            sc.ctx(),
        );
        i = i + 1;
    };

    assert!(draft::total_draft(inner_file::get_draft_holder(&mut file)) == 3, 0);

    // A range clears what it names and nothing else.
    entry_file_draft::clear_drafts(&sys, &mut file, &mut owner_pass, 0, 2, &clk, sc.ctx());

    assert!(draft::total_draft(inner_file::get_draft_holder(&mut file)) == 1, 1);

    // The index only ever moves forward, so the draft that survived keeps its own.
    assert!(draft::available_index(inner_file::get_draft_holder(&mut file)) == 3, 2);

    entry_file_draft::clear_drafts(&sys, &mut file, &mut owner_pass, 2, 3, &clk, sc.ctx());

    assert!(draft::total_draft(inner_file::get_draft_holder(&mut file)) == 0, 3);

    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}
