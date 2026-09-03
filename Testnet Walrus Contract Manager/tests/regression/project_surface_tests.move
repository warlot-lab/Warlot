/// The product domain, reached the way a client reaches it.
///
/// Until this scope no `ProjectHolder` could exist on a published package.
/// `create_project_holder` was `public(package)` with no call site in `sources/`,
/// so every function below it ,  project creation, database initialisation, the
/// file-set root ,  was dead code on chain. Three things hid it: the static
/// checks verify that every emitter has a caller and `emit_project_holder_created`
/// had one, in the orphan itself; the two project test files minted their holder
/// by calling the package function directly; and the compiler raises no unused
/// warning for `public(package)`.
///
/// So the rule for this file is that no test in it may call a `public(package)`
/// function. Everything is reached through `entry_*`, which is the only surface a
/// client has. A future change that severs the entry layer from the product
/// domain fails here rather than shipping.
#[test_only]
module warlot::project_surface_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock::{Self, Clock}, coin::Coin, test_scenario as ts};
use wal::wal::WAL;
use walrus::system::System;
use warlot::{
    admin_cap::AdminCap,
    entry_admin,
    entry_file_project,
    entry_permission,
    entry_register,
    file_set,
    fixtures,
    project_object::{Self, ProjectHolder},
    system_config::{Self, SystemConfig},
    user,
};

// === Constants ===

const ADMIN: address = @0xADA;
const ALICE: address = @0xA11CE;
/// The wallet the backend signs with.
const BACKEND: address = @0xB4CE;

const CYCLES: u64 = 2;
const DRAFT_EPOCHS: u32 = 1;

/// Where the clock sits while the operator slot is live.
const NOW_MS: u64 = 1_000;
/// When that slot stops being accepted.
const OPERATOR_UNTIL_MS: u64 = 10_000;

/// A well-formed root that is not the empty one.
const A_ROOT: vector<u8> = x"f54b57602bd89af3a5e9271c664b77641b176665c51d604e277e1a85e62ae60b";

// === The whole surface, through published entry points only ===

#[test]
fun a_client_reaches_the_whole_project_surface() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut holder, mut wsys, mut funds, clk) = stage(&mut sc);

    sc.next_tx(ALICE);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());
    assert!(project_object::has_project(&holder, project_id), 0);
    assert!(project_object::file_set_root(&holder, project_id) == file_set::empty_root(), 1);

    sc.next_tx(ALICE);
    init_db(&mut holder, project_id, &sys, &mut wsys, &mut funds, &clk, &mut sc);
    assert!(project_object::db_inner_file(&holder, project_id).is_some(), 2);

    sc.next_tx(ALICE);
    entry_file_project::set_file_set_root(&mut holder, project_id, A_ROOT, &sys, sc.ctx());
    assert!(project_object::file_set_root(&holder, project_id) == A_ROOT, 3);

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
fun the_holder_is_recorded_against_the_account() {
    let mut sc = ts::begin(ADMIN);
    let (sys, holder, wsys, funds, clk) = stage(&mut sc);

    // Which holder is this account's, answered on chain. Without the marker a
    // client would have to scan `ProjectHolderCreated` to find out, and nothing
    // would stop a second holder from making the scan ambiguous.
    let alice = user::get_user(&sys, ALICE);
    assert!(user::has_project_holder(alice), 0);
    assert!(user::project_holder_id(alice) == object::id(&holder), 1);

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::user::EProjectHolderExists)]
fun a_second_holder_is_refused_by_name() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, holder, wsys, funds, clk) = stage(&mut sc);

    sc.next_tx(ALICE);
    entry_file_project::open_project_holder(&mut sys, sc.ctx());

    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::user::ENoProjectHolder)]
fun an_account_that_opened_none_has_none() {
    let mut sc = ts::begin(ADMIN);
    let (sys, holder, wsys, funds, clk) = stage(&mut sc);

    // The backend wallet is a registered account in its own right and has opened
    // no holder, so the question has no answer rather than a wrong one.
    let backend = user::get_user(&sys, BACKEND);
    assert!(!user::has_project_holder(backend), 0);
    user::project_holder_id(backend);

    finish(sys, holder, wsys, funds, clk, sc);
}

// === The operator paths, one bit at a time ===

#[test]
fun an_operator_holding_can_init_db_creates_a_project() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut holder, wsys, funds, clk) = stage(&mut sc);

    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    let project_id = entry_file_project::create_project_as_operator(
        &mut holder,
        &sys,
        &cap,
        &clk,
        sc.ctx(),
    );

    // Minted under Alice's holder on the operator's signature, and Alice is still
    // the only admin: the credential carries no ownership.
    assert!(project_object::has_project(&holder, project_id), 0);
    assert!(project_object::project_admin(&holder) == ALICE, 1);

    sc.return_to_sender(cap);
    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
fun an_operator_without_can_init_db_is_refused_a_project() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut holder, wsys, funds, clk) = stage(&mut sc);

    sc.next_tx(ALICE);
    entry_permission::replace_operator_role(
        &mut sys,
        ALICE,
        true,
        true,
        false,
        true,
        true,
        sc.ctx(),
    );

    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    entry_file_project::create_project_as_operator(&mut holder, &sys, &cap, &clk, sc.ctx());

    sc.return_to_sender(cap);
    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
fun an_operator_holding_can_set_root_moves_a_root() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut holder, wsys, funds, clk) = stage(&mut sc);

    sc.next_tx(ALICE);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    entry_file_project::set_file_set_root_as_operator(
        &mut holder,
        project_id,
        A_ROOT,
        &sys,
        &cap,
        &clk,
        sc.ctx(),
    );

    assert!(project_object::file_set_root(&holder, project_id) == A_ROOT, 0);

    sc.return_to_sender(cap);
    finish(sys, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
fun an_operator_without_can_set_root_is_refused_the_root() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut holder, wsys, funds, clk) = stage(&mut sc);

    sc.next_tx(ALICE);
    let project_id = entry_file_project::create_project(&mut holder, &sys, sc.ctx());

    // The root bit alone is withdrawn. Project creation stays granted, which is
    // what makes the refusal below attributable to this bit and not to a role
    // that stopped working.
    sc.next_tx(ALICE);
    entry_permission::replace_operator_role(
        &mut sys,
        ALICE,
        true,
        true,
        true,
        true,
        false,
        sc.ctx(),
    );

    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    entry_file_project::set_file_set_root_as_operator(
        &mut holder,
        project_id,
        A_ROOT,
        &sys,
        &cap,
        &clk,
        sc.ctx(),
    );

    sc.return_to_sender(cap);
    finish(sys, holder, wsys, funds, clk, sc);
}

// === Private functions ===

/// A system holding one live operator slot, a registered Alice who granted the
/// operator role and opened her holder, and the Walrus side a database needs.
fun stage(
    sc: &mut ts::Scenario,
): (SystemConfig, ProjectHolder, System, Coin<WAL>, Clock) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ADMIN);
    let wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ADMIN);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut clk = clock::create_for_testing(sc.ctx());
    let funds = fixtures::wal(sc.ctx());
    clk.set_for_testing(NOW_MS);

    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_admin(&sys, BACKEND, &cap, sc.ctx());

    sc.next_tx(BACKEND);
    let backend_cap = sc.take_from_sender<AdminCap>();
    let backend_cap_id = object::id(&backend_cap);
    sc.return_to_sender(backend_cap);

    sc.next_tx(ADMIN);
    entry_admin::enrol_operator(
        &mut sys,
        &cap,
        backend_cap_id,
        OPERATOR_UNTIL_MS,
        true,
        &clk,
        sc.ctx(),
    );
    sc.return_to_sender(cap);

    sc.next_tx(BACKEND);
    entry_register::all_register_user_publicly(&mut sys, b"backend".to_string(), &clk, sc.ctx());

    // Registering with system permission grants the operator role every bit it
    // can hold, `can_init_db` and `can_set_root` among them. The tests that need
    // one withdrawn withdraw it explicitly.
    sc.next_tx(ALICE);
    entry_register::all_register_user_with_system_permission(
        &mut sys,
        b"alice".to_string(),
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
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
    clk: &Clock,
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
        CYCLES,
        clk,
        fixtures::commit_for(b"the database"),
        DRAFT_EPOCHS,
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
    clk: Clock,
    sc: ts::Scenario,
) {
    destroy(wsys);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(holder);
    ts::return_shared(sys);
    sc.end();
}
