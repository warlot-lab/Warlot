/// The backend signs from a pool of wallets, and the pool changes. Until now the
/// system named one address, fixed at the mint with no setter, copied into every
/// user's delegation table at registration ,  so a second signing key held nothing
/// and a lost first key could not be replaced without every user acting.
///
/// These pin the credential that replaces it. A duplicate admin capability holds
/// a slot in the system's operator set; a user grants the *role* rather than an
/// address; and the file's owner decides, per file, whether operators may write
/// at all and which of the two routes ,  straight into history, into the draft
/// queue ,  their writes may take. Rotating the key is a transfer of an owned
/// object and writes nothing on chain.
#[test_only]
module warlot::operator_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock::{Self, Clock}, coin::Coin, event, test_scenario as ts};
use wal::wal::WAL;
use walrus::system::System;
use warlot::{
    admin_cap::AdminCap,
    draft,
    entry_admin,
    entry_file_access,
    entry_file_create,
    entry_file_draft,
    entry_file_write,
    entry_permission,
    entry_register,
    fixtures,
    inner_file::{Self, InnerFile},
    operator,
    permission,
    system_config::{Self, SystemConfig},
    system_events::{SystemOperatorEnrolled, SystemOperatorRefreshed, SystemOperatorRetired},
    user,
};

// === Constants ===

const ADMIN: address = @0xADA;
const ALICE: address = @0xA11CE;
/// The wallet the backend signs with.
const BACKEND: address = @0xB4CE;
/// The wallet the credential is rotated to.
const BACKUP: address = @0xB4C4;
const MALLORY: address = @0xBAD;

const SET: u32 = 13;
const CYCLES: u64 = 2;
const DRAFT_EPOCHS: u32 = 1;
const FEE: u64 = 100;

/// Where the clock sits while an operator is live.
const NOW_MS: u64 = 1_000;

/// When the operator slot these tests enrol stops being accepted.
const OPERATOR_UNTIL_MS: u64 = 10_000;

/// A moment past `OPERATOR_UNTIL_MS`.
const PAST_EXPIRY_MS: u64 = 20_000;

/// Deny indefinitely.
const FOREVER: u64 = 0;

// === Test-only helpers ===

/// A system holding one enrolled operator, a user who granted the operator role,
/// and one file that user owns.
///
/// `slot_bypass` is the bit the admin puts on the operator's slot; `file_allowed`,
/// `file_bypass` and `file_draft` are the owner's terms for that file. Every test
/// below is one combination of the four.
fun stage(
    sc: &mut ts::Scenario,
    slot_bypass: bool,
    file_allowed: bool,
    file_bypass: bool,
    file_draft: bool,
): (SystemConfig, System, Coin<WAL>, Clock, ID, ID) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ADMIN);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ADMIN);
    let mut sys = sc.take_shared<SystemConfig>();
    let mut clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    clk.set_for_testing(NOW_MS);

    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_admin(&sys, BACKEND, &cap, sc.ctx());

    // The duplicate is in the backend's hands before it holds a slot, which is
    // why the slot is named by id rather than by the capability object.
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
        slot_bypass,
        &clk,
        sc.ctx(),
    );
    sc.return_to_sender(cap);

    // The backend wallet is registered in its own right. A write routed into a
    // draft queue is custodied by whoever pushed it, and a config cannot be
    // owned by an address the system does not know, so a signing key whose
    // writes can be queued has to be a user. A key that always bypasses never
    // needs this.
    sc.next_tx(BACKEND);
    entry_register::all_register_user_publicly(&mut sys, b"backend".to_string(), &clk, sc.ctx());

    // Alice registers and grants the operator role in the same call. No address
    // is written into her table.
    sc.next_tx(ALICE);
    entry_register::all_register_user_with_system_permission(
        &mut sys,
        b"alice".to_string(),
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let first_revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    let file_id = entry_file_create::create_file(
        &sys,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[first_revision],
        SET,
        CYCLES,
        &clk,
        fixtures::commit_for(b"first"),
        DRAFT_EPOCHS,
        file_allowed,
        file_bypass,
        file_draft,
        false,
        0,
        sc.ctx(),
    );

    (sys, wsys, funds, clk, file_id, backend_cap_id)
}

/// One operator write against `file`, made by whoever the scenario's sender is.
fun operator_write(
    sc: &mut ts::Scenario,
    sys: &SystemConfig,
    wsys: &mut System,
    funds: &mut Coin<WAL>,
    clk: &Clock,
    file: &mut InnerFile,
    admin_cap: &AdminCap,
    to_draft: bool,
    label: vector<u8>,
) {
    let revision = fixtures::certified_blob(
        wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        funds,
        sc.ctx(),
    );

    entry_file_write::write_as_operator(
        file,
        admin_cap,
        to_draft,
        option::none(),
        clk,
        sys,
        vector[revision],
        fixtures::commit_for(label),
        vector[],
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

// === The credential works ===

#[test]
fun an_enrolled_operator_writes_into_history() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    assert!(file.track_back().length() == 1, 0);

    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"by the operator",
    );

    // Into the file's history, not into the queue: the slot and the file both
    // carry the bypass.
    assert!(file.track_back().length() == 2, 1);
    assert!(!file.has_draft_queue(), 2);
    // And the content is the owner's, not the operator's.
    assert!(file.owner() == ALICE, 3);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun an_enrolled_operator_creates_a_file() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, _file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    let first_revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );

    let made = entry_file_create::create_file_as_operator(
        &sys,
        &cap,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[first_revision],
        SET,
        CYCLES,
        &clk,
        fixtures::commit_for(b"made for alice"),
        DRAFT_EPOCHS,
        sc.ctx(),
    );

    sc.next_tx(BACKEND);
    let file = ts::take_shared_by_id<InnerFile>(&sc, made);
    assert!(file.owner() == ALICE, 0);
    // The operator was minted no pass. The owner's own pass was, as always.
    assert!(!sc.has_most_recent_for_sender<warlot::writer_pass::WriterPass>(), 1);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun an_explicit_address_grant_still_works_with_no_capability() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // Mallory holds no capability and never will. Alice names her address
    // directly, which is the delegation the operator role does not replace.
    sc.next_tx(MALLORY);
    entry_register::all_register_user_publicly(&mut sys, b"mallory".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_permission::grant(&mut sys, ALICE, MALLORY, true, true, true, true, true, true, sc.ctx());
    entry_file_access::create_pass(&sys, &file, MALLORY, PAST_EXPIRY_MS, false, sc.ctx());

    sc.next_tx(MALLORY);
    let pass = sc.take_from_sender<warlot::writer_pass::WriterPass>();
    let revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    // A pass without the admin privilege proposes rather than writes.
    entry_file_write::write_(
        &mut file,
        &pass,
        true,
        option::none(),
        &clk,
        &sys,
        vector[revision],
        fixtures::commit_for(b"by an address grant"),
        vector[],
        sc.ctx(),
    );

    assert!(draft::total_draft(inner_file::get_draft_holder(&mut file)) == 1, 0);

    destroy(pass);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === The credential is refused, one reason at a time ===

#[test]
#[expected_failure(abort_code = warlot::operator::ENotAnOperator)]
fun a_capability_with_no_slot_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // A second duplicate, minted the same way and never enrolled.
    sc.next_tx(ADMIN);
    let admin_cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_admin(&sys, MALLORY, &admin_cap, sc.ctx());
    sc.return_to_sender(admin_cap);

    sc.next_tx(MALLORY);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();

    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"unenrolled",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::operator::EOperatorExpired)]
fun an_expired_slot_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, mut clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // Nothing about the capability changed. The clock alone ends it, which is
    // what an expiry on the slot is for: a capability does not decay.
    clk.set_for_testing(PAST_EXPIRY_MS);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();

    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"too late",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::INVALIDACCESS)]
fun a_user_who_never_granted_the_role_is_not_acted_for() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, _file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // Mallory registers publicly, so her table is empty and she granted no role.
    sc.next_tx(MALLORY);
    entry_register::all_register_user_publicly(&mut sys, b"mallory".to_string(), &clk, sc.ctx());

    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    let first_revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );

    let _ = entry_file_create::create_file_as_operator(
        &sys,
        &cap,
        MALLORY,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[first_revision],
        SET,
        CYCLES,
        &clk,
        fixtures::commit_for(b"uninvited"),
        DRAFT_EPOCHS,
        sc.ctx(),
    );

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::EOperatorsRefused)]
fun a_file_closed_to_operators_refuses_one() {
    let mut sc = ts::begin(ADMIN);
    // The account-level grant is in place and the slot is live. Only the file's
    // own bit is off.
    let (sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, false, false, false);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();

    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        true,
        b"shut out",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::INVALIDWRITER)]
fun a_denied_address_is_refused_while_holding_a_live_capability() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // The write that proves the path is open, before anything is denied. Without
    // it the abort below would prove only that some earlier gate was shut.
    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"before the denial",
    );
    assert!(file.track_back().length() == 2, 0);

    sc.next_tx(ALICE);
    entry_file_access::deny_writer(&sys, &mut file, BACKEND, FOREVER, &clk, sc.ctx());

    // Same capability, same slot, same role grant. The owner denied the address.
    sc.next_tx(BACKEND);
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"after the denial",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::EPassRevoked)]
fun a_revoked_capability_id_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, file_id, cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"before the revocation",
    );
    assert!(file.track_back().length() == 2, 0);

    // The deny list's revoked-id space is keyed by `ID` and is blind to what an
    // id names, so the call that refuses one pass refuses one capability too ,
    // on this file, without waiting for the admin to retire the slot.
    sc.next_tx(ALICE);
    entry_file_access::revoke_pass(&sys, &mut file, cap_id, sc.ctx());
    assert!(file.is_pass_revoked(cap_id), 1);

    sc.next_tx(BACKEND);
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"after the revocation",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::operator::ENotAnOperator)]
fun retiring_a_slot_refuses_the_operator_everywhere_at_once() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"before retirement",
    );
    assert!(file.track_back().length() == 2, 0);

    // One admin transaction, against the system alone. No user is touched.
    sc.next_tx(ADMIN);
    let admin_cap = sc.take_from_sender<AdminCap>();
    entry_admin::retire_operator(&mut sys, &admin_cap, cap_id, sc.ctx());
    sc.return_to_sender(admin_cap);
    assert!(!operator::is_operator(sys.operator_set(), cap_id), 1);

    sc.next_tx(BACKEND);
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"after retirement",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_file_write::ENoAddBlobGrant)]
/// The root grant withdrawn on its own, with the rest of the role intact.
///
/// Every other bit stays true, so nothing but `add_blob_to_address` can be the
/// reason. This is the case the named refusal exists for: the role is still
/// granted and the credential is still live, so the generic denial from `store`
/// would have said only that permission was refused, not which one.
fun narrowing_add_blob_alone_names_the_missing_grant() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(ALICE);
    entry_permission::replace_operator_role(
        &mut sys,
        ALICE,
        false,
        true,
        true,
        true,
        true,
        sc.ctx(),
    );

    let alice = user::get_user(&sys, ALICE);
    let (add_blob, inner, _pass, db, compact, root) =
        permission::operator_role_bits(alice.uid());
    assert!(!add_blob, 0);
    assert!(inner && db && compact && root, 1);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"no grant to store under alice",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// The same missing grant, on a write that never reaches the owner.
///
/// A queued write is custodied by whoever pushed it, so it stores under the
/// backend's own address and asks Alice for nothing. The refusal above is placed
/// on the routing rather than on the entry point for exactly this reason: an
/// account that has taken `add_blob_to_address` away from the operator has
/// stopped it writing *history*, not stopped it proposing.
fun a_queued_operator_write_needs_no_grant_from_the_owner() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(ALICE);
    entry_permission::replace_operator_role(
        &mut sys,
        ALICE,
        false,
        true,
        true,
        true,
        true,
        sc.ctx(),
    );

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        true,
        b"a proposal costs alice nothing",
    );

    // The head did not move and the revision is waiting for the owner.
    assert!(file.track_back().length() == 1, 0);
    assert!(file.has_draft_queue(), 1);
    assert!(draft::total_draft(inner_file::get_draft_holder(&mut file)) == 1, 2);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
/// `can_set_root` narrows on its own, leaving every other bit standing.
///
/// The reason it is a bit of its own rather than a reuse of `can_init_db`:
/// withdrawing it freezes the account's project commitments while storing, file
/// creation, database initialisation and compaction all keep running. Folding it
/// into `can_init_db` would take three of those down with it.
fun the_root_bit_narrows_on_its_own() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // Alice's registration granted every bit the role can hold, this one
    // included.
    sc.next_tx(ALICE);
    let alice = user::get_user(&sys, ALICE);
    let (_, _, _, _, _, granted_root) = permission::operator_role_bits(alice.uid());
    assert!(granted_root, 0);

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

    let alice = user::get_user(&sys, ALICE);
    let (add_blob, inner, pass, db, compact, root) =
        permission::operator_role_bits(alice.uid());
    assert!(!root, 1);
    assert!(add_blob && inner && db && compact, 2);
    assert!(!pass, 3);

    // And the operator still writes history, which is what "leaving every other
    // bit standing" has to mean to be worth anything.
    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"still writing",
    );
    assert!(file.track_back().length() == 2, 4);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
// The refusal now comes from the entry point rather than from `store` three
// frames down, and names the grant that is missing rather than denying
// generically. Revoking the role takes `add_blob_to_address` with it, and that
// is the bit the write needs.
#[expected_failure(abort_code = warlot::entry_file_write::ENoAddBlobGrant)]
fun revoking_the_role_refuses_the_operator_on_that_account() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"before the revocation",
    );
    assert!(file.track_back().length() == 2, 0);

    sc.next_tx(ALICE);
    entry_permission::revoke_operator_role(&mut sys, ALICE, sc.ctx());
    let alice = user::get_user(&sys, ALICE);
    assert!(!permission::has_operator_role(alice.uid()), 1);

    sc.next_tx(BACKEND);
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"after the revocation",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === The bypass needs both bits, and the owner wins ===

#[test]
fun the_slot_bypass_alone_routes_the_write_into_the_queue() {
    let mut sc = ts::begin(ADMIN);
    // The admin granted the bypass. The file's owner did not.
    let (sys, mut wsys, mut funds, clk, file_id, cap_id) =
        stage(&mut sc, true, true, false, true);

    assert!(operator::operator_may_bypass_draft(sys.operator_set(), cap_id), 0);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();

    // The operator asks to skip the queue.
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"asked to skip",
    );

    // It did not skip. The head is where it was and the revision is a draft.
    assert!(file.track_back().length() == 1, 1);
    assert!(file.has_draft_queue(), 2);
    assert!(draft::total_draft(inner_file::get_draft_holder(&mut file)) == 1, 3);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun the_owner_wins() {
    let mut sc = ts::begin(ADMIN);
    // Both bits open, so the first write is a bypass. The admin's grant never
    // changes after this point ,  only the owner's answer does.
    let (sys, mut wsys, mut funds, clk, file_id, cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();

    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"while the owner allowed it",
    );

    // The same call, before the owner's refusal, reaches the history. This is
    // what stops the assertion below from passing for some other reason.
    assert!(file.track_back().length() == 2, 0);
    assert!(!file.has_draft_queue(), 1);

    // The owner refuses the bypass. Nothing else about the world changes: the
    // slot still carries it, the role is still granted, the file still admits
    // operators.
    sc.next_tx(ALICE);
    entry_file_access::set_operator_policy(&sys, &mut file, true, false, true, sc.ctx());
    assert!(operator::operator_may_bypass_draft(sys.operator_set(), cap_id), 2);
    assert!(file.operators_allowed(), 3);
    assert!(!file.operators_may_bypass_draft(), 4);

    sc.next_tx(BACKEND);
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"after the owner refused",
    );

    // Same caller, same capability, same slot, same request. The head did not
    // move and the write is sitting in the owner's queue.
    assert!(file.track_back().length() == 2, 5);
    assert!(draft::total_draft(inner_file::get_draft_holder(&mut file)) == 1, 6);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_file_access::ENotFileOwner)]
fun only_the_file_owner_sets_the_operator_policy() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) = stage(&mut sc, true, true, false, true);

    // The operator holding a live credential tries to re-open the bypass for
    // itself. The bits are gated on the sender for exactly this reason.
    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_file_access::set_operator_policy(&sys, &mut file, true, true, true, sc.ctx());

    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === The four-state policy matrix ===

// The three bits spell four states an owner can mean, and each has an answer for
// both requests an operator can make. The eight tests below are that table, one
// case each: a write lands where the policy says, or is refused by the error that
// names why. Nothing here is left to a default.

/// Stage one policy, make one operator write against it, and hand back the world.
///
/// Every case differs only in the bits it stages, what it asks for, and what it
/// asserts afterwards, so sharing the rest is what makes the table legible as a
/// table.
fun write_under_policy(
    sc: &mut ts::Scenario,
    slot_bypass: bool,
    file_allowed: bool,
    file_bypass: bool,
    file_draft: bool,
    to_draft: bool,
): (SystemConfig, System, Coin<WAL>, Clock, InnerFile, AdminCap) {
    let (sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(sc, slot_bypass, file_allowed, file_bypass, file_draft);

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();

    operator_write(
        sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        to_draft,
        b"under this policy",
    );

    (sys, wsys, funds, clk, file, cap)
}

/// The head moved and no queue was ever built.
fun assert_wrote_history(file: &InnerFile) {
    assert!(file.track_back().length() == 2, 0);
    assert!(!file.has_draft_queue(), 1);
}

/// The head did not move and the revision is waiting for the owner.
fun assert_queued(file: &mut InnerFile) {
    assert!(file.track_back().length() == 1, 0);
    assert!(draft::total_draft(inner_file::get_draft_holder(file)) == 1, 1);
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::EOperatorsRefused)]
fun refused_takes_no_direct_write() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file, cap) =
        write_under_policy(&mut sc, true, false, false, false, false);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::EOperatorsRefused)]
fun refused_takes_no_draft() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file, cap) =
        write_under_policy(&mut sc, true, false, false, false, true);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun direct_only_takes_a_direct_write() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file, cap) =
        write_under_policy(&mut sc, true, true, true, false, false);

    assert_wrote_history(&file);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_file_write::EOperatorDraftsRefused)]
fun direct_only_refuses_a_draft() {
    let mut sc = ts::begin(ADMIN);
    // The state that could not be said before. Clearing the bypass used to be
    // the only way to keep an operator out of the history, and it filled the
    // queue instead; this file takes the write or nothing.
    let (sys, wsys, funds, clk, file, cap) =
        write_under_policy(&mut sc, true, true, true, false, true);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun queue_only_routes_a_direct_write_into_the_queue() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, mut file, cap) =
        write_under_policy(&mut sc, true, true, false, true, false);

    // The behaviour the two-bit policy had for this combination, kept ,  but now
    // because the owner opened the queue rather than because the routing had
    // nowhere else to put it.
    assert_queued(&mut file);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun queue_only_takes_a_draft() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, mut file, cap) =
        write_under_policy(&mut sc, true, true, false, true, true);

    assert_queued(&mut file);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun either_takes_a_direct_write() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file, cap) =
        write_under_policy(&mut sc, true, true, true, true, false);

    assert_wrote_history(&file);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun either_takes_a_draft() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, mut file, cap) =
        write_under_policy(&mut sc, true, true, true, true, true);

    assert_queued(&mut file);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_file_write::EOperatorSlotCannotBypass)]
fun a_slot_without_the_bypass_has_no_route_into_a_direct_only_file() {
    let mut sc = ts::begin(ADMIN);
    // The file's own bits are legal and ordinary ,  it admits operators and
    // takes direct writes. What is missing is on the slot, so the routing
    // arrives with the bypass unavailable and no queue to fall back on. Reachable
    // state, named refusal.
    let (sys, wsys, funds, clk, file, cap) =
        write_under_policy(&mut sc, false, true, true, false, false);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === The fifth spelling is refused, not stored ===

#[test]
#[expected_failure(abort_code = warlot::inner_file::EPolicyOpensNoRoute)]
fun a_file_cannot_be_born_admitting_operators_with_no_route() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, _file_id, _cap_id) =
        stage(&mut sc, true, true, false, false);

    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::EPolicyOpensNoRoute)]
fun the_owner_cannot_set_a_policy_with_no_route() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // It would mean exactly what `operators_allowed: false` means, and a state
    // with two spellings is one a reader gets wrong.
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_file_access::set_operator_policy(&sys, &mut file, true, false, false, sc.ctx());

    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun shutting_operators_out_needs_no_route_at_all() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // The refusal above is about `allowed: true` alone. Closing the file is
    // still one call, and the other two bits stop meaning anything.
    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    entry_file_access::set_operator_policy(&sys, &mut file, false, false, false, sc.ctx());

    assert!(!file.operators_allowed(), 0);
    assert!(!file.operators_may_bypass_draft(), 1);
    assert!(!file.operators_may_draft(), 2);

    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === An operator-created file is born writable by its creator ===

#[test]
fun a_file_an_operator_creates_admits_that_operator_on_both_routes() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, _file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    let first_revision = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );

    // The call names no policy at all. `create_inner_file` means "make me a file
    // you will maintain", and one the operator cannot write to is not that.
    let made = entry_file_create::create_file_as_operator(
        &sys,
        &cap,
        ALICE,
        fixtures::file_writers(),
        fixtures::file_track_back(),
        vector[first_revision],
        SET,
        CYCLES,
        &clk,
        fixtures::commit_for(b"born open"),
        DRAFT_EPOCHS,
        sc.ctx(),
    );

    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, made);
    assert!(file.operators_allowed(), 0);
    assert!(file.operators_may_bypass_draft(), 1);
    assert!(file.operators_may_draft(), 2);

    // And it is the owner, not the operator, who narrows it afterwards.
    sc.next_tx(ALICE);
    entry_file_access::set_operator_policy(&sys, &mut file, true, true, false, sc.ctx());
    assert!(!file.operators_may_draft(), 3);

    sc.next_tx(BACKEND);
    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === Rotation ===

#[test]
fun rotating_the_capability_writes_nothing_on_chain() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, file_id, cap_id) =
        stage(&mut sc, true, true, true, true);

    let slots_before = operator::operator_ids(sys.operator_set());
    let (until_before, bypass_before) = (
        operator::operator_expiry(sys.operator_set(), cap_id),
        operator::operator_may_bypass_draft(sys.operator_set(), cap_id),
    );

    // The rotation itself: an owned object moving between accounts. No
    // `SystemConfig`, no `User`, no protocol call at all.
    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    transfer::public_transfer(cap, BACKUP);

    sc.next_tx(BACKUP);
    // Nothing was announced, because nothing changed.
    assert!(event::events_by_type<SystemOperatorEnrolled>().is_empty(), 0);
    assert!(event::events_by_type<SystemOperatorRefreshed>().is_empty(), 1);
    assert!(event::events_by_type<SystemOperatorRetired>().is_empty(), 6);
    assert!(operator::operator_ids(sys.operator_set()) == slots_before, 2);
    assert!(operator::operator_expiry(sys.operator_set(), cap_id) == until_before, 3);
    assert!(
        operator::operator_may_bypass_draft(sys.operator_set(), cap_id) == bypass_before,
        4,
    );

    // The new holder writes immediately, with no grant of its own anywhere.
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"by the rotated key",
    );
    assert!(file.track_back().length() == 2, 5);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === ORIGINAL and DUPLICATE, both ways ===

#[test]
#[expected_failure(abort_code = warlot::operator::ENotDuplicateCap)]
fun an_original_capability_is_refused_as_an_operator_credential() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // Enrol the original's own id, so membership cannot be what refuses it. The
    // only thing left is the state tag.
    sc.next_tx(ADMIN);
    let admin_cap = sc.take_from_sender<AdminCap>();
    let admin_cap_id = object::id(&admin_cap);
    entry_admin::enrol_operator(
        &mut sys,
        &admin_cap,
        admin_cap_id,
        OPERATOR_UNTIL_MS,
        true,
        &clk,
        sc.ctx(),
    );
    assert!(operator::is_operator(sys.operator_set(), admin_cap_id), 0);

    // Alice granted the role at registration, so this widens it rather than
    // making it. The two are separate calls precisely so this cannot be a
    // guess.
    sc.next_tx(ALICE);
    entry_permission::replace_operator_role(
        &mut sys,
        ALICE,
        true,
        true,
        true,
        true,
        true,
        sc.ctx(),
    );

    sc.next_tx(ADMIN);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &admin_cap,
        false,
        b"by the original",
    );

    sc.return_to_sender(admin_cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ENotOriginalCap)]
fun a_duplicate_cannot_reach_the_treasury() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut cap = sc.take_from_sender<AdminCap>();
    entry_admin::withdraw_system_wal(&mut sys, &mut cap, 1, sc.ctx());

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ENotOriginalCap)]
fun a_duplicate_cannot_mint_a_system() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_system(&mut cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ENotOriginalCap)]
fun a_duplicate_cannot_change_a_cost() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(BACKEND);
    let mut cap = sc.take_from_sender<AdminCap>();
    entry_admin::update_cost(&mut cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_admin::ENotOriginalCap)]
fun a_duplicate_cannot_enrol_another_operator() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    // Otherwise a leaked hot key could enrol a second one and outlive its own
    // retirement.
    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::enrol_operator(
        &mut sys,
        &cap,
        object::id_from_address(@0xFEED),
        OPERATOR_UNTIL_MS,
        true,
        &clk,
        sc.ctx(),
    );

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::operator::ECapForAnotherSystem)]
fun a_capability_from_another_system_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // A successor system, and a duplicate minted against it. Its id is put in
    // *this* system's set, so membership cannot be what refuses it.
    sc.next_tx(ADMIN);
    let mut admin_cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_system(&mut admin_cap, &mut sys, FEE, FEE, FEE, FEE, sc.ctx());
    let successor_id = *option::borrow(sys.next_system());

    sc.next_tx(ADMIN);
    let successor = ts::take_shared_by_id<SystemConfig>(&sc, successor_id);
    let successor_cap = sc.take_from_sender<AdminCap>();
    entry_admin::mint_admin(&successor, MALLORY, &successor_cap, sc.ctx());

    sc.next_tx(MALLORY);
    let foreign_cap = sc.take_from_sender<AdminCap>();
    let foreign_cap_id = object::id(&foreign_cap);
    sc.return_to_sender(foreign_cap);

    sc.next_tx(ADMIN);
    entry_admin::enrol_operator(
        &mut sys,
        &admin_cap,
        foreign_cap_id,
        OPERATOR_UNTIL_MS,
        true,
        &clk,
        sc.ctx(),
    );
    sc.return_to_sender(admin_cap);
    sc.return_to_sender(successor_cap);
    ts::return_shared(successor);

    sc.next_tx(MALLORY);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"from elsewhere",
    );

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === The set itself ===

#[test]
fun a_slot_is_refreshed_rather_than_duplicated() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, mut clk, _file_id, cap_id) =
        stage(&mut sc, false, true, true, true);

    assert!(operator::operator_count(sys.operator_set()) == 1, 0);
    assert!(operator::operator_expiry(sys.operator_set(), cap_id) == OPERATOR_UNTIL_MS, 1);
    assert!(!operator::operator_may_bypass_draft(sys.operator_set(), cap_id), 2);

    // Past the deadline, the slot is dead. Re-adding the same id moves the
    // deadline rather than taking a second slot.
    clk.set_for_testing(PAST_EXPIRY_MS);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::refresh_operator(
        &mut sys,
        &cap,
        cap_id,
        PAST_EXPIRY_MS + OPERATOR_UNTIL_MS,
        true,
        &clk,
        sc.ctx(),
    );

    assert!(operator::operator_count(sys.operator_set()) == 1, 3);
    assert!(
        operator::operator_expiry(sys.operator_set(), cap_id)
            == PAST_EXPIRY_MS + OPERATOR_UNTIL_MS,
        4,
    );
    assert!(operator::operator_may_bypass_draft(sys.operator_set(), cap_id), 5);

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun retiring_an_id_that_holds_no_slot_is_a_no_op() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::retire_operator(&mut sys, &cap, object::id_from_address(@0xFEED), sc.ctx());

    // No abort, and nothing announced: the stream never reports a retirement
    // that did not happen. This is the call that pulls a leaked key, and one
    // that can abort is one that can fail inside the batch pulling it.
    assert!(event::events_by_type<SystemOperatorRetired>().is_empty(), 0);
    assert!(operator::operator_count(sys.operator_set()) == 1, 1);

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::operator::EInvalidOperatorExpiry)]
fun a_slot_cannot_be_born_expired() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::enrol_operator(
        &mut sys,
        &cap,
        object::id_from_address(@0xFEED),
        NOW_MS,
        true,
        &clk,
        sc.ctx(),
    );

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::operator::EOperatorSetFull)]
fun the_operator_set_is_bounded() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();

    // The set already holds one. Fill it to the bound, then ask for one more.
    let mut i = 1;
    while (i <= operator::max_operators()) {
        entry_admin::enrol_operator(
            &mut sys,
            &cap,
            object::id_from_address(sui::address::from_u256(i as u256)),
            OPERATOR_UNTIL_MS,
            false,
            &clk,
            sc.ctx(),
        );
        i = i + 1;
    };

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

// === Lazy containers ===

#[test]
fun a_file_holds_no_queue_and_no_deny_list_until_it_needs_them() {
    let mut sc = ts::begin(ADMIN);
    let (sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, false, true);

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);

    // Freshly created, and already carrying a revision.
    assert!(!file.has_draft_queue(), 0);
    assert!(!file.has_deny_list(), 1);

    // Lifting a denial nobody made does not give the file a deny list to hold
    // one in.
    entry_file_access::remove_deny_writer(&sys, &mut file, MALLORY, sc.ctx());
    assert!(!file.has_deny_list(), 2);

    // The first draft builds the queue.
    sc.next_tx(BACKEND);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        true,
        b"the first draft",
    );
    assert!(file.has_draft_queue(), 3);
    assert!(!file.has_deny_list(), 4);

    // The first denial builds the deny list.
    sc.next_tx(ALICE);
    entry_file_access::deny_writer(&sys, &mut file, MALLORY, FOREVER, &clk, sc.ctx());
    assert!(file.has_deny_list(), 5);

    ts::return_to_address(BACKEND, cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::inner_file::ENoDraftQueue)]
fun merging_from_a_file_that_never_drafted_is_refused_by_name() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let pass = sc.take_from_sender<warlot::writer_pass::WriterPass>();

    entry_file_draft::clear_drafts(&sys, &mut file, &pass, 0, 4, &clk, sc.ctx());

    destroy(pass);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::operator::EAlreadyAnOperator)]
fun enrolling_a_capability_that_already_holds_a_slot_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, cap_id) = stage(&mut sc, true, true, true, true);

    // Moving a live key's deadline is `refresh_operator`. Letting the enrolment
    // do it would mean an admin onboarding what they believed was a new key
    // silently rewriting the terms of one already signing.
    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::enrol_operator(
        &mut sys,
        &cap,
        cap_id,
        PAST_EXPIRY_MS,
        false,
        &clk,
        sc.ctx(),
    );

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::operator::ENotAnOperator)]
fun refreshing_a_capability_that_holds_no_slot_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, cap_id) = stage(&mut sc, true, true, true, true);

    // The key was retired ,  by another admin, or in an earlier transaction of
    // the same batch. A refresh that fell back to enrolling would put it back.
    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    entry_admin::retire_operator(&mut sys, &cap, cap_id, sc.ctx());
    entry_admin::refresh_operator(
        &mut sys,
        &cap,
        cap_id,
        PAST_EXPIRY_MS,
        true,
        &clk,
        sc.ctx(),
    );

    sc.return_to_sender(cap);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::EOperatorRoleAlreadyGranted)]
fun granting_the_operator_role_twice_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    // Alice's registration granted it. A second grant would narrow or widen what
    // she already has while reading like a first one.
    sc.next_tx(ALICE);
    entry_permission::grant_operator_role(
        &mut sys,
        ALICE,
        true,
        false,
        false,
        false,
        false,
        sc.ctx(),
    );

    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::permission::EOperatorRoleNotGranted)]
fun replacing_an_operator_role_that_was_never_granted_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, wsys, funds, clk, _file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(MALLORY);
    entry_register::all_register_user_publicly(&mut sys, b"mallory".to_string(), &clk, sc.ctx());
    entry_permission::replace_operator_role(
        &mut sys,
        MALLORY,
        true,
        true,
        true,
        true,
        true,
        sc.ctx(),
    );

    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun the_operator_role_narrows_without_being_withdrawn() {
    let mut sc = ts::begin(ADMIN);
    let (mut sys, mut wsys, mut funds, clk, file_id, _cap_id) =
        stage(&mut sc, true, true, true, true);

    // Alice keeps the role but takes away the bit that lets the operator create
    // files for her, while leaving the one that lets it store.
    sc.next_tx(ALICE);
    entry_permission::replace_operator_role(
        &mut sys,
        ALICE,
        true,
        false,
        false,
        false,
        false,
        sc.ctx(),
    );

    let alice = user::get_user(&sys, ALICE);
    assert!(permission::has_operator_role(alice.uid()), 0);
    let (add_blob, inner, pass, db, compact, root) =
        permission::operator_role_bits(alice.uid());
    assert!(add_blob, 1);
    assert!(!inner && !pass && !db && !compact && !root, 2);

    // Writing an existing file only needs `add_blob`, so it still lands.
    sc.next_tx(BACKEND);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let cap = sc.take_from_sender<AdminCap>();
    operator_write(
        &mut sc,
        &sys,
        &mut wsys,
        &mut funds,
        &clk,
        &mut file,
        &cap,
        false,
        b"still allowed",
    );
    assert!(file.track_back().length() == 2, 3);

    sc.return_to_sender(cap);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === Denying and re-denying are separate acts ===

#[test]
fun a_denial_is_made_once_and_moved_after_that() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);

    entry_file_access::deny_writer(&sys, &mut file, MALLORY, OPERATOR_UNTIL_MS, &clk, sc.ctx());
    assert!(file.has_deny_list(), 0);

    // The owner shortens it. Asking for the deadline to move says so.
    entry_file_access::redeny_writer(&sys, &mut file, MALLORY, NOW_MS + 1, &clk, sc.ctx());

    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::deny_list::EAlreadyDenied)]
fun denying_an_already_denied_writer_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);

    // Indefinite, and then what looks like a second denial. It would have moved
    // the deadline to a date, quietly turning a permanent refusal into a
    // temporary one.
    entry_file_access::deny_writer(&sys, &mut file, MALLORY, FOREVER, &clk, sc.ctx());
    entry_file_access::deny_writer(&sys, &mut file, MALLORY, OPERATOR_UNTIL_MS, &clk, sc.ctx());

    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::deny_list::ENotDenied)]
fun moving_a_denial_that_was_never_made_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);

    entry_file_access::deny_writer(&sys, &mut file, BACKEND, FOREVER, &clk, sc.ctx());
    // The list exists now, so the refusal below is the writer's own absence from
    // it rather than the file having no list at all.
    entry_file_access::redeny_writer(&sys, &mut file, MALLORY, OPERATOR_UNTIL_MS, &clk, sc.ctx());

    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_file_access::ENotDenied)]
fun moving_a_denial_on_a_file_with_no_deny_list_is_refused() {
    let mut sc = ts::begin(ADMIN);
    let (sys, wsys, funds, clk, file_id, _cap_id) = stage(&mut sc, true, true, true, true);

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    assert!(!file.has_deny_list(), 0);

    entry_file_access::redeny_writer(&sys, &mut file, MALLORY, OPERATOR_UNTIL_MS, &clk, sc.ctx());

    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}
