/// C-3a: removing a blob config aborts, because clearing the head's `pre` extracts
/// from an option that `add_blob` never fills. Withdrawal is dead for any user
/// holding two or more configs.
#[test_only]
module warlot::withdraw_tests;

// === Imports ===

use sui::{clock, test_scenario as ts, test_utils};
use warlot::{blob_config, store, user};

// === Constants ===

const ALICE: address = @0xA11CE;
const SET: u32 = 13;

// === Test-only helpers ===

#[test]
#[expected_failure]
fun remove_blob_cfg_aborts() {
    let mut sc = ts::begin(ALICE);
    let ctx = sc.ctx();
    let clk = clock::create_for_testing(ctx);

    let mut alice = user::create_user(
        b"alice".to_string(),
        object::id_from_address(@0x1),
        &clk,
        option::none(),
        ctx,
    );

    let a = store::add_blob(&mut alice, blob_config::create_dummy_config(SET, &clk, ctx), SET, ctx);
    let _b = store::add_blob(
        &mut alice,
        blob_config::create_dummy_config(SET, &clk, ctx),
        SET,
        ctx,
    );

    // `a` has a successor but no predecessor, so removal takes the head branch
    // and aborts extracting `pre`.
    let cfg = store::remove_blob_cfg_from_user(&mut alice, a);

    test_utils::destroy(cfg);
    clock::destroy_for_testing(clk);
    test_utils::destroy(alice);
    sc.end();
}
