/// Renewal walks a caller-supplied batch of independent shared configs rather than
/// an ordering the contract maintains. There is no link field to make cyclic, the
/// batch terminates by construction, and every config in it is renewed exactly
/// once ,  none skipped, none charged twice.
#[test_only]
module warlot::linked_list_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, test_scenario as ts};
use walrus::blob;
use warlot::{
    blob_config::{Self, BlobConfig},
    entry_renew,
    fixtures,
    system_config::{Self, SystemConfig},
};

// === Constants ===

const ALICE: address = @0xA11CE;
/// An address with no relationship to Alice, to show the batch needs none.
const CARL: address = @0xCA71;
const SET: u32 = 13;
/// Where each blob's storage term starts, short of `SET` so renewal has work to do.
const START_EPOCHS: u32 = 5;
const CYCLES: u64 = 3;
const BATCH: u64 = 3;

// === Test-only helpers ===

#[test]
fun a_batch_renews_every_config_exactly_once() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    // `walrus::system::new_for_testing` carries its own transaction context, so the
    // ambient sender has to be restored before anything is attributed to Alice.
    sc.next_tx(ALICE);
    let sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    let mut ids = vector<ID>[];
    let mut i = 0;
    while (i < BATCH) {
        ids.push_back(
            fixtures::shared_config(
                &mut wsys,
                ALICE,
                SET,
                option::some(CYCLES),
                START_EPOCHS,
                &mut funds,
                &clk,
                sc.ctx(),
            ),
        );
        i = i + 1;
    };

    // One call per config within a single transaction, which is the shape a
    // programmable transaction block takes.
    sc.next_tx(CARL);
    ids.do_ref!(|id| {
        let mut config = ts::take_shared_by_id<BlobConfig>(&sc, *id);
        entry_renew::renew_blob(&sys, &mut wsys, &mut config, &mut funds);
        ts::return_shared(config);
    });

    sc.next_tx(ALICE);
    ids.do_ref!(|id| {
        let config = ts::take_shared_by_id<BlobConfig>(&sc, *id);

        // One cycle spent, not zero and not two.
        assert!(config.cycle_limit().borrow() == CYCLES - 1, 0);

        let blobs = blob_config::unwrap(config, sc.ctx());
        blobs.do_ref!(|renewed| assert!(blob::storage(renewed).end_epoch() == SET, 1));
        destroy(blobs);
    });

    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
