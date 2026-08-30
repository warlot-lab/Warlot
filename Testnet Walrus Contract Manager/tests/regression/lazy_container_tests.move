/// An empty container still costs an object header and a field entry, and most
/// accounts never fill either of these.
///
/// A user's coin bank and their delegation table were both built at registration,
/// for every user, whether or not they ever funded a wallet or delegated to
/// anybody. Both are dynamic object fields ,  two objects each, counting the
/// entry that names the child ,  so the pair was ~815 B charged to every
/// registration up front. They are attached by the first call that puts something
/// in them now, which is a change to *when* they exist and to nothing else about
/// them: the same layout, the same reads, the same answers.
///
/// These pin the "nothing else about them" half. A lazy container is only safe if
/// every reader answers an absent container exactly as it answers an empty one,
/// and every writer that must refuse still refuses.
#[test_only]
module warlot::lazy_container_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, event, test_scenario as ts};
use wal::wal::WAL;
use warlot::{
    entry_permission,
    entry_register,
    entry_wallet,
    fixtures,
    identity_events::{PermissionGranted, PermissionRevoked},
    permission,
    system_config::{Self, SystemConfig},
    user,
    wallet,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

const DEPOSIT: u64 = 500;

// === Test-only helpers ===

/// A system with Alice registered and nothing else done.
fun registered(sc: &mut ts::Scenario, with_operator_role: bool): SystemConfig {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());

    if (with_operator_role) {
        entry_register::all_register_user_with_system_permission(
            &mut sys,
            b"alice".to_string(),
            &clk,
            sc.ctx(),
        );
    } else {
        entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    };

    clock::destroy_for_testing(clk);

    sys
}

// === Tests ===

#[test]
/// A registration builds neither container, and both absences read as empty.
fun a_registration_builds_neither_container() {
    let mut sc = ts::begin(ALICE);
    let mut sys = registered(&mut sc, false);

    sc.next_tx(ALICE);
    assert!(!permission::has_delegation_table(user::get_user(&sys, ALICE).uid()), 0);
    // An account that has delegated to nobody has delegated to Bob, and answers
    // so without a table to look in.
    assert!(!permission::has_delegate(user::get_user(&sys, ALICE).uid(), BOB), 1);
    assert!(!user::grants_add_blob(user::get_user(&sys, ALICE), BOB), 2);
    // The owner needs no row to store for themselves.
    assert!(user::grants_add_blob(user::get_user(&sys, ALICE), ALICE), 3);

    let alice_wallet = user::get_user_mut(&mut sys, ALICE).get_wallet();
    assert!(!wallet::has_bank_for_testing(alice_wallet), 4);
    assert!(wallet::get_balance<WAL>(alice_wallet) == 0, 5);
    assert!(!wallet::has_estimate<WAL>(alice_wallet, 1), 6);

    ts::return_shared(sys);
    sc.end();
}

#[test]
/// The operator role is a dynamic field of its own and never needed the table, so
/// a registration that opens with a full delegation still builds none.
fun the_operator_role_needs_no_table() {
    let mut sc = ts::begin(ALICE);
    let sys = registered(&mut sc, true);

    sc.next_tx(ALICE);
    let alice = user::get_user(&sys, ALICE);
    assert!(permission::has_operator_role(alice.uid()), 0);
    assert!(!permission::has_delegation_table(alice.uid()), 1);

    let (add, file, pass, db, compact) = permission::operator_role_bits(alice.uid());
    assert!(add && file && pass && db && compact, 2);

    ts::return_shared(sys);
    sc.end();
}

#[test]
/// The first deposit attaches the bank, and the second finds it.
fun the_first_deposit_attaches_the_bank() {
    let mut sc = ts::begin(ALICE);
    let mut sys = registered(&mut sc, false);

    sc.next_tx(ALICE);
    let mut funds = fixtures::wal(sc.ctx());
    let after_first = entry_wallet::deposit_coin(&mut sys, &mut funds, DEPOSIT, sc.ctx());
    assert!(after_first == DEPOSIT, 0);

    let after_second = entry_wallet::deposit_coin(&mut sys, &mut funds, DEPOSIT, sc.ctx());
    assert!(after_second == DEPOSIT * 2, 1);

    let alice_wallet = user::get_user_mut(&mut sys, ALICE).get_wallet();
    assert!(wallet::has_bank_for_testing(alice_wallet), 2);
    assert!(wallet::get_balance<WAL>(alice_wallet) == DEPOSIT * 2, 3);

    destroy(funds);
    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::wallet::ENoBalance)]
/// A wallet with no bank holds nothing, and a withdrawal from it is refused by
/// the same error an empty balance raises.
fun a_wallet_with_no_bank_cannot_pay_out() {
    let mut sc = ts::begin(ALICE);
    let mut sys = registered(&mut sc, false);

    sc.next_tx(ALICE);
    entry_wallet::withdraw_wal(&mut sys, DEPOSIT, sc.ctx());

    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::wallet::ENoBalance)]
fun a_wallet_with_no_bank_cannot_be_emptied() {
    let mut sc = ts::begin(ALICE);
    let mut sys = registered(&mut sc, false);

    sc.next_tx(ALICE);
    entry_wallet::withdraw_all_wal(&mut sys, sc.ctx());

    ts::return_shared(sys);
    sc.end();
}

#[test]
/// The first grant attaches the table, and the bits land where a reader looks.
fun the_first_grant_attaches_the_table() {
    let mut sc = ts::begin(ALICE);
    let mut sys = registered(&mut sc, false);

    sc.next_tx(ALICE);
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, true, false, true, sc.ctx());

    let alice = user::get_user(&sys, ALICE);
    assert!(permission::has_delegation_table(alice.uid()), 0);
    assert!(permission::has_delegate(alice.uid(), BOB), 1);

    let (add, file, pass, db, compact) = permission::delegate_bits(alice.uid(), BOB);
    assert!(add && !file && pass && !db && compact, 2);
    assert!(user::grants_add_blob(alice, BOB), 3);
    assert!(event::events_by_type<PermissionGranted>().length() == 1, 4);

    ts::return_shared(sys);
    sc.end();
}

#[test]
#[expected_failure(abort_code = warlot::permission::ENotDelegated)]
/// A replacement cannot silently become a first grant, and an account with no
/// table has made no grant to replace.
fun replacing_a_grant_that_was_never_made_is_refused() {
    let mut sc = ts::begin(ALICE);
    let mut sys = registered(&mut sc, false);

    sc.next_tx(ALICE);
    entry_permission::replace_grant(&mut sys, ALICE, BOB, true, true, true, true, true, sc.ctx());

    ts::return_shared(sys);
    sc.end();
}

#[test]
/// Revoking from an account that holds no table is not an error, and still
/// announces ,  a revocation that can abort is one that can fail at the moment it
/// is most needed.
fun revoking_without_a_table_is_a_no_op() {
    let mut sc = ts::begin(ALICE);
    let mut sys = registered(&mut sc, false);

    sc.next_tx(ALICE);
    entry_permission::revoke(&mut sys, ALICE, BOB, sc.ctx());

    assert!(!permission::has_delegation_table(user::get_user(&sys, ALICE).uid()), 0);
    assert!(event::events_by_type<PermissionRevoked>().length() == 1, 1);

    ts::return_shared(sys);
    sc.end();
}
