/// A file's storage term is chosen once, at creation, and there is no setter for
/// it. The tier table it was chosen from is configuration, and an admin may retune
/// it at any time.
///
/// While every store re-validated the term against the live table, those two facts
/// together meant that dropping a term from the table permanently froze every
/// existing file bought on it: the owner could not write, and could not move the
/// file to a term still sold. The remedy was for the admin to put the term back,
/// and nothing in the protocol said which files a retune had just frozen.
///
/// Validation now happens where a term is *bought* ,  file creation and adoption ,
/// and not where a mandate already sold is continued. These pin both directions of
/// that, because either half failing alone is a defect: a write that is refused is
/// the bug that was fixed, and a purchase that is allowed on a term the system no
/// longer sells is the check having gone missing.
#[test_only]
module warlot::tier_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use warlot::{
    admin_cap::AdminCap,
    blob_config::BlobConfig,
    entry_admin,
    entry_file_create,
    entry_file_write,
    entry_renew,
    entry_upload,
    file_data,
    fixtures,
    inner_file::InnerFile,
    system_config::{Self, SystemConfig},
    tier,
    writer_pass::WriterPass
};

// === Constants ===

const ALICE: address = @0xA11CE;

/// The term the fixture file is bought on, and a term the default ladder sells.
const SOLD: u32 = 13;

/// The same ladder with `SOLD` taken out of it.
const RETUNED: vector<u32> = vector[1, 2, 7, 20, 26, 52];
const HORIZON: u32 = 53;

/// A term above the retuned ladder's top, which no version of the table has sold.
const UNSOLD: u32 = 100;

const CYCLES: u64 = 2;

// === Tests ===

#[test]
fun a_dropped_term_freezes_no_file() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut admin_cap = sc.take_from_sender<AdminCap>();
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

    // The admin retunes the ladder out from under a file that is already on it.
    entry_admin::update_tier_table(&mut admin_cap, &mut sys, RETUNED, HORIZON, sc.ctx());
    let dropped = SOLD;
    assert!(!sys.tier_table().contains(&dropped), 0);

    // The owner can still write. This is the whole finding: before the fix this
    // aborted `EInvalidTier`, permanently, with no action available to them.
    sc.next_tx(ALICE);
    let revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );

    entry_file_write::write_(
        &mut file,
        &owner_pass,
        false,
        option::none(),
        &clk,
        &sys,
        vector[revision],
        fixtures::commit_for(b"written on a term nobody sells any more"),
        vector[],
        sc.ctx(),
    );

    // The write landed, rather than merely not aborting: the head is the revision
    // that was just written on the dropped term.
    sc.next_tx(ALICE);
    let head_entry = vector::borrow(file.track_back(), 0);
    assert!(
        file_data::commit(head_entry)
            == fixtures::commit_for(b"written on a term nobody sells any more"),
        1,
    );

    // And the content stays renewable, which is what bounds the blast radius: the
    // file went read-only at worst, never unreachable. Renewal never consulted the
    // tier table, and this is here so that a later change cannot quietly extend
    // the freeze to it.
    let head = file_data::blob_config_id(head_entry);
    let mut head_config = ts::take_shared_by_id<BlobConfig>(&sc, head);

    entry_renew::renew_blob(&sys, &mut wsys, &mut head_config, &mut funds, sc.ctx());

    destroy(owner_pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(head_config);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.return_to_sender(admin_cap);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::tier::EInvalidTier)]
fun a_dropped_term_refuses_a_new_file() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut admin_cap = sc.take_from_sender<AdminCap>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_admin::update_tier_table(&mut admin_cap, &mut sys, RETUNED, HORIZON, sc.ctx());

    // Creating a file buys a term, and a term the system does not sell is refused
    // by name at the moment of purchase.
    let blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );

    entry_file_create::create_file(
        &sys,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[blob],
        SOLD,
        option::some(CYCLES),
        &clk,
        fixtures::commit_for(b"bought on a term nobody sells"),
        1,
        true,
        true,
        true,
        false,
        0,
        sc.ctx(),
    );

    abort
}

#[test]
#[expected_failure(abort_code = warlot::tier::EInvalidTier)]
fun a_dropped_term_refuses_an_adoption() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut admin_cap = sc.take_from_sender<AdminCap>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_admin::update_tier_table(&mut admin_cap, &mut sys, RETUNED, HORIZON, sc.ctx());

    let blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );

    // The other buying funnel. One insertion covers both its entry points, and
    // this is the one that proves it covers this one.
    entry_upload::foreign_blob_add(
        &sys,
        ALICE,
        option::some(CYCLES),
        SOLD,
        vector[blob],
        &clk,
        sc.ctx(),
    );

    abort
}

#[test]
fun registration_term_answers_for_terms_the_table_does_not_sell() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut admin_cap = sc.take_from_sender<AdminCap>();

    let retuned = RETUNED;
    entry_admin::update_tier_table(&mut admin_cap, &mut sys, retuned, HORIZON, sc.ctx());
    assert!(!sys.tier_table().contains(&SOLD), 0);

    // The reserve for a revision its owner is still allowed to write. Validating
    // here refused to answer, which put the failure one step ahead of the write
    // the answer was meant to prepare, and left the freeze in place from the
    // caller's side even once the write itself was allowed.
    assert!(tier::registration_term(&sys, SOLD) == SOLD, 1);

    // A term the table has never sold is answered the same way. The margin belongs
    // to the live table's longest term, and an unsold term is not it on either
    // side of the ladder.
    assert!(tier::registration_term(&sys, UNSOLD) == UNSOLD, 2);

    // The margin is still read off the live table rather than a stale one, and it
    // still leaves the blob an epoch below the horizon.
    let top = retuned[retuned.length() - 1];
    assert!(tier::registration_term(&sys, top) == top + 1, 3);
    assert!(tier::registration_term(&sys, top) <= sys.max_epochs_ahead(), 4);

    ts::return_shared(sys);
    sc.return_to_sender(admin_cap);
    sc.end();
}
