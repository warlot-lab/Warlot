/// Renewal is the product, and until now it announced nothing at all: not which
/// blob was extended, not what it cost, not that a mandate had been drained to
/// zero. These pin the announcements that make it auditable, and in particular
/// that the cost reported is the cost actually paid rather than the number the
/// emitter happened to be handed.
#[test_only]
module warlot::event_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, event, test_scenario as ts};
use wal::wal::WAL;
use warlot::{
    admin_cap::AdminCap,
    blob_config::BlobConfig,
    entry_admin,
    entry_permission,
    entry_register,
    entry_renew,
    fixtures,
    identity_events::{Self, OperatorRoleGranted, PermissionGranted, PermissionRevoked},
    registry::Registry,
    storage_events::{Self, BlobRenewed, BlobStored, RenewCycleSpent, RenewSkipped},
    store,
    system_config::{Self, SystemConfig},
    treasury_events::{Self, SystemWithdraw},
};

// === Constants ===

const ADMIN: address = @0xADA;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const MALLORY: address = @0xBAD;

const SET: u32 = 13;
/// Short of `SET`, so a renewal has work to do.
const SHORT_EPOCHS: u32 = 5;
const CYCLES: u64 = 2;
const BLOB_SIZE: u64 = 1_024;
const FEE: u64 = 100;

// === Test-only helpers ===

#[test]
fun renew_emits() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    // `new_for_testing` runs on a dummy context, so the sender has to be put back.
    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
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

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut funds, sc.ctx());

    let renewals = event::events_by_type<BlobRenewed>();
    assert!(renewals.length() == 1, 0);

    let (
        system_id,
        renewed_config,
        owner,
        _blob_obj_id,
        epoch_set,
        current_epoch,
        epochs_extended,
        new_end_epoch,
        _wal_spent,
        _executed_by,
    ) = storage_events::read_blob_renewed(&renewals[0]);

    assert!(system_id == object::id(&sys), 1);
    assert!(renewed_config == config_id, 2);
    assert!(owner == ALICE, 3);
    assert!(epoch_set == SET, 4);
    assert!(epochs_extended > 0, 5);

    // The extension is what the blob needed, and it lands exactly on the term the
    // config was bought under.
    assert!(new_end_epoch == current_epoch + SET, 6);
    assert!(epochs_extended == SET - SHORT_EPOCHS, 7);

    // The mandate is charged once for the config, not once per blob.
    let spent = event::events_by_type<RenewCycleSpent>();
    assert!(spent.length() == 1, 8);
    let (_, _, _, blobs_extended, _, cycles_remaining, _) =
        storage_events::read_renew_cycle_spent(&spent[0]);
    assert!(blobs_extended == 1, 9);
    assert!(cycles_remaining.borrow() == CYCLES - 1, 10);

    // Work was done, so nothing was skipped.
    assert!(event::events_by_type<RenewSkipped>().is_empty(), 11);

    ts::return_shared(config);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun renew_skip_emits() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    // A mandate with nothing left. The blob is short of its term, so the only
    // thing stopping the renewal is the budget.
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        SET,
        option::some(0),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(MALLORY);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut funds, sc.ctx());

    let skipped = event::events_by_type<RenewSkipped>();
    assert!(skipped.length() == 1, 0);

    let (system_id, skipped_config, owner, blob_obj_id, reason, epoch_set, _, executed_by) =
        storage_events::read_renew_skipped(&skipped[0]);

    assert!(system_id == object::id(&sys), 1);
    assert!(skipped_config == config_id, 2);
    assert!(owner == ALICE, 3);
    assert!(reason == storage_events::renew_skip_cycle_exhausted(), 4);
    assert!(epoch_set == SET, 5);
    assert!(executed_by == MALLORY, 6);

    // The whole config was skipped, so the event names no single blob.
    assert!(blob_obj_id.is_none(), 7);

    // Nothing was renewed and no cycle was charged.
    assert!(event::events_by_type<BlobRenewed>().is_empty(), 8);
    assert!(event::events_by_type<RenewCycleSpent>().is_empty(), 9);

    ts::return_shared(config);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun wal_spent_accurate() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
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

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    // Measured on the coin itself, either side of the call. Comparing the event
    // against a number the emitter was handed would prove only that the emitter
    // repeats its argument.
    let before = funds.value();
    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut funds, sc.ctx());
    let paid = before - funds.value();

    assert!(paid > 0, 0);

    let renewals = event::events_by_type<BlobRenewed>();
    let mut reported = 0;
    renewals.do_ref!(|renewal| {
        let (_, _, _, _, _, _, _, _, wal_spent, _) = storage_events::read_blob_renewed(renewal);
        reported = reported + wal_spent;
    });

    assert!(reported == paid, 1);

    // And the per-config total agrees with the sum of the per-blob amounts.
    let spent = event::events_by_type<RenewCycleSpent>();
    let (_, _, _, _, cycle_wal_spent, _, _) = storage_events::read_renew_cycle_spent(&spent[0]);
    assert!(cycle_wal_spent == paid, 2);

    ts::return_shared(config);
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun executed_by() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut alice_funds = fixtures::wal(sc.ctx());
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        SET,
        option::some(CYCLES),
        SHORT_EPOCHS,
        &mut alice_funds,
        &clk,
        sc.ctx(),
    );

    // Renewal is open to anyone, and the chain owes the owner an answer to "who
    // paid to keep my data alive".
    sc.next_tx(MALLORY);
    let mut mallory_funds = fixtures::wal(sc.ctx());
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut mallory_funds, sc.ctx());

    let renewals = event::events_by_type<BlobRenewed>();
    assert!(renewals.length() == 1, 0);

    let (_, _, owner, _, _, _, _, _, wal_spent, executed_by) =
        storage_events::read_blob_renewed(&renewals[0]);

    assert!(owner == ALICE, 1);
    assert!(executed_by == MALLORY, 2);
    assert!(owner != executed_by, 3);

    // Mallory's coin is the one that shrank.
    assert!(wal_spent > 0, 4);
    assert!(mallory_funds.value() == fixtures::test_wal() - wal_spent, 5);

    let spent = event::events_by_type<RenewCycleSpent>();
    let (_, _, cycle_owner, _, _, _, cycle_executed_by) =
        storage_events::read_renew_cycle_spent(&spent[0]);
    assert!(cycle_owner == ALICE, 6);
    assert!(cycle_executed_by == MALLORY, 7);

    ts::return_shared(config);
    destroy(mallory_funds);
    destroy(alice_funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun stored_by_differs() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, false, sc.ctx());

    // Bob uploads on Alice's behalf. Without `stored_by` this is indistinguishable
    // from Alice uploading for herself, which is the whole of what delegation
    // traceability means.
    sc.next_tx(BOB);
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        BLOB_SIZE,
        SHORT_EPOCHS,
        &mut funds,
        sc.ctx(),
    );
    let (config_id, _) = store::store_blob_internal(
        &sys,
        vector[raw_blob],
        SET,
        CYCLES,
        ALICE,
        option::none(),
        &clk,
        sc.ctx(),
    );

    let stores = event::events_by_type<BlobStored>();
    assert!(stores.length() == 1, 0);

    let (
        system_id,
        stored_config,
        owner,
        stored_by,
        blobs_obj_id,
        blob_sizes,
        size,
        _encoded_size,
        _end_epoch,
        epoch_set,
        cycle_limit,
        uploaded_on,
    ) = storage_events::read_blob_stored(&stores[0]);

    assert!(owner == ALICE, 1);
    assert!(stored_by == BOB, 2);
    assert!(owner != stored_by, 3);

    // And the event addresses the config, which is what renewal takes.
    assert!(system_id == object::id(&sys), 4);
    assert!(stored_config == config_id, 5);
    assert!(blobs_obj_id.length() == 1, 6);
    assert!(blob_sizes == vector[BLOB_SIZE], 7);
    assert!(size == BLOB_SIZE, 8);
    assert!(epoch_set == SET, 9);
    let cycles = CYCLES;
    assert!(cycle_limit.borrow() == cycles, 10);

    // The config records no timestamp of its own now, so the store's is only in
    // the stream.
    assert!(uploaded_on == clk.timestamp_ms(), 11);

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun withdraw_emits() {
    let mut sc = ts::begin(ADMIN);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    // Put something in the treasury to take out: a rename pays the system's fee.
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let mut registry = sc.take_from_sender<Registry>();
    entry_register::update_username(
        &mut sys,
        &mut registry,
        b"alice2".to_string(),
        &mut funds,
        sc.ctx(),
    );
    assert!(sys.get_system_balance<WAL>() == FEE, 0);

    sc.next_tx(ADMIN);
    let mut cap = sc.take_from_sender<AdminCap>();

    entry_admin::withdraw_system_wal(&mut sys, &mut cap, FEE, sc.ctx());

    let payouts = event::events_by_type<SystemWithdraw>();
    assert!(payouts.length() == 1, 1);

    let (system_id, operator, coin_type, amount, new_balance) =
        treasury_events::read_system_withdraw(&payouts[0]);

    assert!(system_id == object::id(&sys), 2);
    assert!(operator == ADMIN, 3);
    assert!(amount == FEE, 4);

    // The vault is multi-coin, so an untyped amount would sum balances of
    // different things into one number that means nothing.
    assert!(coin_type == wal_type(), 5);

    // Announced against what the treasury holds afterwards, so a drain is visible
    // as a drain rather than as a sequence of unrelated amounts.
    assert!(new_balance == 0, 6);
    assert!(sys.get_system_balance<WAL>() == 0, 7);

    sc.next_tx(ADMIN);
    destroy(sc.take_from_sender<sui::coin::Coin<WAL>>());

    sc.return_to_sender(cap);
    ts::return_shared(sys);
    destroy(registry);
    destroy(funds);
    clock::destroy_for_testing(clk);
    sc.end();
}

#[test]
fun permission_events() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());

    // Registering publicly leaves the table empty, so nothing is granted yet.
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    assert!(event::events_by_type<PermissionGranted>().is_empty(), 0);

    sc.next_tx(ALICE);
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, false, false, true, false, sc.ctx());

    let grants = event::events_by_type<PermissionGranted>();
    assert!(grants.length() == 1, 1);

    let (
        system_id,
        owner,
        delegate,
        add_blob_to_address,
        create_inner_file,
        create_writer_pass,
        can_init_db,
        can_compact,
        can_set_root,
    ) = identity_events::read_permission_granted(&grants[0]);

    assert!(system_id == object::id(&sys), 2);
    assert!(owner == ALICE, 3);
    assert!(delegate == BOB, 4);

    // Every bit is carried, so a replay reconstructs the row rather than its
    // existence.
    assert!(add_blob_to_address, 5);
    assert!(create_inner_file, 6);
    assert!(!create_writer_pass, 7);
    assert!(!can_init_db, 8);
    assert!(can_compact, 9);
    assert!(!can_set_root, 15);

    sc.next_tx(ALICE);
    entry_permission::revoke(&mut sys, ALICE, BOB, sc.ctx());

    let revokes = event::events_by_type<PermissionRevoked>();
    assert!(revokes.length() == 1, 10);

    let (revoked_system, revoked_owner, revoked_delegate) =
        identity_events::read_permission_revoked(&revokes[0]);

    assert!(revoked_system == object::id(&sys), 11);
    assert!(revoked_owner == ALICE, 12);
    assert!(revoked_delegate == BOB, 13);

    // The grant is not re-announced by the revoke.
    assert!(event::events_by_type<PermissionGranted>().is_empty(), 14);

    ts::return_shared(sys);
    clock::destroy_for_testing(clk);
    sc.end();
}

#[test]
fun a_default_delegation_is_announced() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());

    // Registering with the system's operator role hands it every bit before the
    // user has done anything. It is a delegation, so it is announced as one ,  and
    // as `OperatorRoleGranted` rather than `PermissionGranted`, because it names
    // no address to grant to.
    entry_register::all_register_user_with_system_permission(
        &mut sys,
        b"alice".to_string(),
        &clk,
        sc.ctx(),
    );

    let grants = event::events_by_type<OperatorRoleGranted>();
    assert!(grants.length() == 1, 0);

    let (_, owner, add_blob, inner_file, writer_pass, init_db, compact, set_root) =
        identity_events::read_operator_role_granted(&grants[0]);

    assert!(owner == ALICE, 1);
    assert!(add_blob && inner_file && init_db && compact && set_root, 2);

    // Every bit but one. The role cannot mint passes, and the event says so
    // rather than leaving a reader to infer it from the entry point's signature.
    assert!(!writer_pass, 4);

    // And no address was named anywhere, which is the whole point of the change:
    // a registration no longer writes any key's address into the user's table.
    assert!(event::events_by_type<PermissionGranted>().is_empty(), 3);

    ts::return_shared(sys);
    clock::destroy_for_testing(clk);
    sc.end();
}

// === Private functions ===

/// The coin-type string the treasury and wallet key their balances by.
fun wal_type(): std::string::String {
    std::string::from_ascii(std::type_name::with_defining_ids<WAL>().into_string())
}
