/// Compaction is the delete primitive, not only the collector.
///
/// Walrus deletes, extends and shares a quilt whole and never a patch, so
/// removing one file means repacking the survivors and dropping the old quilt.
/// That puts three things on the critical path of "only the user can delete their
/// data": the repack must be delegable without being destructive, the chain must
/// hold a receipt that outlives the data it describes, and the client must be
/// able to tell a faithful repack from an unfaithful one before it deletes
/// anything.
///
/// These pin all three. The two that get skipped ,  and the two that matter ,
/// are `omission_detected` and `substitution_detected`: each shows the step that
/// catches its failure *and* shows the other steps passing, because a
/// verification procedure whose steps are redundant is one somebody will
/// eventually shorten.
#[test_only]
module warlot::compaction_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock::{Self, Clock}, coin::Coin, event, test_scenario as ts};
use wal::wal::WAL;
use walrus::system::System;
use warlot::{
    admin_cap::AdminCap,
    blob_config::{Self, BlobConfig},
    entry_admin,
    entry_compaction,
    entry_permission,
    entry_register,
    entry_renew,
    entry_withdraw,
    fixtures,
    id_set,
    layout,
    quilt::{Self, Quilt},
    storage_events::{BlobWithdrawn, LayoutRegistered},
    store,
    system_config::{Self, SystemConfig},
};

// === Constants ===

const ADMIN: address = @0xADA;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
/// The wallet a background compaction service signs with.
const BACKEND: address = @0xB4CE;
const MALLORY: address = @0xBAD;

const SET: u32 = 13;
/// A storage term the system also sells, used to build a mixed-policy quilt.
const OTHER_SET: u32 = 26;
const CYCLES: u64 = 2;

/// Where the clock sits throughout.
const NOW_MS: u64 = 1_000;

/// When the operator slot these tests enrol stops being accepted.
const OPERATOR_UNTIL_MS: u64 = 10_000;

/// How far past the current epoch a predecessor blob's storage reaches. Short, so
/// a renewal after a compaction has work to do.
const SHORT_EPOCHS: u32 = 1;

// === Test-only helpers ===

/// A registered Alice, three configs she owns, and one config holding the quilt
/// they were repacked into.
///
/// The predecessors are separate configs under one policy, which is what an
/// uncompacted account looks like: one config per upload, each renewed on its
/// own. The target is built through the ordinary store path, so its owner is
/// whoever the store was authorised for rather than whoever says so.
fun stage(
    sc: &mut ts::Scenario,
    grant_operator_role: bool,
): (SystemConfig, System, Coin<WAL>, Clock, vector<ID>, ID) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ADMIN);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ADMIN);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    clk.set_for_testing(NOW_MS);

    sc.next_tx(ALICE);
    if (grant_operator_role) {
        entry_register::all_register_user_with_system_permission(
            &mut sys,
            b"alice".to_string(),
            &clk,
            sc.ctx(),
        );
    } else {
        entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    };

    sc.next_tx(ALICE);
    let system_id = object::id(&sys);
    let mut predecessors = vector<ID>[];
    let mut i = 0u64;
    while (i < 3) {
        predecessors.push_back(
            fixtures::shared_config(
                &mut wsys,
                system_id,
                ALICE,
                SET,
                option::some(CYCLES),
                SHORT_EPOCHS,
                &mut funds,
                &clk,
                sc.ctx(),
            ),
        );
        i = i + 1;
    };

    let target = new_quilt_config(sc, &sys, &mut wsys, &mut funds, &clk, ALICE);

    (sys, wsys, funds, clk, predecessors, target)
}

/// A config holding exactly one blob, which is what a quilt is.
fun new_quilt_config(
    sc: &mut ts::Scenario,
    sys: &SystemConfig,
    wsys: &mut System,
    funds: &mut Coin<WAL>,
    clk: &Clock,
    owner: address,
): ID {
    let packed = fixtures::certified_blob(
        wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        funds,
        sc.ctx(),
    );
    let (config_id, _) = store::store_blob_internal(
        sys,
        vector[packed],
        SET,
        option::some(CYCLES),
        owner,
        option::none(),
        clk,
        sc.ctx(),
    );

    config_id
}

/// Enrol a duplicate capability for `BACKEND` and return its id.
fun enrol_backend(sc: &mut ts::Scenario, sys: &mut SystemConfig, clk: &Clock): ID {
    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_admin(sys, BACKEND, &cap, sc.ctx());

    sc.next_tx(BACKEND);
    let backend_cap = sc.take_from_sender<AdminCap>();
    let backend_cap_id = object::id(&backend_cap);
    sc.return_to_sender(backend_cap);

    sc.next_tx(ADMIN);
    entry_admin::enrol_operator(
        sys,
        &cap,
        backend_cap_id,
        OPERATOR_UNTIL_MS,
        false,
        clk,
        sc.ctx(),
    );
    sc.return_to_sender(cap);

    backend_cap_id
}

/// The three files these tests pack, one patch each.
fun three_files(): Quilt {
    quilt::new(vector[
        quilt::patch(b"f1", b"docs/a.txt", b"alpha"),
        quilt::patch(b"f2", b"docs/b.txt", b"beta"),
        quilt::patch(b"f3", b"img/c.png", b"gamma"),
    ])
}

/// `count` patches whose paths are already ascending, as a full quilt's would be.
fun many_files(count: u64): Quilt {
    let mut patches = vector[];
    let mut i = 0u64;
    while (i < count) {
        // Zero-padded decimal, which orders the same as the raw bytes.
        let mut name = b"f/";
        name.append(vector[
            48 + ((i / 1000) as u8),
            48 + (((i / 100) % 10) as u8),
            48 + (((i / 10) % 10) as u8),
            48 + ((i % 10) as u8),
        ]);
        patches.push_back(quilt::patch(name, name, name));
        i = i + 1;
    };
    quilt::new(patches)
}

/// The predecessor generation: one file per blob, which is what an uncompacted
/// account holds.
fun three_singletons(): vector<vector<u8>> {
    vector[b"f1", b"f2", b"f3"]
}

/// `ids` in ascending byte order, which is the order a compaction must name its
/// predecessors in.
fun ascending(ids: &vector<ID>): vector<ID> {
    let mut sorted = *ids;
    let length = sorted.length();
    let mut i = 1;
    while (i < length) {
        let mut j = i;
        while (j > 0 && id_set::is_before(&sorted[j], &sorted[j - 1])) {
            sorted.swap(j, j - 1);
            j = j - 1;
        };
        i = i + 1;
    };
    sorted
}

/// Register `packed` as the layout on `target`, superseding every config in
/// `predecessors`.
fun compact(
    sc: &mut ts::Scenario,
    sys: &SystemConfig,
    clk: &Clock,
    target: &mut BlobConfig,
    predecessors: &vector<ID>,
    packed: &Quilt,
    generation: u32,
) {
    let mut plan = entry_compaction::plan_compaction(sys, target);
    ascending(predecessors).do_ref!(|id| {
        let old = ts::take_shared_by_id<BlobConfig>(sc, *id);
        entry_compaction::supersede(&mut plan, &old);
        ts::return_shared(old);
    });

    entry_compaction::register_layout(
        sys,
        target,
        plan,
        layout::kind_quilt(),
        generation,
        packed.paths(),
        packed.tags(),
        clk,
        sc.ctx(),
    );
}

fun finish(
    sys: SystemConfig,
    wsys: System,
    funds: Coin<WAL>,
    clk: Clock,
    sc: ts::Scenario,
) {
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

// === Tests ===

#[test]
/// The whole path, and the receipt it leaves.
fun a_compaction_writes_its_receipt() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &packed, 1);

    let record = blob_config::layout(&target);
    assert!(record.is_quilt(), 0);
    assert!(record.generation() == 1, 1);
    assert!(record.file_count() == 3, 2);
    assert!(record.superseded_count() == 3, 3);
    assert!(record.created_at_ms() == NOW_MS, 4);

    // The root the chain holds is the one the quilt's tags imply, which is what
    // step 3 of the verification compares against.
    assert!(quilt::chain_agrees(&packed, record.file_set_root()), 5);

    // And the event carries the members the two roots commit to, which is the
    // half of the record that has to survive the deletion of the quilt.
    let announced = event::events_by_type<LayoutRegistered>();
    assert!(announced.length() == 1, 6);
    let (
        _system_id,
        config_id,
        owner,
        registered_by,
        kind,
        generation,
        file_count,
        file_set_root,
        paths,
        content_hashes,
        superseded_root,
        superseded_count,
        superseded,
        _created_at_ms,
    ) = warlot::storage_events::read_layout_registered(&announced[0]);
    assert!(config_id == target_id, 7);
    assert!(owner == ALICE && registered_by == ALICE, 8);
    assert!(kind == layout::kind_quilt() && generation == 1, 9);
    assert!(file_count == 3 && superseded_count == 3, 10);
    assert!(file_set_root == record.file_set_root(), 11);
    assert!(superseded_root == record.superseded_root(), 12);
    assert!(paths == packed.paths() && content_hashes == packed.tags(), 13);
    assert!(superseded == ascending(&predecessors), 14);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
/// The additive half of a compaction is delegable and this is the bit that
/// delegates it. Bob holds every other bit and still cannot register.
fun requires_bit() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    entry_permission::grant(&mut sys, ALICE, BOB, true, true, true, true, false, false, sc.ctx());

    sc.next_tx(BOB);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &packed, 1);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// The same call with the bit granted.
fun a_granted_delegate_may_compact() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    entry_permission::grant(&mut sys, ALICE, BOB, false, false, false, false, true, false, sc.ctx());

    sc.next_tx(BOB);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &packed, 1);

    assert!(blob_config::layout(&target).generation() == 1, 0);
    // The delegate registered it; the owner still owns everything.
    assert!(blob_config::owner(&target) == ALICE, 1);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// The operator path, which is the one a background service actually takes, and
/// the deletion that stays out of its reach afterwards.
fun owner_only_delete() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, true);
    let packed = three_files();
    let backend_cap_id = enrol_backend(&mut sc, &mut sys, &clk);

    sc.next_tx(BACKEND);
    let backend_cap = sc.take_from_sender<AdminCap>();
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);

    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    ascending(&predecessors).do_ref!(|id| {
        let old = ts::take_shared_by_id<BlobConfig>(&sc, *id);
        entry_compaction::supersede(&mut plan, &old);
        ts::return_shared(old);
    });
    entry_compaction::register_layout_as_operator(
        &sys,
        &backend_cap,
        &mut target,
        plan,
        layout::kind_quilt(),
        1,
        packed.paths(),
        packed.tags(),
        &clk,
        sc.ctx(),
    );

    assert!(object::id(&backend_cap) == backend_cap_id, 0);
    assert!(blob_config::layout(&target).generation() == 1, 1);
    // Nothing was withdrawn. The operator wrote a receipt and stopped.
    assert!(event::events_by_type<BlobWithdrawn>().is_empty(), 2);
    sc.return_to_sender(backend_cap);
    ts::return_shared(target);

    // The owner takes the superseded content back, one config at a time, and is
    // the only address that can.
    sc.next_tx(ALICE);
    predecessors.do_ref!(|id| {
        let old = ts::take_shared_by_id<BlobConfig>(&sc, *id);
        entry_withdraw::self_withdraw_blob(&sys, old, sc.ctx());
    });
    assert!(event::events_by_type<BlobWithdrawn>().length() == 3, 3);

    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENotOwner)]
/// A stranger cannot release the superseded content, before or after a
/// compaction says it has been replaced. The receipt authorises nothing.
fun a_stranger_cannot_delete_the_superseded() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &packed, 1);
    ts::return_shared(target);

    sc.next_tx(MALLORY);
    let old = ts::take_shared_by_id<BlobConfig>(&sc, predecessors[0]);
    entry_withdraw::self_withdraw_blob(&sys, old, sc.ctx());

    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::compaction::ECrossUserQuilt)]
/// A quilt spanning two owners has no participant who can delete: deletion is
/// whole-quilt, so either party removing their file destroys the other's.
fun cross_user_refused() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, _predecessors, target_id) = stage(&mut sc, false);

    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());

    sc.next_tx(BOB);
    let bobs = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        BOB,
        SET,
        option::some(CYCLES),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    let theirs = ts::take_shared_by_id<BlobConfig>(&sc, bobs);
    entry_compaction::supersede(&mut plan, &theirs);

    abort
}

#[test]
#[expected_failure(abort_code = warlot::compaction::EPolicyNotHomogeneous)]
/// Renewal is whole-quilt too, so one storage term has to serve every file in the
/// quilt permanently. A predecessor bought on a different term cannot be folded
/// in without silently changing what its owner paid for.
fun policy_homogeneous() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, _predecessors, target_id) = stage(&mut sc, false);

    sc.next_tx(ALICE);
    let longer = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        OTHER_SET,
        option::some(CYCLES),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    let other_term = ts::take_shared_by_id<BlobConfig>(&sc, longer);
    entry_compaction::supersede(&mut plan, &other_term);

    abort
}

#[test]
#[expected_failure(abort_code = warlot::compaction::EPolicyNotHomogeneous)]
/// The mandate has to match as well as the term: a quilt is renewed as one
/// object, so it spends one mandate.
fun mandate_homogeneous() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, _predecessors, target_id) = stage(&mut sc, false);

    sc.next_tx(ALICE);
    let indefinite = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        SET,
        option::none(),
        SHORT_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    let other_mandate = ts::take_shared_by_id<BlobConfig>(&sc, indefinite);
    entry_compaction::supersede(&mut plan, &other_mandate);

    abort
}

#[test]
/// A compaction that quietly drops a file.
///
/// The point of the test is not that step 4 catches it. It is that steps 2 and 3
/// **do not**: the repack is internally consistent, every byte in it matches its
/// tag, and the root the chain holds is the root over what was actually packed.
/// A verifier that stopped after step 3 would sign off on this.
fun omission_detected() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);

    // Two of the three files are repacked, and the third is simply left out.
    let dropped_one = quilt::new(vector[
        quilt::patch(b"f1", b"docs/a.txt", b"alpha"),
        quilt::patch(b"f2", b"docs/b.txt", b"beta"),
    ]);

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &dropped_one, 1);

    let on_chain_root = blob_config::layout(&target).file_set_root();
    let (faithful, agrees, whole) =
        quilt::verify(&dropped_one, on_chain_root, three_singletons());

    assert!(faithful, 0);
    assert!(agrees, 1);
    assert!(!whole, 2);

    // The file that is gone, named. `f3` was in the superseded generation and is
    // in no patch of the new one.
    assert!(!quilt::list_patches(&dropped_one).contains(&b"f3"), 3);
    assert!(quilt::complete(&dropped_one, vector[b"f1", b"f2"]), 4);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// A compaction that keeps every file and changes one file's bytes.
///
/// The mirror of the omission case, and the reason step 2 is not implied by the
/// others: the quilt is complete, the tags reproduce the root the chain holds,
/// and one name now resolves to content somebody else chose.
fun substitution_detected() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);

    let honest = three_files();
    let swapped = quilt::new(vector[
        quilt::patch(b"f1", b"docs/a.txt", b"alpha"),
        quilt::patch(b"f2", b"docs/b.txt", b"beta"),
        // The tag still describes `gamma`; the bytes no longer do.
        quilt::substituted_patch(b"f3", b"img/c.png", b"gamma", b"not gamma"),
    ]);

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    // The chain is given the honest tags, because the tags are what a
    // substituting compactor leaves alone ,  changing them would move the root
    // and be caught at once.
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &honest, 1);

    let on_chain_root = blob_config::layout(&target).file_set_root();
    let (faithful, agrees, whole) =
        quilt::verify(&swapped, on_chain_root, three_singletons());

    assert!(!faithful, 0);
    assert!(agrees, 1);
    assert!(whole, 2);

    // And the honest quilt passes all three, so the failure above is the
    // substitution and not the fixture.
    let (h_faithful, h_agrees, h_whole) =
        quilt::verify(&honest, on_chain_root, three_singletons());
    assert!(h_faithful && h_agrees && h_whole, 3);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// Registering a layout changes nothing but the target.
///
/// The behavioural half of "no accept/reject state machine": there is no pending
/// row, no accepted flag and no expiry, and the superseded configs come out of
/// the call exactly as they went in ,  still owned, still renewable, still the
/// owner's to release or keep.
fun no_state_machine() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &packed, 1);
    ts::return_shared(target);

    // Nothing was released, re-parented or retired.
    assert!(event::events_by_type<BlobWithdrawn>().is_empty(), 0);

    sc.next_tx(MALLORY);
    let cycles = CYCLES;
    predecessors.do_ref!(|id| {
        let mut old = ts::take_shared_by_id<BlobConfig>(&sc, *id);
        assert!(blob_config::owner(&old) == ALICE, 1);
        assert!(!blob_config::has_layout(&old), 2);
        assert!(blob_config::cycle_limit(&old).borrow() == cycles, 3);

        // And a superseded config is still renewable by anyone, which is what
        // stops a compaction the owner has not accepted from starving the
        // content it claims to replace.
        entry_renew::renew_blob(&sys, &mut wsys, &mut old, &mut funds, sc.ctx());
        assert!(blob_config::cycle_limit(&old).borrow() == cycles - 1, 4);
        ts::return_shared(old);
    });

    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ELayoutAlreadyRegistered)]
/// The receipt is what a holder of the superseded content checked before deleting
/// it, so a receipt that could be replaced is one Warlot could rewrite after the
/// fact. A new generation is a new config.
fun a_layout_is_written_once() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &packed, 1);

    sc.next_tx(ALICE);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &packed, 2);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::compaction::EGenerationNotAdvanced)]
/// The lineage is a strict order, not a set of claims.
fun generation_must_advance() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut first = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut first, &predecessors, &packed, 1);
    ts::return_shared(first);

    // A second repack of the first generation, claiming the same depth.
    sc.next_tx(ALICE);
    let mut wsys_mut = wsys;
    let mut funds_mut = funds;
    let second_id = new_quilt_config(&mut sc, &sys, &mut wsys_mut, &mut funds_mut, &clk, ALICE);

    sc.next_tx(ALICE);
    let mut second = ts::take_shared_by_id<BlobConfig>(&sc, second_id);
    compact(&mut sc, &sys, &clk, &mut second, &vector[target_id], &packed, 1);

    ts::return_shared(second);
    finish(sys, wsys_mut, funds_mut, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::compaction::ENothingSuperseded)]
/// A compaction that supersedes nothing is an upload, and an upload writes no
/// receipt.
fun nothing_superseded_refused() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, _predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &vector<ID>[], &packed, 1);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::compaction::ESupersedesItself)]
fun a_compaction_cannot_supersede_its_own_target() {
    let mut sc = ts::begin(ADMIN);
    let (sys, _wsys, _funds, _clk, _predecessors, target_id) = stage(&mut sc, false);

    sc.next_tx(ALICE);
    let target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    entry_compaction::supersede(&mut plan, &target);

    abort
}

#[test]
#[expected_failure(abort_code = warlot::compaction::ESupersededNotAscending)]
/// Naming one predecessor twice would put a second leaf in the tree and leave the
/// count beside the root disagreeing with it. The ascending rule catches it in
/// one comparison rather than a scan of everything named so far.
fun a_predecessor_cannot_be_named_twice() {
    let mut sc = ts::begin(ADMIN);
    let (sys, _wsys, _funds, _clk, predecessors, target_id) = stage(&mut sc, false);

    sc.next_tx(ALICE);
    let target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    let old = ts::take_shared_by_id<BlobConfig>(&sc, predecessors[0]);
    entry_compaction::supersede(&mut plan, &old);
    entry_compaction::supersede(&mut plan, &old);

    abort
}

#[test]
#[expected_failure(abort_code = warlot::compaction::EQuiltIsOneBlob)]
/// A quilt is a single Walrus blob however many patches it carries, so the kind
/// is checked against the custody rather than believed.
fun a_quilt_is_one_blob() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, predecessors, _target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let first = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    let second = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    let (two_blob_id, _) = store::store_blob_internal(
        &sys,
        vector[first, second],
        SET,
        option::some(CYCLES),
        ALICE,
        option::none(),
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let mut two_blob = ts::take_shared_by_id<BlobConfig>(&sc, two_blob_id);
    compact(&mut sc, &sys, &clk, &mut two_blob, &predecessors, &packed, 1);

    ts::return_shared(two_blob);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::compaction::EMismatchedEntries)]
fun every_path_needs_one_hash() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    ascending(&predecessors).do_ref!(|id| {
        let old = ts::take_shared_by_id<BlobConfig>(&sc, *id);
        entry_compaction::supersede(&mut plan, &old);
        ts::return_shared(old);
    });

    let mut short_tags = packed.tags();
    short_tags.pop_back();

    entry_compaction::register_layout(
        &sys,
        &mut target,
        plan,
        layout::kind_quilt(),
        1,
        packed.paths(),
        short_tags,
        &clk,
        sc.ctx(),
    );

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// The identity survives two repacks; the layout it lives in does not.
///
/// `warlot_file_id` is the quilt patch identifier and is chosen by the protocol,
/// so it is stable across a repack by construction. `QuiltPatchId` is derived from
/// the whole quilt's composition and changes, which is why it is a cache and
/// never an identity ,  nothing on chain records one.
fun a_file_id_survives_two_generations() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, predecessors, first_id) = stage(&mut sc, false);
    let packed = three_files();

    sc.next_tx(ALICE);
    let mut first = ts::take_shared_by_id<BlobConfig>(&sc, first_id);
    compact(&mut sc, &sys, &clk, &mut first, &predecessors, &packed, 1);
    let first_root = blob_config::layout(&first).file_set_root();
    assert!(blob_config::generation(&first) == 1, 0);
    ts::return_shared(first);

    // Generation two repacks the same files out of generation one. Same
    // identifiers, same paths, same bytes ,  a different quilt.
    sc.next_tx(ALICE);
    let second_id = new_quilt_config(&mut sc, &sys, &mut wsys, &mut funds, &clk, ALICE);
    let repacked = three_files();

    sc.next_tx(ALICE);
    let mut second = ts::take_shared_by_id<BlobConfig>(&sc, second_id);
    compact(&mut sc, &sys, &clk, &mut second, &vector[first_id], &repacked, 2);

    let record = blob_config::layout(&second);
    assert!(record.generation() == 2, 1);
    assert!(record.superseded_count() == 1, 2);

    // The verification runs against generation one's identifiers, read while
    // generation one is still alive. That is step 4, and it is why deletion is
    // step 5.
    let (faithful, agrees, whole) =
        quilt::verify(&repacked, record.file_set_root(), quilt::list_patches(&packed));
    assert!(faithful && agrees && whole, 3);

    // The names bind to the same content across both generations, so the root is
    // the same 32 bytes even though the quilt holding them is a different object.
    assert!(record.file_set_root() == first_root, 4);
    assert!(quilt::list_patches(&repacked) == three_singletons(), 5);

    ts::return_shared(second);

    // Only now is generation one released, and only by its owner.
    sc.next_tx(ALICE);
    let retired = ts::take_shared_by_id<BlobConfig>(&sc, first_id);
    entry_withdraw::self_withdraw_blob(&sys, retired, sc.ctx());
    assert!(event::events_by_type<BlobWithdrawn>().length() == 1, 6);

    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EPathsNotAscending)]
/// The submitted order is the canonical order, so an unordered set is refused
/// rather than quietly reordered ,  which is also what keeps the root's own sort
/// with nothing to do.
fun paths_must_arrive_in_order() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let out_of_order = quilt::new(vector[
        quilt::patch(b"img/c.png", b"img/c.png", b"gamma"),
        quilt::patch(b"f1", b"docs/a.txt", b"alpha"),
    ]);

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &out_of_order, 1);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// A quilt at the patch cap registers, and its receipt is the same 95 bytes a
/// three-file one carries.
///
/// The cap is reachable only because the entries arrive ordered. Measured against
/// the Move test runner's execution bound, the same 666 entries in arbitrary
/// order do not fold at all: the commitment's sort is insertion sort and
/// therefore quadratic, so the ordering rule is what turns the design's stated
/// ceiling into one the chain can actually reach.
fun a_full_quilt_registers() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let full = many_files(layout::max_patches());

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &full, 1);

    let record = blob_config::layout(&target);
    assert!(record.file_count() == layout::max_patches(), 0);
    assert!(record.file_count() == 666, 1);
    assert!(quilt::chain_agrees(&full, record.file_set_root()), 2);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EFileSetTooLarge)]
/// One patch past the cap. The bound is the commitment's, not a separate number:
/// a layout the chain cannot recompute a root over is a layout it cannot attest
/// to.
fun a_quilt_may_not_exceed_the_patch_cap() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let too_many = many_files(layout::max_patches() + 1);

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    compact(&mut sc, &sys, &clk, &mut target, &predecessors, &too_many, 1);

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::compaction::EOwnerMoved)]
/// A plan and its target are separate transaction inputs, so a call sequence can
/// re-parent the config between opening the plan and closing it. The plan's terms
/// were read from the config it was opened against, so they would then be
/// somebody else's.
fun a_target_that_changes_hands_mid_compaction_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, predecessors, target_id) = stage(&mut sc, false);
    let packed = three_files();

    // Bob is a real account that has asked Alice to compact for him, so the
    // permission check the registration opens with passes on his account too.
    // The refusal below is the plan's terms no longer describing its target, and
    // nothing else.
    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());
    entry_permission::grant(&mut sys, BOB, ALICE, false, false, false, false, true, false, sc.ctx());

    sc.next_tx(ALICE);
    let mut target = ts::take_shared_by_id<BlobConfig>(&sc, target_id);
    let mut plan = entry_compaction::plan_compaction(&sys, &target);
    ascending(&predecessors).do_ref!(|id| {
        let old = ts::take_shared_by_id<BlobConfig>(&sc, *id);
        entry_compaction::supersede(&mut plan, &old);
        ts::return_shared(old);
    });

    blob_config::transfer_ownership(&mut target, object::id(&sys), BOB);

    entry_compaction::register_layout(
        &sys,
        &mut target,
        plan,
        layout::kind_quilt(),
        1,
        packed.paths(),
        packed.tags(),
        &clk,
        sc.ctx(),
    );

    ts::return_shared(target);
    finish(sys, wsys, funds, clk, sc);
}
