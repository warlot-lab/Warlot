/// The one invariant the project record exists to hold: a project names one
/// database, and having named it cannot name another.
///
/// The record it lives on was rebuilt in this scope ,  keyed by a minted id
/// rather than by a name, and stripped of the name, description, timestamps and
/// counters no contract function read. The invariant is the thing in that
/// migration most easily lost by accident, so it is asserted here rather than
/// assumed to have come across.
///
/// Every world below is built the way a client builds one, through
/// `entry_file_project`. The holder used to be minted here by a package call no
/// client can make, which is how a product domain that nothing on chain could
/// reach passed a suite this size.
#[test_only]
module warlot::db_inner_file_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, event, test_scenario as ts};
use walrus::system::System;
use wal::wal::WAL;
use sui::coin::Coin;
use warlot::{
    entry_file_project,
    entry_register,
    file_set,
    fixtures,
    product_events::{Self, ProjectCreated, ProjectDatabaseInitialised, ProjectFileSetRootChanged},
    project_object::{Self, ProjectHolder},
    system_config::{Self, SystemConfig},
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

const CYCLES: u64 = 2;
const DRAFT_EPOCHS: u32 = 1;

/// A well-formed root that is not the empty one.
const A_ROOT: vector<u8> = x"f54b57602bd89af3a5e9271c664b77641b176665c51d604e277e1a85e62ae60b";

// === Tests ===

#[test]
#[expected_failure(abort_code = warlot::project_object::DBEXIST)]
fun still_unique() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, mut wsys, mut funds, clk) = world(&mut sc);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    sc.next_tx(ALICE);
    init_db(&mut holder, project_id, &sys, &mut wsys, &mut funds, &clk, &mut sc);

    // The second database is refused by name, on a record that no longer carries
    // the project's name at all.
    sc.next_tx(ALICE);
    init_db(&mut holder, project_id, &sys, &mut wsys, &mut funds, &clk, &mut sc);

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
fun the_first_database_is_recorded() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, mut wsys, mut funds, clk) = world(&mut sc);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    assert!(project_object::has_project(&holder, project_id), 0);
    assert!(project_object::db_inner_file(&holder, project_id).is_none(), 1);

    sc.next_tx(ALICE);
    init_db(&mut holder, project_id, &sys, &mut wsys, &mut funds, &clk, &mut sc);

    let named = project_object::db_inner_file(&holder, project_id);
    assert!(named.is_some(), 2);

    // The stream names the same file, so a reader that never sees the object
    // knows which inner file the project answers to.
    let announced = event::events_by_type<ProjectDatabaseInitialised>();
    assert!(announced.length() == 1, 3);
    let (holder_id, announced_project, inner_file_id, initialised_by) =
        product_events::read_project_database_initialised(&announced[0]);
    assert!(holder_id == object::id(&holder), 4);
    assert!(announced_project == project_id, 5);
    assert!(inner_file_id == named.destroy_some(), 6);
    assert!(initialised_by == ALICE, 7);

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::project_object::ENoSuchProject)]
fun a_database_needs_a_project_to_belong_to() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, mut wsys, mut funds, clk) = world(&mut sc);

    // Under the previous shape a project was addressed by a name the caller
    // typed, so a miss and a project were the same lookup. It is a minted id now
    // and a miss aborts.
    sc.next_tx(ALICE);
    init_db(
        &mut holder,
        object::id_from_address(@0xDEAD),
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut sc,
    );

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
fun projects_are_keyed_by_a_minted_id() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, wsys, funds, clk) = world(&mut sc);

    let first = entry_file_project::create_project(&mut holder, &sys, sc.ctx());
    let second = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    // Two projects, no names, and nothing to collide. Under a name key the second
    // would have had to be called something else.
    assert!(first != second, 0);
    assert!(project_object::has_project(&holder, first), 1);
    assert!(project_object::has_project(&holder, second), 2);

    // The id is minted on chain and carried by nothing else, so the announcement
    // is the only way a reader learns it exists.
    let announced = event::events_by_type<ProjectCreated>();
    assert!(announced.length() == 2, 3);
    let (_holder_id, announced_first, created_by, opening_root) =
        product_events::read_project_created(&announced[0]);
    assert!(announced_first == first, 4);
    assert!(created_by == ALICE, 5);
    assert!(opening_root == file_set::empty_root(), 6);

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
fun a_stranger_cannot_create_a_project() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, wsys, funds, clk) = world(&mut sc);

    sc.next_tx(BOB);
    entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::project_object::INVALIDACCESS)]
fun the_record_refuses_a_holder_that_is_not_the_accounts() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, wsys, funds, clk) = world(&mut sc);

    // The entry layer establishes which account a caller acts for and hands that
    // address down; this is the record's own check that the holder it was given
    // is that account's. No published path can reach it, which is the point ,  it
    // is what a future entry point that forgot the first check would hit.
    project_object::create_project(&mut holder, BOB, sc.ctx());

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
fun the_commitment_opens_empty_and_every_move_is_announced() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, wsys, funds, clk) = world(&mut sc);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    // A project with no files commits to the empty set rather than to nothing.
    assert!(project_object::file_set_root(&holder, project_id) == file_set::empty_root(), 0);

    sc.next_tx(ALICE);
    entry_file_project::set_file_set_root(&mut holder, project_id, A_ROOT, &sys, sc.ctx());

    assert!(project_object::file_set_root(&holder, project_id) == A_ROOT, 1);

    let announced = event::events_by_type<ProjectFileSetRootChanged>();
    assert!(announced.length() == 1, 2);
    let (_holder_id, announced_project, root, previous_root, changed_by) =
        product_events::read_project_file_set_root_changed(&announced[0]);
    assert!(announced_project == project_id, 3);
    assert!(root == A_ROOT, 4);
    assert!(previous_root == file_set::empty_root(), 5);
    assert!(changed_by == ALICE, 6);

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EInvalidRootLength)]
fun the_commitment_refuses_the_wrong_width() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, wsys, funds, clk) = world(&mut sc);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    sc.next_tx(ALICE);
    entry_file_project::set_file_set_root(&mut holder, project_id, x"0011", &sys, sc.ctx());

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
fun a_stranger_cannot_move_the_commitment() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut holder, wsys, funds, clk) = world(&mut sc);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    // The root is the whole of what the chain says about a naming layer living
    // off chain, so whoever can move it decides what the names resolve to.
    sc.next_tx(BOB);
    entry_file_project::set_file_set_root(&mut holder, project_id, A_ROOT, &sys, sc.ctx());

    finish(sys, holder, wsys, funds, clk, sc);
}

// === Private functions ===

/// A registered Alice, the holder she opened, and the Walrus side a file needs.
fun world(sc: &mut ts::Scenario): (SystemConfig, ProjectHolder, System, Coin<WAL>, clock::Clock) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    entry_file_project::open_project_holder(&mut sys, sc.ctx());

    sc.next_tx(ALICE);
    let holder = sc.take_shared<ProjectHolder>();

    (sys, holder, wsys, funds, clk)
}

/// Create a file through the real entry point and name it as the project's database.
fun init_db(
    holder: &mut ProjectHolder,
    project_id: ID,
    sys: &SystemConfig,
    wsys: &mut System,
    funds: &mut Coin<WAL>,
    clk: &clock::Clock,
    sc: &mut ts::Scenario,
) {
    let raw_blob = fixtures::certified_blob(
        wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        funds,
        sc.ctx(),
    );

    entry_file_project::initialize_project_file(
        holder,
        project_id,
        sys,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[raw_blob],
        fixtures::file_epoch_set(),
        option::some(CYCLES),
        clk,
        fixtures::commit_for(b"the database"),
        DRAFT_EPOCHS,
        true,
        true,
        true,
        false,
        0,
        sc.ctx(),
    );
}

fun finish(
    sys: SystemConfig,
    holder: ProjectHolder,
    wsys: System,
    funds: Coin<WAL>,
    clk: clock::Clock,
    sc: ts::Scenario,
) {
    destroy(wsys);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(holder);
    ts::return_shared(sys);
    sc.end();
}
