/// A storage term is either one the system sells or it is refused by name. The
/// previous implementation folded any number into whichever of three buckets it
/// fell nearest, so a caller asking for 30 epochs was sold 53 and billed for it,
/// with no error and no event to notice it by.
#[test_only]
module warlot::renew_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use warlot::{
    entry_register,
    entry_upload,
    fixtures,
    store,
    system_config::{Self, SystemConfig},
    tier
};

// === Constants ===

const ALICE: address = @0xA11CE;
/// A term that is not on the ladder, and that the previous implementation would
/// have quietly sold as the longest one.
const OFF_LADDER: u32 = 30;
const CYCLES: u64 = 2;
const START_EPOCHS: u32 = 5;
const BLOB_SIZE: u64 = 1_024;

// === Test-only helpers ===

#[test]
#[expected_failure(abort_code = warlot::tier::EInvalidTier)]
fun tier_rejected() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    let raw_blob = fixtures::certified_blob(&mut wsys, BLOB_SIZE, START_EPOCHS, &mut funds, sc.ctx());

    // 30 is not sold. The call fails; it does not come back as 52.
    //
    // Asked through the entry point rather than of `store_blob_internal`, which no
    // longer checks: the term is refused where it is bought, and adoption is one
    // of the two places that buys one.
    entry_upload::foreign_blob_add(
        &sys,
        ALICE,
        option::some(CYCLES),
        OFF_LADDER,
        vector[raw_blob],
        &clk,
        sc.ctx(),
    );

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}

#[test]
fun top_tier_reserve() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();

    let ladder = *sys.tier_table();
    let top = ladder[ladder.length() - 1];

    // The longest term registers one epoch above itself, so a blob on the term
    // where the most valuable data lives is never sitting on the storage ceiling
    // with no extension left.
    assert!(top == 52, 0);
    assert!(tier::registration_term(&sys, top) == 53, 1);
    assert!(tier::registration_term(&sys, top) <= sys.max_epochs_ahead(), 2);

    // Every shorter term registers at itself; they are already far below the
    // ceiling and a uniform margin would double the price of the shortest one.
    let mut i = 0;
    while (i < ladder.length() - 1) {
        assert!(tier::registration_term(&sys, ladder[i]) == ladder[i], 3);
        i = i + 1;
    };

    // And a term is returned exactly as asked for, never adjusted.
    assert!(tier::validate(&sys, 7) == 7, 4);
    assert!(!tier::is_tier(&sys, OFF_LADDER), 5);

    ts::return_shared(sys);
    sc.end();
}
