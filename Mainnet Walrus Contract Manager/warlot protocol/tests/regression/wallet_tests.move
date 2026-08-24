/// WAL deposited into a user's internal wallet has a way back out. The deposit and
/// the withdrawal are the same amount, the wallet is empty afterwards, and the coin
/// lands in the depositor's account.
#[test_only]
module warlot::wallet_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, coin::{Self, Coin}, test_scenario as ts};
use wal::wal::WAL;
use warlot::{
    entry_register,
    entry_wallet,
    system_config::{Self, SystemConfig},
    user,
    wallet,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const FUNDED: u64 = 5_000;
const DEPOSIT: u64 = 3_000;

// === Test-only helpers ===

#[test]
fun a_deposit_can_be_withdrawn_in_full() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = coin::mint_for_testing<WAL>(FUNDED, sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    let balance = entry_wallet::deposit_coin(&mut sys, &mut funds, DEPOSIT, sc.ctx());
    assert!(balance == DEPOSIT, 0);
    assert!(funds.value() == FUNDED - DEPOSIT, 1);

    entry_wallet::withdraw_wal(&mut sys, DEPOSIT, sc.ctx());

    let emptied = wallet::get_balance<WAL>(user::get_user_mut(&mut sys, ALICE).get_wallet());
    assert!(emptied == 0, 2);

    // The withdrawal is handed back as a coin in Alice's own account.
    sc.next_tx(ALICE);
    let returned = sc.take_from_sender<Coin<WAL>>();
    assert!(returned.value() == DEPOSIT, 3);

    destroy(returned);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun withdraw_all_empties_the_wallet() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = coin::mint_for_testing<WAL>(FUNDED, sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());
    entry_wallet::deposit_coin(&mut sys, &mut funds, FUNDED, sc.ctx());

    entry_wallet::withdraw_all_wal(&mut sys, sc.ctx());

    let emptied = wallet::get_balance<WAL>(user::get_user_mut(&mut sys, ALICE).get_wallet());
    assert!(emptied == 0, 0);

    sc.next_tx(ALICE);
    let returned = sc.take_from_sender<Coin<WAL>>();
    assert!(returned.value() == FUNDED, 1);

    destroy(returned);
    destroy(funds);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
