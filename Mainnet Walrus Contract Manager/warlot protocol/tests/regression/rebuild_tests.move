/// The next scope deletes on-chain state on the grounds that the event stream can
/// rebuild it. This is the test that decides whether that is true.
///
/// It drives one long history through the real entry points ,  registration,
/// delegation granted and taken back, uploads for oneself and on someone else's
/// behalf, adoption from outside, renewal by a stranger, withdrawal, a file with
/// its rollback window overflowing, a fallback set and dropped, a draft proposed
/// and accepted, a pass minted, revoked and destroyed, a writer denied and
/// released, the wallet, the treasury and the admin surface ,  replaying every
/// event as it goes and then comparing the reconstruction against the objects the
/// chain actually holds, field by field.
///
/// The comparison is written from the chain side. Each assertion names a field of
/// a real object and demands the replay produce it, so a field the stream does not
/// carry fails here rather than being quietly left out of the check.
#[test_only]
module warlot::rebuild_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, coin, test_scenario as ts};
use wal::wal::WAL;
use walrus::blob::Blob;
use warlot::{
    admin_cap::AdminCap,
    blob_config::{Self, BlobConfig},
    deny_list,
    draft,
    entry_admin,
    entry_innerfile,
    entry_permission,
    entry_register,
    entry_renew,
    entry_upload,
    entry_wallet,
    entry_withdraw,
    file_data,
    fixtures,
    foreign_meta::{Self, ForeignMeta},
    inner_file::{Self, InnerFile},
    permission,
    registry::{Self, Registry},
    replay,
    store,
    system_config::{Self, SystemConfig},
    user,
    vault,
    wallet,
    writer_pass::{Self, WriterPass}
};

// === Constants ===

const ADMIN: address = @0xADA;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const MALLORY: address = @0xBAD;

const SET: u32 = 13;
const START_EPOCHS: u32 = 5;
const CYCLES: u64 = 2;
const BLOB_SIZE: u64 = 1_024;
const FEE: u64 = 100;
const NEW_FEE: u64 = 250;

const FILE_WRITERS: u8 = 5;
const FILE_TRACK_BACK: u8 = 3;
const FILE_DRAFT_EPOCHS: u32 = 1;
const PASS_EXPIRY_MS: u64 = 500_000;
const DENY_UNTIL_MS: u64 = 900_000;

const WALLET_DEPOSIT: u64 = 4_000;
const WALLET_WITHDRAW: u64 = 1_500;

/// How far the clock moves between steps.
///
/// It has to move at all: every timestamp the protocol records is taken from this
/// clock, so a scenario that leaves it at zero cannot tell an event carrying the
/// right timestamp from one carrying a constant.
const TICK_MS: u64 = 1_000;

// === Test-only helpers ===

#[test]
fun rebuild_matches_chain() {
    let mut ledger = replay::new();
    let mut sc = ts::begin(ADMIN);

    // --- genesis -----------------------------------------------------------
    system_config::init_for_testing(sc.ctx());
    ledger.absorb();

    sc.next_tx(ADMIN);
    let mut wsys = fixtures::walrus_system(sc.ctx());
    ledger.absorb();

    // --- registration ------------------------------------------------------
    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let system_id = object::id(&sys);
    let mut clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(BOB);
    let mut bob_funds = fixtures::wal(sc.ctx());
    entry_register::all_register_user_with_system_permission(
        &mut sys,
        b"bob".to_string(),
        &clk,
        sc.ctx(),
    );
    ledger.absorb();

    // --- delegation granted, taken back, and granted again -----------------
    sc.next_tx(ALICE);
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, true, true, true, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    entry_permission::revoke(&mut sys, ALICE, BOB, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, false, false, true, sc.ctx());
    ledger.absorb();

    // --- an upload for herself, and one on her behalf ----------------------
    sc.next_tx(ALICE);
    let alice_blob = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut funds, sc.ctx());
    let (own_config, _) = store::store_blob_internal(
        &sys,
        vector[alice_blob],
        SET,
        CYCLES,
        option::none(),
        ALICE,
        &clk,
        sc.ctx(),
    );
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(BOB);
    let bob_blob = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut bob_funds, sc.ctx());
    let (delegated_config, _) = store::store_blob_internal(
        &sys,
        vector[bob_blob],
        SET,
        CYCLES,
        option::none(),
        ALICE,
        &clk,
        sc.ctx(),
    );
    ledger.absorb();

    // --- blobs adopted from outside the protocol ---------------------------
    sc.next_tx(ALICE);
    let mut alice_meta = sc.take_from_sender<ForeignMeta>();
    let mut alice_registry = sc.take_from_sender<Registry>();
    let alice_registry_id = object::id(&alice_registry);
    let foreign_one = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut funds, sc.ctx());
    let foreign_two = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut funds, sc.ctx());
    entry_upload::foreign_blob_add(
        &alice_registry,
        &sys,
        &mut alice_meta,
        CYCLES,
        SET,
        vector[foreign_one, foreign_two],
        &clk,
        sc.ctx(),
    );
    ledger.absorb();

    // --- a stranger renews one config --------------------------------------
    sc.next_tx(MALLORY);
    let mut mallory_funds = fixtures::wal(sc.ctx());
    let mut renewed = ts::take_shared_by_id<BlobConfig>(&sc, own_config);
    entry_renew::renew_blob(&sys, &mut wsys, &mut renewed, &mut mallory_funds, sc.ctx());
    ledger.absorb();

    // --- the owner takes one back ------------------------------------------
    sc.next_tx(ALICE);
    let withdrawn = ts::take_shared_by_id<BlobConfig>(&sc, delegated_config);
    entry_withdraw::self_withdraw_blob(&sys, withdrawn, sc.ctx());
    ledger.absorb();

    // --- a file, and its rollback window overflowing -----------------------
    sc.next_tx(ALICE);
    let first_revision = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut funds, sc.ctx());
    let file_id = entry_innerfile::create_file(
        &sys,
        ALICE,
        FILE_WRITERS,
        FILE_TRACK_BACK,
        vector[first_revision],
        SET,
        CYCLES,
        &clk,
        fixtures::commit_for(b"r0"),
        FILE_DRAFT_EPOCHS,
        false,
        0,
        sc.ctx(),
    );
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let mut owner_pass = sc.take_from_sender<WriterPass>();
    let owner_pass_id = object::id(&owner_pass);

    let depth = FILE_TRACK_BACK as u64;
    let mut written = 0;
    while (written < 3) {
        sc.next_tx(ALICE);

        // Once the window is full every write pushes one revision out of it, and
        // the caller hands over the config that revision names.
        let window = file.track_back();
        let evicted = if (window.length() >= depth) {
            let oldest = file_data::blob_config_id(&window[window.length() - 1]);
            vector[ts::take_shared_by_id<BlobConfig>(&sc, oldest)]
        } else {
            vector<BlobConfig>[]
        };

        let revision = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut funds, sc.ctx());
        entry_innerfile::force_write_innerfile(
            &mut file,
            &mut owner_pass,
            &clk,
            &sys,
            vector[revision],
            fixtures::commit_for(b"revision"),
            evicted,
            sc.ctx(),
        );
        ledger.absorb();
        tick(&mut clk);
        written = written + 1;
    };

    // --- a fallback recorded, then dropped ---------------------------------
    sc.next_tx(ALICE);
    let head_config_id = file_data::blob_config_id(&file.track_back()[0]);
    let head_config = ts::take_shared_by_id<BlobConfig>(&sc, head_config_id);
    entry_innerfile::set_root_change(
        &sys,
        &mut file,
        &mut owner_pass,
        fixtures::commit_for(b"known good"),
        &head_config,
        &clk,
        sc.ctx(),
    );
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    entry_innerfile::remove_root_change(&sys, &mut file, &mut owner_pass, &clk, sc.ctx());
    ledger.absorb();

    // --- a pass, a draft, and the merge that accepts it --------------------
    sc.next_tx(ALICE);
    entry_innerfile::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(BOB);
    let mut bob_pass = sc.take_from_sender<WriterPass>();
    let bob_pass_id = object::id(&bob_pass);
    let proposal = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut bob_funds, sc.ctx());
    entry_innerfile::write_(
        &mut file,
        &mut bob_pass,
        true,
        0,
        false,
        &clk,
        &sys,
        vector[proposal],
        fixtures::commit_for(b"a proposal"),
        vector[],
        sc.ctx(),
    );
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    let draft_config_id = ts::most_recent_id_shared<BlobConfig>().destroy_some();
    let mut draft_config = ts::take_shared_by_id<BlobConfig>(&sc, draft_config_id);
    let oldest = file_data::blob_config_id(&file.track_back()[file.track_back().length() - 1]);
    let displaced = ts::take_shared_by_id<BlobConfig>(&sc, oldest);
    entry_innerfile::merge_draft_into_file(
        &sys,
        &mut file,
        &mut owner_pass,
        &mut draft_config,
        0,
        true,
        vector[displaced],
        &clk,
        sc.ctx(),
    );
    ledger.absorb();

    // --- the two revocations, and a pass destroyed by its holder ------------
    sc.next_tx(ALICE);
    entry_innerfile::deny_writer(&sys, &mut file, MALLORY, DENY_UNTIL_MS, &clk, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    entry_innerfile::remove_deny_writer(&sys, &mut file, MALLORY, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    entry_innerfile::deny_writer(&sys, &mut file, BOB, DENY_UNTIL_MS, &clk, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    entry_innerfile::revoke_pass(&sys, &mut file, bob_pass_id, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(BOB);
    writer_pass::destroy_writer_pass(bob_pass, sc.ctx());
    ledger.absorb();

    // --- the wallet ---------------------------------------------------------
    sc.next_tx(ALICE);
    entry_wallet::deposit_coin(&mut sys, &mut funds, WALLET_DEPOSIT, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);
    entry_wallet::withdraw_wal(&mut sys, WALLET_WITHDRAW, sc.ctx());
    ledger.absorb();

    // --- the treasury -------------------------------------------------------
    sc.next_tx(ALICE);
    entry_register::update_username(
        &mut sys,
        &mut alice_registry,
        b"alice-renamed".to_string(),
        &mut funds,
        sc.ctx(),
    );
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ADMIN);
    let mut cap = sc.take_from_sender<AdminCap>();
    entry_admin::withdraw_system_wal(&mut sys, &mut cap, FEE / 2, sc.ctx());
    ledger.absorb();

    // --- the admin surface --------------------------------------------------
    sc.next_tx(ADMIN);
    entry_admin::update_cost(&mut cap, &mut sys, NEW_FEE, NEW_FEE, NEW_FEE, NEW_FEE, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ADMIN);
    entry_admin::update_tier_table(&mut cap, &mut sys, vector[1, 2, 7, 26], 30, sc.ctx());
    ledger.absorb();

    // === The comparison, written from the chain side =======================

    sc.next_tx(ALICE);

    // --- SystemConfig -------------------------------------------------------
    let system_row = ledger.system(system_id);
    assert!(system_row.system_previous() == object::id_from_address(@0x0), 0);
    assert!(system_row.system_next().is_none(), 1);
    assert!(system_row.system_version() == sys.get_system_version(), 2);
    assert!(system_row.system_warlot_address() == sys.get_warlot_address(), 3);
    assert!(system_row.system_tier_table() == *sys.tier_table(), 4);
    assert!(system_row.system_max_epochs_ahead() == sys.max_epochs_ahead(), 5);

    let (apikey, migrate, name, del) = system_row.system_costs();
    assert!(apikey == sys.cost_change_apikey_forms(), 6);
    assert!(migrate == sys.cost_to_migrate_system(), 7);
    assert!(name == sys.cost_to_update_name(), 8);
    assert!(del == sys.cost_to_delete(), 9);

    // Derived from joins minus leaves, then held against the counter the chain
    // keeps for itself.
    assert!(system_row.system_users() == sys.users(), 10);
    assert!(system_row.system_vault_wal() == sys.get_system_balance<WAL>(), 11);
    assert!(system_row.system_admin_caps().length() == 1, 12);
    assert!(system_row.system_admin_caps()[0] == object::id(&cap), 13);
    assert!(system_row.system_accepts(wal_type()), 14);
    assert!(vault::is_coin_supported<WAL>(sys.get_vault_mut()), 15);

    // --- Alice's user record, registry and wallet ---------------------------
    let alice_row = ledger.user(ALICE);
    assert!(alice_row.user_joined(), 16);
    assert!(alice_row.user_system() == system_id, 17);
    assert!(alice_row.user_username() == alice_registry.public_username(), 18);
    assert!(alice_row.user_registry() == alice_registry_id, 19);
    assert!(alice_row.user_created_at() == alice_registry.created_at(), 20);
    assert!(alice_row.user_decay_at() == alice_registry.decay_at(), 21);
    assert!(alice_row.user_foreign_meta().borrow() == object::id(&alice_meta), 22);
    assert!(alice_row.user_foreign_configs() == alice_meta.total_blob_config(), 23);
    assert!(alice_row.user_foreign_chunk() == alice_meta.current_index(), 24);

    let alice_user = user::get_user(&sys, ALICE);
    assert!(alice_row.user_id() == object::id(alice_user), 25);
    assert!(alice_user.owner() == ALICE, 26);

    // Delegation, bit by bit, against the table itself.
    assert!(ledger.delegation_live(ALICE, BOB), 27);
    assert!(permission::has_delegate(alice_user.uid(), BOB), 28);
    let (l_add, l_file, l_pass, l_db, l_compact) = ledger.delegation_bits(ALICE, BOB);
    let (c_add, c_file, c_pass, c_db, c_compact) =
        permission::delegate_bits(alice_user.uid(), BOB);
    assert!(l_add == c_add && l_file == c_file, 29);
    assert!(l_pass == c_pass && l_db == c_db && l_compact == c_compact, 30);

    // Bob's registration handed the system's own delegate every bit, before Bob
    // had done anything.
    assert!(ledger.delegation_live(BOB, sys.get_warlot_address()), 31);
    let bob_user = user::get_user(&sys, BOB);
    assert!(permission::has_delegate(bob_user.uid(), sys.get_warlot_address()), 32);

    // Deposits minus withdrawals, against the balance the wallet holds.
    let expected_wallet = alice_row.user_wallet_wal();
    let alice_wallet = user::get_user_mut(&mut sys, ALICE).get_wallet();
    assert!(expected_wallet == WALLET_DEPOSIT - WALLET_WITHDRAW, 33);
    assert!(expected_wallet == wallet::get_balance<WAL>(alice_wallet), 34);
    assert!(alice_row.user_wallet() == object::id(alice_wallet), 35);

    // --- the config the stranger renewed ------------------------------------
    let renewed_row = ledger.config(own_config);
    assert!(renewed_row.config_live(), 36);
    assert!(renewed_row.config_owner() == blob_config::owner(&renewed), 37);
    assert!(renewed_row.config_stored_by() == ALICE, 38);
    assert!(renewed_row.config_epoch_set() == blob_config::epoch_set(&renewed), 39);
    assert!(renewed_row.config_cycle_limit() == blob_config::cycle_limit(&renewed), 40);
    assert!(renewed_row.config_cycle_limit().borrow() == CYCLES - 1, 41);
    assert!(renewed_row.config_file_meta() == renewed.fileMeta_id(), 42);
    assert!(renewed_row.config_uploaded_on() == renewed.uploaded_on(), 43);
    assert!(renewed_row.config_blobs() == renewed.blob_ids(), 44);
    assert!(renewed_row.config_blob_sizes() == vector[BLOB_SIZE], 45);
    assert!(renewed_row.config_size() == BLOB_SIZE, 46);
    assert!(renewed_row.config_renewals() == 1, 47);
    assert!(renewed_row.config_wal_spent() > 0, 48);

    // --- the config the owner withdrew --------------------------------------
    // A replay that only ever adds reconstructs a state that never existed.
    let gone_row = ledger.config(delegated_config);
    assert!(!gone_row.config_live(), 49);
    assert!(gone_row.config_owner() == ALICE, 50);
    assert!(gone_row.config_stored_by() == BOB, 51);
    assert!(gone_row.config_owner() != gone_row.config_stored_by(), 52);

    // --- the draft's config, re-parented by the merge ------------------------
    let draft_row = ledger.config(draft_config_id);
    assert!(draft_row.config_stored_by() == BOB, 54);
    assert!(draft_row.config_owner() == ALICE, 55);
    assert!(draft_row.config_owner() == blob_config::owner(&draft_config), 56);

    // --- the file, its window, its fallback, its drafts and its denials -------
    let file_row = ledger.file(file_id);
    assert!(file_row.file_system() == system_id, 57);
    assert!(file_row.file_owner() == file.owner(), 58);
    assert!(file_row.file_created_by() == ALICE, 59);
    assert!(file_row.file_writers_length() == file.writers_length(), 60);
    assert!(file_row.file_track_back_length() == file.track_back_length(), 61);
    assert!(file_row.file_epoch_set() == file.epoch_set(), 62);
    assert!(file_row.file_cycle_end() == file.cycle_end(), 63);
    assert!(file_row.file_created_at_ms() == file.created_at_ms(), 64);
    assert!(file_row.file_last_modified() == file.last_modified(), 65);

    // The rollback window, entry by entry, newest first.
    let window = file.track_back();
    let rebuilt_commits = file_row.file_window_commits();
    let rebuilt_configs = file_row.file_window_configs();
    let rebuilt_authors = file_row.file_window_authors();
    assert!(rebuilt_commits.length() == window.length(), 66);
    assert!(window.length() == FILE_TRACK_BACK as u64, 67);
    let mut slot = 0;
    while (slot < window.length()) {
        assert!(rebuilt_commits[slot] == file_data::commit(&window[slot]), 68);
        assert!(rebuilt_configs[slot] == file_data::blob_config_id(&window[slot]), 69);
        assert!(rebuilt_authors[slot] == file_data::commit_by(&window[slot]), 70);
        slot = slot + 1;
    };

    // The newest entry is the draft Bob proposed and Alice accepted.
    assert!(rebuilt_configs[0] == draft_config_id, 71);
    assert!(rebuilt_authors[0] == BOB, 72);

    // The fallback was set and then dropped, and the replay followed both.
    assert!(file_row.file_root_change().is_none(), 73);
    assert!(!file.has_root_change(), 74);

    // Pins minus merges, against the queue's own counter.
    let rebuilt_total_draft = file_row.file_total_draft();
    let rebuilt_available_index = file_row.file_available_index();
    let draft_holder = file.get_draft_holder();
    assert!(rebuilt_total_draft == draft::total_draft(draft_holder), 75);
    assert!(rebuilt_available_index == draft::available_index(draft_holder), 76);
    assert!(rebuilt_total_draft == 0, 77);
    assert!(rebuilt_available_index == 1, 78);

    // Denials on, off and on again, counted rather than copied.
    let deny_obj = deny_list::borrow(file.uid());
    assert!(ledger.denials_live(file_id) == deny_list::numbers_of_deny(deny_obj), 79);
    assert!(ledger.denials_live(file_id) == 1, 80);
    assert!(deny_list::contains(deny_obj, BOB), 81);
    assert!(!deny_list::contains(deny_obj, MALLORY), 82);
    assert!(ledger.denial_until(file_id, BOB) == deny_list::period(deny_obj, BOB), 83);

    // --- the passes ----------------------------------------------------------
    let owner_pass_row = ledger.pass(owner_pass_id);
    assert!(owner_pass_row.pass_file() == file_id, 84);
    assert!(owner_pass_row.pass_holder() == ALICE, 85);
    assert!(owner_pass_row.pass_duration() == owner_pass.duration(), 86);
    assert!(owner_pass_row.pass_admin_privilege() == owner_pass.has_admin_privilege(), 87);
    assert!(!owner_pass_row.pass_revoked() && !owner_pass_row.pass_destroyed(), 88);

    let bob_pass_row = ledger.pass(bob_pass_id);
    assert!(bob_pass_row.pass_holder() == BOB, 89);
    assert!(bob_pass_row.pass_duration() == PASS_EXPIRY_MS, 90);
    assert!(!bob_pass_row.pass_admin_privilege(), 91);
    assert!(bob_pass_row.pass_revoked(), 92);
    assert!(inner_file::is_pass_revoked(&file, bob_pass_id), 93);
    assert!(bob_pass_row.pass_destroyed(), 94);

    // --- deletion, checked against what Alice actually holds -----------------
    //
    // Three configs died: the one she withdrew, and the two revisions the
    // rollback window pushed out. Their blobs are hers outright now, and the
    // replay names exactly those.
    let released = ledger.released_blobs(ALICE);
    let owned = ts::ids_for_sender<Blob>(&sc);
    assert!(released.length() == 3, 95);
    assert!(owned.length() == released.length(), 96);
    released.do_ref!(|blob_id| assert!(owned.contains(blob_id), 97));

    assert!(ledger.live_configs(ALICE) > 0, 98);
    assert!(ledger.applied() > 0, 99);

    ledger.absorb();

    owned.do_ref!(|blob_id| destroy(sc.take_from_sender_by_id<Blob>(*blob_id)));
    ts::return_to_address(ADMIN, cap);
    sc.return_to_sender(alice_registry);
    sc.return_to_sender(alice_meta);
    destroy(owner_pass);
    destroy(funds);
    destroy(bob_funds);
    destroy(mallory_funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(head_config);
    ts::return_shared(draft_config);
    ts::return_shared(renewed);
    ts::return_shared(file);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun rebuild_follows_a_user_between_systems() {
    let mut ledger = replay::new();
    let mut sc = ts::begin(ADMIN);

    system_config::init_for_testing(sc.ctx());
    ledger.absorb();

    sc.next_tx(ADMIN);
    let mut first = sc.take_shared<SystemConfig>();
    let first_id = object::id(&first);
    let mut cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_system(&mut cap, &mut first, FEE, FEE, FEE, FEE, sc.ctx());
    let second_id = *option::borrow(first.next_system());
    ledger.absorb();

    sc.next_tx(ALICE);
    let mut second = ts::take_shared_by_id<SystemConfig>(&sc, second_id);
    let mut clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    entry_register::all_register_user_publicly(&mut first, b"alice".to_string(), &clk, sc.ctx());
    ledger.absorb();
    tick(&mut clk);

    // The move is a removal from one system and an addition to the other, and a
    // replay that could not represent the removal would leave Alice registered
    // twice.
    sc.next_tx(ALICE);
    let mut alice_registry = sc.take_from_sender<Registry>();
    entry_register::migrate_system(
        &mut alice_registry,
        &mut first,
        &mut second,
        &mut funds,
        &clk,
        sc.ctx(),
    );
    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ALICE);

    let first_row = ledger.system(first_id);
    assert!(first_row.system_next().borrow() == second_id, 0);
    assert!(first_row.system_users() == first.users(), 1);
    assert!(first_row.system_users() == 0, 2);
    assert!(!user::check_user(&first, ALICE), 3);

    let second_row = ledger.system(second_id);
    assert!(second_row.system_previous() == first_id, 4);
    assert!(second_row.system_users() == second.users(), 5);
    assert!(second_row.system_users() == 1, 6);
    assert!(user::check_user(&second, ALICE), 7);

    // The migration fee reached the system that was joined, not the one left.
    assert!(second_row.system_vault_wal() == second.get_system_balance<WAL>(), 8);
    assert!(second_row.system_vault_wal() == FEE, 9);
    assert!(first_row.system_vault_wal() == first.get_system_balance<WAL>(), 10);

    let alice_row = ledger.user(ALICE);
    assert!(alice_row.user_joined(), 11);
    assert!(alice_row.user_system() == second_id, 12);
    assert!(alice_row.user_system() == registry::get_system(&alice_registry), 13);
    assert!(alice_row.user_updated_at() == alice_registry.updated_at(), 14);

    // Both capabilities were announced, each against the system it administers.
    assert!(first_row.system_admin_caps().length() == 1, 15);
    assert!(second_row.system_admin_caps().length() == 1, 16);

    ledger.absorb();
    tick(&mut clk);

    sc.next_tx(ADMIN);
    destroy(sc.take_from_sender<AdminCap>());

    sc.return_to_sender(cap);
    destroy(alice_registry);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(second);
    ts::return_shared(first);
    sc.end();
}

// === Private functions ===

/// Move the clock on, so no two recorded timestamps are the same by accident.
fun tick(clk: &mut clock::Clock) {
    clock::increment_for_testing(clk, TICK_MS);
}

/// The coin-type string the treasury keys its balances by.
fun wal_type(): std::string::String {
    std::string::from_ascii(std::type_name::with_defining_ids<WAL>().into_string())
}
