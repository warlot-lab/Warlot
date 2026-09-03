/// The upgrade gate is the fence between a package and a system that has not been
/// raised to it yet. It is worth nothing unless it is on every way in, so every way
/// in is listed here and each one is asserted separately ,  a gate proven on a
/// helper is not a gate proven on the functions that were supposed to call it.
///
/// `migrate_version` is the one deliberate omission. It is the call that clears a
/// stale version, so gating it would leave a system that could never be repaired.
#[test_only]
module warlot::version_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock::{Self, Clock}, coin::Coin, test_scenario as ts};
use wal::wal::WAL;
use walrus::system::System;
use warlot::{
    admin_cap::AdminCap,
    blob_config::BlobConfig,
    entry_admin,
    entry_file_access,
    entry_file_create,
    entry_file_draft,
    entry_file_fallback,
    entry_file_project,
    entry_file_write,
    entry_permission,
    entry_register,
    entry_renew,
    entry_upload,
    entry_wallet,
    entry_withdraw,
    fixtures,
    inner_file::InnerFile,
    project_object::ProjectHolder,
    registry::Registry,
    system_config::{Self, SystemConfig},
    writer_pass::WriterPass,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const FEE: u64 = 100;
const AMOUNT: u64 = 1;
const CYCLES: u64 = 2;
const START_EPOCHS: u32 = 5;
const PASS_EXPIRY_MS: u64 = 5_000;

/// A version below the first the package was ever published at, which is what a
/// system looks like after the package has been upgraded past it and before the
/// admin has raised it.
const STALE_VERSION: u64 = 0;

// === Test-only helpers ===

/// A system and the capability that administers it, one version behind.
fun stale_admin(sc: &mut ts::Scenario): (SystemConfig, AdminCap, Coin<WAL>, Clock) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let cap = sc.take_from_sender<AdminCap>();
    let clk = clock::create_for_testing(sc.ctx());
    let funds = fixtures::wal(sc.ctx());

    system_config::set_version_for_testing(&mut sys, STALE_VERSION);

    (sys, cap, funds, clk)
}

fun finish_admin(sys: SystemConfig, cap: AdminCap, funds: Coin<WAL>, clk: Clock, sc: ts::Scenario) {
    destroy(cap);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

/// A registered account, the system it belongs to and the successor it could move
/// to, with the system one version behind.
fun stale_account(
    sc: &mut ts::Scenario,
): (SystemConfig, SystemConfig, AdminCap, Registry, Coin<WAL>, Clock) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut cap = sc.take_from_sender<AdminCap>();
    let clk = clock::create_for_testing(sc.ctx());
    let funds = fixtures::wal(sc.ctx());

    entry_admin::mint_system(&mut cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());
    let next_id = *sys.next_system().borrow();

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let next = ts::take_shared_by_id<SystemConfig>(sc, next_id);
    let registry = sc.take_from_sender<Registry>();

    system_config::set_version_for_testing(&mut sys, STALE_VERSION);

    (sys, next, cap, registry, funds, clk)
}

fun finish_account(
    sys: SystemConfig,
    next: SystemConfig,
    cap: AdminCap,
    registry: Registry,
    funds: Coin<WAL>,
    clk: Clock,
    sc: ts::Scenario,
) {
    destroy(cap);
    destroy(registry);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(next);
    ts::return_shared(sys);
    sc.end();
}

/// A published file, the pass that writes to it and a spare config, with the
/// system one version behind. Built while it is current, because none of these
/// objects can be created through a gate that is already closed.
fun file_world(
    sc: &mut ts::Scenario,
    stale: bool,
): (SystemConfig, InnerFile, WriterPass, BlobConfig, ProjectHolder, System, Coin<WAL>, Clock) {
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
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        fixtures::file_epoch_set(),
        option::some(CYCLES),
        START_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );
    entry_file_project::open_project_holder(&mut sys, sc.ctx());

    sc.next_tx(ALICE);
    let file = ts::take_shared_by_id<InnerFile>(sc, file_id);
    let config = ts::take_shared_by_id<BlobConfig>(sc, config_id);
    let pass = sc.take_from_sender<WriterPass>();
    let holder = sc.take_shared<ProjectHolder>();

    if (stale) {
        system_config::set_version_for_testing(&mut sys, STALE_VERSION);
    };

    (sys, file, pass, config, holder, wsys, funds, clk)
}

fun finish_file(
    sys: SystemConfig,
    file: InnerFile,
    pass: WriterPass,
    config: BlobConfig,
    holder: ProjectHolder,
    wsys: System,
    funds: Coin<WAL>,
    clk: Clock,
    sc: ts::Scenario,
) {
    destroy(pass);
    destroy(wsys);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(holder);
    ts::return_shared(config);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

// === The gate, per entry point ===

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_withdraw_system_wal() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::withdraw_system_wal(&mut sys, &mut cap, AMOUNT, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_withdraw_system_coin() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::withdraw_system_coin<WAL>(&mut sys, &mut cap, AMOUNT, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_add_coin_type() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::add_coin_type<WAL>(&mut cap, &mut sys);
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_remove_supported_coin() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::remove_supported_coin<WAL>(&mut cap, &mut sys);
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_mint_system() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::mint_system(&mut cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_update_cost() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::update_cost(&mut cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_update_tier_table() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::update_tier_table(&mut cap, &mut sys, vector[1, 2, 7], 53, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_mint_admin() {
    let mut sc = ts::begin(ALICE);
    let (sys, cap, funds, clk) = stale_admin(&mut sc);
    entry_admin::mint_admin(&sys, BOB, &cap, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_grant() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, cap, funds, clk) = stale_admin(&mut sc);
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, false, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_revoke() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, cap, funds, clk) = stale_admin(&mut sc);
    entry_permission::revoke(&mut sys, ALICE, BOB, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_all_register_user_publicly() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, cap, funds, clk) = stale_admin(&mut sc);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_all_register_user_with_system_permission() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, cap, funds, clk) = stale_admin(&mut sc);
    entry_register::all_register_user_with_system_permission(
        &mut sys,
        b"bob".to_string(),
        &clk,
        sc.ctx(),
    );
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_deposit_coin() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, cap, mut funds, clk) = stale_admin(&mut sc);
    let _ = entry_wallet::deposit_coin(&mut sys, &mut funds, AMOUNT, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_withdraw_wal() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, cap, funds, clk) = stale_admin(&mut sc);
    entry_wallet::withdraw_wal(&mut sys, AMOUNT, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_withdraw_all_wal() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, cap, funds, clk) = stale_admin(&mut sc);
    entry_wallet::withdraw_all_wal(&mut sys, sc.ctx());
    finish_admin(sys, cap, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_update_username() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, next, cap, mut registry, mut funds, clk) = stale_account(&mut sc);
    entry_register::update_username(
        &mut sys,
        &mut registry,
        b"renamed".to_string(),
        &mut funds,
        sc.ctx(),
    );
    finish_account(sys, next, cap, registry, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_migrate_system() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut next, cap, mut registry, mut funds, clk) = stale_account(&mut sc);
    entry_register::migrate_system(
        &mut registry,
        &mut sys,
        &mut next,
        &mut funds,
        &clk,
        sc.ctx(),
    );
    finish_account(sys, next, cap, registry, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_foreign_blob_add() {
    let mut sc = ts::begin(ALICE);
    let (sys, next, cap, registry, funds, clk) = stale_account(&mut sc);
    entry_upload::foreign_blob_add(
        &sys,
        ALICE,
        CYCLES,
        fixtures::file_epoch_set(),
        vector[],
        &clk,
        sc.ctx(),
    );
    finish_account(sys, next, cap, registry, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_create_file() {
    let mut sc = ts::begin(ALICE);
    let (sys, file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    let _ = entry_file_create::create_file(
        &sys,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[],
        fixtures::file_epoch_set(),
        CYCLES,
        &clk,
        fixtures::commit_for(b"blocked"),
        1,
        true,
        true,
        false,
        0,
        sc.ctx(),
    );
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_initialize_project_file() {
    let mut sc = ts::begin(ALICE);
    let (sys, file, pass, config, mut holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_project::initialize_project_file(
        &mut holder,
        object::id_from_address(@0x0),
        &sys,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[],
        fixtures::file_epoch_set(),
        CYCLES,
        &clk,
        fixtures::commit_for(b"blocked"),
        1,
        true,
        true,
        false,
        0,
        sc.ctx(),
    );
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_deny_writer() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_access::deny_writer(&sys, &mut file, BOB, 0, &clk, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_remove_deny_writer() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_access::remove_deny_writer(&sys, &mut file, BOB, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_revoke_pass() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    let pass_id = object::id(&pass);
    entry_file_access::revoke_pass(&sys, &mut file, pass_id, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_force_write_innerfile() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_write::force_write_innerfile(
        &mut file,
        &pass,
        &clk,
        &sys,
        vector[],
        fixtures::commit_for(b"blocked"),
        vector[],
        sc.ctx(),
    );
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_write_() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_write::write_(
        &mut file,
        &pass,
        true,
        option::none(),
        &clk,
        &sys,
        vector[],
        fixtures::commit_for(b"blocked"),
        vector[],
        sc.ctx(),
    );
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_set_root_change() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_fallback::set_root_change(
        &sys,
        &mut file,
        &pass,
        fixtures::commit_for(b"blocked"),
        &config,
        &clk,
        sc.ctx(),
    );
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_remove_root_change() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_fallback::remove_root_change(&sys, &mut file, &pass, &clk, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_merge_draft_into_file() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, mut config, holder, wsys, funds, clk) =
        file_world(&mut sc, true);
    entry_file_draft::merge_draft_into_file(
        &sys,
        &mut file,
        &pass,
        &mut config,
        0,
        true,
        vector[],
        &clk,
        sc.ctx(),
    );
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_delete_draft() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_draft::delete_draft(&sys, &mut file, &pass, 0, &clk, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_clear_drafts() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_draft::clear_drafts(&sys, &mut file, &pass, 0, 1, &clk, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_create_pass() {
    let mut sc = ts::begin(ALICE);
    let (sys, file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_renew_blob() {
    let mut sc = ts::begin(ALICE);
    let (sys, file, pass, mut config, holder, mut wsys, mut funds, clk) =
        file_world(&mut sc, true);
    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut funds, sc.ctx());
    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::version::EWrongPackageVersion)]
fun gate_self_withdraw_blob() {
    let mut sc = ts::begin(ALICE);
    let (sys, file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, true);
    entry_withdraw::self_withdraw_blob(&sys, config, sc.ctx());

    destroy(pass);
    destroy(wsys);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(holder);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

// === Controls ===

#[test]
fun a_current_system_is_accepted() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut file, pass, config, holder, wsys, funds, clk) = file_world(&mut sc, false);

    // The same call the stale system refuses, against one at the package version.
    entry_file_access::deny_writer(&sys, &mut file, BOB, 0, &clk, sc.ctx());

    assert!(sys.get_system_version() == 1, 0);

    finish_file(sys, file, pass, config, holder, wsys, funds, clk, sc);
}

#[test]
fun a_stale_system_can_be_migrated_back() {
    let mut sc = ts::begin(ALICE);
    let (mut sys, mut cap, funds, clk) = stale_admin(&mut sc);

    entry_admin::migrate_version(&mut cap, &mut sys, sc.ctx());
    assert!(sys.get_system_version() == 1, 0);

    // And what the gate refused a moment ago now goes through.
    entry_admin::update_cost(&mut cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());
    assert!(sys.cost_to_update_name() == FEE, 1);

    finish_admin(sys, cap, funds, clk, sc);
}
