/// The shared system object is off the write path, and an adoption is one config.
///
/// It used to be mutated by every upload ,  a user counter, an adopted-blob
/// counter, per-user index entries ,  which put one globally shared object in the
/// write set of an operation that concerns exactly one user. Under Sui's
/// shared-object congestion control that is the thing that makes uploads queue
/// behind each other. Every counter and index that forced it is gone, and this
/// asserts the result rather than trusting the deletion.
#[test_only]
module warlot::upload_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, event, test_scenario as ts};
use wal::wal::WAL;
use warlot::{
    admin_cap::AdminCap,
    blob_config::{Self, BlobConfig},
    entry_admin,
    entry_file_create,
    entry_file_write,
    entry_register,
    entry_renew,
    entry_upload,
    fixtures,
    identity_events::{UserJoinedSystem, UserLeftSystem},
    inner_file::InnerFile,
    operator,
    registry::Registry,
    system_config::SystemConfig,
    system_events::{
        AdminCapMinted,
        SystemCreated,
        SystemFeesChanged,
        SystemOperatorEnrolled,
        SystemOperatorRefreshed,
        SystemOperatorRetired,
        SystemSucceeded,
        SystemTiersChanged,
        SystemVersionMigrated
    },
    storage_events::{Self, BlobStored, ForeignBlobsAdopted},
    system_config,
    treasury_events::{SystemWithdraw, VaultCoinSupportChanged, VaultDeposited},
    writer_pass::WriterPass
};

// === Constants ===

const ALICE: address = @0xA11CE;
const ADMIN: address = @0xADA;
/// The wallet the backend signs with.
const BACKEND: address = @0xB4CE;

/// When the operator slot these tests enrol stops being accepted.
const OPERATOR_UNTIL_MS: u64 = 10_000;

const CYCLES: u64 = 2;
const SET: u32 = 13;
const SHORT_EPOCHS: u32 = 1;
const DRAFT_EPOCHS: u32 = 1;

// === Tests ===

#[test]
fun system_config_untouched() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let registry = sc.take_from_sender<Registry>();
    let renewable = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        SET,
        option::some(CYCLES),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    // One immutable borrow, taken once and used for every call below. This is
    // the assertion the field comparisons only corroborate: reaching the shared
    // object at all ,  a counter, a table entry, a dynamic field ,  needs
    // `&mut SystemConfig`, so a write path that touched it would not compile
    // against this reference.
    let system: &SystemConfig = &sys;

    let version = system.get_system_version();
    let operators = operator::operator_count(system.operator_set());
    let tiers = *system.tier_table();
    let horizon = system.max_epochs_ahead();
    let apikey_fee = system.cost_change_apikey_forms();
    let migrate_fee = system.cost_to_migrate_system();
    let name_fee = system.cost_to_update_name();
    let delete_fee = system.cost_to_delete();
    let treasury = system.get_system_balance<WAL>();

    // --- adoption from outside the protocol -------------------------------
    sc.next_tx(ALICE);
    let foreign = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_upload::foreign_blob_add(
        system,
        ALICE,
        CYCLES,
        SET,
        vector[foreign],
        &clk,
        sc.ctx(),
    );
    assert_system_silent(0);

    // --- an upload that publishes a file ----------------------------------
    sc.next_tx(ALICE);
    let first_revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    let file_id = entry_file_create::create_file(
        system,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[first_revision],
        SET,
        CYCLES,
        &clk,
        fixtures::commit_for(b"first"),
        DRAFT_EPOCHS,
        true,
        true,
        false,
        0,
        sc.ctx(),
    );
    assert_system_silent(10);

    // --- a write into the file's history ----------------------------------
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let pass = sc.take_from_sender<WriterPass>();
    let revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_file_write::force_write_innerfile(
        &mut file,
        &pass,
        &clk,
        system,
        vector[revision],
        fixtures::commit_for(b"second"),
        vector[],
        sc.ctx(),
    );
    assert_system_silent(20);

    // --- a renewal, which anyone may run ----------------------------------
    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, renewable);
    entry_renew::renew_blob(system, &mut wsys, &mut config, &mut funds, sc.ctx());
    assert_system_silent(30);

    // --- nothing on the object moved --------------------------------------
    assert!(system.get_system_version() == version, 40);
    assert!(operator::operator_count(system.operator_set()) == operators, 41);
    assert!(*system.tier_table() == tiers, 42);
    assert!(system.max_epochs_ahead() == horizon, 43);
    assert!(system.cost_change_apikey_forms() == apikey_fee, 44);
    assert!(system.cost_to_migrate_system() == migrate_fee, 45);
    assert!(system.cost_to_update_name() == name_fee, 46);
    assert!(system.cost_to_delete() == delete_fee, 47);

    // The treasury is reached through the system, so a payment taken on the
    // upload path would show here even though the fields above would not.
    assert!(system.get_system_balance<WAL>() == treasury, 48);

    sc.return_to_sender(registry);
    destroy(pass);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(config);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

// === Private functions ===

/// Abort unless the transaction just executed said nothing about the system.
///
/// Every event that reports a change to the shared object or its treasury. A
/// mutation that the field comparisons could miss ,  a fee set to the value it
/// already held, a coin type added and removed ,  still has to announce itself,
/// so this catches what a before-and-after read cannot.
fun assert_system_silent(code: u64) {
    assert!(event::events_by_type<SystemCreated>().is_empty(), code);
    assert!(event::events_by_type<SystemFeesChanged>().is_empty(), code + 1);
    assert!(event::events_by_type<SystemTiersChanged>().is_empty(), code + 2);
    assert!(event::events_by_type<SystemVersionMigrated>().is_empty(), code + 3);
    assert!(event::events_by_type<SystemSucceeded>().is_empty(), code + 4);
    assert!(event::events_by_type<AdminCapMinted>().is_empty(), code + 5);
    assert!(event::events_by_type<VaultDeposited>().is_empty(), code + 6);
    assert!(event::events_by_type<SystemWithdraw>().is_empty(), code + 7);
    assert!(event::events_by_type<VaultCoinSupportChanged>().is_empty(), code + 8);
    assert!(event::events_by_type<UserJoinedSystem>().is_empty(), code + 9);
    assert!(event::events_by_type<UserLeftSystem>().is_empty(), code + 10);
    assert!(event::events_by_type<SystemOperatorEnrolled>().is_empty(), code + 11);
    assert!(event::events_by_type<SystemOperatorRefreshed>().is_empty(), code + 12);
    assert!(event::events_by_type<SystemOperatorRetired>().is_empty(), code + 13);
}

#[test]
/// An adoption is one config, whatever it carries.
///
/// It used to be one shared object and one event per blob, so a hundred-blob
/// adoption created a hundred configs the owner then had to renew a hundred
/// times. One config per call is also the only granularity a quilt has: a quilt
/// is a single Walrus blob, and Walrus extends and deletes one whole.
fun an_adoption_is_one_config() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let registry = sc.take_from_sender<Registry>();
    let mut blobs = vector[];
    let mut i = 0u64;
    while (i < 3) {
        blobs.push_back(
            fixtures::certified_blob(
                &mut wsys,
                fixtures::blob_size(),
                fixtures::blob_epochs_ahead(),
                &mut funds,
                sc.ctx(),
            ),
        );
        i = i + 1;
    };

    entry_upload::foreign_blob_add(&sys, ALICE, CYCLES, SET, blobs, &clk, sc.ctx());

    // One custody announcement, naming one config that holds all three blobs.
    let stored = event::events_by_type<BlobStored>();
    assert!(stored.length() == 1, 0);

    let adopted = event::events_by_type<ForeignBlobsAdopted>();
    assert!(adopted.length() == 1, 1);
    let (_system_id, owner, adopted_by, config_id, blob_count) =
        storage_events::read_foreign_blobs_adopted(&adopted[0]);
    assert!(owner == ALICE && adopted_by == ALICE, 2);
    assert!(blob_count == 3, 3);

    sc.next_tx(ALICE);
    let config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    assert!(blob_config::owner(&config) == ALICE, 4);
    assert!(config.blob_ids().length() == 3, 5);
    assert!(blob_config::epoch_set(&config) == SET, 6);
    let cycles = CYCLES;
    assert!(blob_config::cycle_limit(&config).borrow() == cycles, 7);
    // An adoption is not a compaction, so it leaves no receipt.
    assert!(!blob_config::has_layout(&config), 8);

    ts::return_shared(config);
    sc.return_to_sender(registry);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
/// The operator path adopts on the user's behalf, and the record keeps both
/// addresses apart.
fun an_operator_adopts_for_the_owner() {
    let mut sc = ts::begin(ADMIN);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ADMIN);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ADMIN);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    clk.set_for_testing(1_000);

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
        false,
        &clk,
        sc.ctx(),
    );
    sc.return_to_sender(cap);

    sc.next_tx(ALICE);
    entry_register::all_register_user_with_system_permission(
        &mut sys,
        b"alice".to_string(),
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let registry = sc.take_from_sender<Registry>();

    sc.next_tx(BACKEND);
    let backend_cap = sc.take_from_sender<AdminCap>();
    let foreign = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_upload::foreign_blob_add_as_operator(
        &sys,
        &backend_cap,
        ALICE,
        CYCLES,
        SET,
        vector[foreign],
        &clk,
        sc.ctx(),
    );

    let adopted = event::events_by_type<ForeignBlobsAdopted>();
    assert!(adopted.length() == 1, 0);
    let (_system_id, owner, adopted_by, config_id, blob_count) =
        storage_events::read_foreign_blobs_adopted(&adopted[0]);
    // The custody is the user's; the act is the backend's. Collapsing the two
    // loses the audit trail.
    assert!(owner == ALICE, 1);
    assert!(adopted_by == BACKEND, 2);
    assert!(blob_count == 1, 3);
    sc.return_to_sender(backend_cap);

    sc.next_tx(ALICE);
    let config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    assert!(blob_config::owner(&config) == ALICE, 4);

    ts::return_shared(config);
    sc.return_to_sender(registry);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
