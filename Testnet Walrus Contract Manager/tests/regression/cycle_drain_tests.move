/// C-5: a renewal cycle is burned before any work is attempted, so a caller who
/// asks for zero epochs ahead spends nothing and still exhausts the mandate.
/// The caller needs no capability and no permission entry.
#[test_only]
module warlot::cycle_drain_tests;

// === Imports ===

use sui::{clock, coin, test_scenario as ts, test_utils};
use wal::wal::WAL;
use warlot::{
    blob_config,
    entry_register,
    entry_renew,
    fixtures,
    renew,
    store,
    system_config::{Self, SystemConfig},
    user,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const MALLORY: address = @0xBAD;
const SET: u32 = 13;

// === Test-only helpers ===

#[test]
fun renew_burns_cycles_without_doing_work() {
    let mut sc = ts::begin(ALICE);
    let ctx = sc.ctx();
    let clk = clock::create_for_testing(ctx);
    let mut wsys = fixtures::walrus_system(ctx);
    let mut funds = fixtures::wal(ctx);
    let mut zero_payment = coin::zero<WAL>(ctx);

    // One blob paid well past the target, with a budget of three renewal cycles.
    let blob = fixtures::blob(&mut wsys, 1024, 10, &mut funds, ctx);
    let mut cfg = blob_config::new_config_blob(
        vector[blob],
        SET,
        option::some(3),
        option::none(),
        &clk,
        ctx,
    );

    assert!(cfg.cycle_limit().borrow() == 3, 0);

    // Three free calls asking for zero epochs ahead: nothing is extended, and
    // the budget is gone.
    renew::renew_blob_cfg(&mut cfg, &mut wsys, 0, &mut zero_payment);
    renew::renew_blob_cfg(&mut cfg, &mut wsys, 0, &mut zero_payment);
    renew::renew_blob_cfg(&mut cfg, &mut wsys, 0, &mut zero_payment);

    assert!(cfg.cycle_limit().borrow() == 0, 1);
    assert!(zero_payment.value() == 0, 2); // the caller spent no WAL at all

    zero_payment.destroy_zero();
    test_utils::destroy(funds);
    test_utils::destroy(wsys);
    test_utils::destroy(cfg);
    clock::destroy_for_testing(clk);
    sc.end();
}

#[test]
fun anyone_can_drain_another_users_renewal_budget() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    // Build the Walrus side first: `system::new_for_testing` leaves the ambient
    // transaction context with its own sender, which the next transaction resets.
    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let blob = fixtures::blob(&mut wsys, 1024, 10, &mut funds, sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    entry_register::all_register_user_publicly(
        &mut sys,
        b"alice".to_string(),
        &clk,
        sc.ctx(),
    );

    // Alice stores one blob with a budget of two renewal cycles.
    let (cfg_id, _) = store::store_blob_internal(
        &mut sys,
        vector[blob],
        SET,
        2,
        option::none(),
        ALICE,
        &clk,
        sc.ctx(),
    );

    // Mallory takes over. She is not Alice, holds no capability, and has no
    // permission entry.
    sc.next_tx(MALLORY);

    let mut i = 0;
    while (i < 2) {
        let est = renew::create_estimate(0, coin::zero<WAL>(sc.ctx()));
        entry_renew::renew_specific_blob(&mut sys, &mut wsys, est, ALICE, cfg_id, 0, sc.ctx());
        i = i + 1;
    };

    // Alice's budget is now zero, so every future renewal returns early forever.
    let alice = user::get_user_mut(&mut sys, ALICE);
    assert!(store::get_blob_config_by_id(alice, cfg_id).cycle_limit().borrow() == 0, 0);

    test_utils::destroy(funds);
    test_utils::destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
