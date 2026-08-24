/// C-1: the blob-config list `add_blob` builds is a 2-cycle, and `pre` is never
/// populated, so renewal traversal never terminates and the oldest config is
/// unreachable.
#[test_only]
module warlot::linked_list_tests;

// === Imports ===

use sui::{clock, test_scenario as ts, test_utils};
use warlot::{blob_config, store, user};

// === Constants ===

const ALICE: address = @0xA11CE;
const SET: u32 = 13;

// === Test-only helpers ===

#[test]
fun linked_list_is_cyclic_and_pre_is_never_set() {
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
    let b = store::add_blob(&mut alice, blob_config::create_dummy_config(SET, &clk, ctx), SET, ctx);
    let c = store::add_blob(&mut alice, blob_config::create_dummy_config(SET, &clk, ctx), SET, ctx);

    // `pre` is none on every node, so the list is not doubly linked at all.
    assert!(store::get_blob_config_by_id(&mut alice, a).pre().is_none(), 0);
    assert!(store::get_blob_config_by_id(&mut alice, b).pre().is_none(), 1);
    assert!(store::get_blob_config_by_id(&mut alice, c).pre().is_none(), 2);

    // The head is the newest node.
    assert!(store::get_epoch_set_head(&alice, SET).borrow() == c, 3);

    // `c.next == b` and `b.next == c`: a 2-cycle, with `a` unreachable.
    assert!(store::get_blob_config_by_id(&mut alice, c).next().borrow() == b, 4);
    assert!(store::get_blob_config_by_id(&mut alice, b).next().borrow() == c, 5);

    // Walk the list the way `renew::process_user_renewal` walks it.
    let mut cur = store::get_epoch_set_head(&alice, SET);
    let mut steps = 0u64;
    let mut saw_a = false;
    while (cur.is_some() && steps < 1000) {
        let id = *cur.borrow();
        if (id == a) saw_a = true;
        cur = *store::get_blob_config_by_id(&mut alice, id).next();
        steps = steps + 1;
    };
    assert!(steps == 1000, 6); // the loop never ended
    assert!(!saw_a, 7); // and the oldest config is never reached

    clock::destroy_for_testing(clk);
    test_utils::destroy(alice);
    sc.end();
}
