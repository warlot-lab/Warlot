/// Custody on a `BlobConfig` decides who may withdraw the blobs under it, so a
/// config arriving is a responsibility as much as a gift. Moving it one-sidedly
/// would let anybody make anybody else the holder of content they never asked
/// for, which is why the move is two acts and not one.
///
/// The required accept is what closes that, and it closes it by construction.
/// There is no inbound policy, no quota and no byte budget here because none of
/// them are needed once the recipient has to act, and every path that looked as
/// though it would need one turned out not to: a direct operator write is born
/// owned by the file's owner and transfers nothing, a draft merge is the owner's
/// own act, and a rejected draft stays with the writer who pushed it.
#[test_only]
module warlot::custody_transfer_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{clock, coin::Coin, event, test_scenario as ts};
use wal::wal::WAL;
use walrus::{blob::Blob, system::System};
use warlot::{
    blob_config::{Self, BlobConfig},
    entry_file_access,
    entry_file_draft,
    entry_file_write,
    entry_permission,
    entry_register,
    entry_renew,
    entry_transfer,
    entry_withdraw,
    fixtures,
    inner_file::InnerFile,
    storage_events::{Self, BlobConfigOwnershipAccepted, BlobConfigOwnershipOffered,
        BlobConfigOwnershipOfferCancelled},
    system_config::{Self, SystemConfig},
    writer_pass::WriterPass,
};

// === Constants ===

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const CAROL: address = @0xCA401;
const MALLORY: address = @0xBAD;
/// An address the system has never seen.
const STRANGER: address = @0x57A;

const SET: u32 = 13;
const CYCLES: u64 = 2;
const START_EPOCHS: u32 = 5;
const PASS_EXPIRY_MS: u64 = 5_000;

// === The handover works ===

#[test]
fun an_accepted_offer_moves_custody_and_the_new_owner_can_withdraw() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());

    // The offer alone moves nothing. This is the whole point of the two acts.
    assert!(blob_config::owner(&config) == ALICE, 0);
    assert!(blob_config::pending_owner(&config) == option::some(BOB), 1);

    let offered = event::events_by_type<BlobConfigOwnershipOffered>();
    assert!(offered.length() == 1, 2);
    let (_system_id, announced_config, owner, recipient) =
        storage_events::read_blob_config_ownership_offered(&offered[0]);
    assert!(announced_config == config_id, 3);
    assert!(owner == ALICE, 4);
    assert!(recipient == BOB, 5);

    sc.next_tx(BOB);
    entry_transfer::accept(&sys, &mut config, sc.ctx());

    assert!(blob_config::owner(&config) == BOB, 6);
    assert!(blob_config::pending_owner(&config).is_none(), 7);

    // The accepted event says why custody moved, which BlobConfigOwnerChanged
    // cannot: a draft merge re-parents a config on a path nobody offered on.
    let accepted = event::events_by_type<BlobConfigOwnershipAccepted>();
    assert!(accepted.length() == 1, 8);
    let (_system_id, _config, previous_owner, new_owner) =
        storage_events::read_blob_config_ownership_accepted(&accepted[0]);
    assert!(previous_owner == ALICE, 9);
    assert!(new_owner == BOB, 10);

    // Taking it up is not a claim about custody but the thing itself: the blob
    // comes out into Bob's account and nowhere else.
    sc.next_tx(BOB);
    entry_withdraw::self_withdraw_blob(&sys, config, sc.ctx());

    sc.next_tx(BOB);
    let returned = ts::ids_for_sender<Blob>(&sc);
    assert!(returned.length() == 1, 11);
    returned.do_ref!(|id| destroy(ts::take_from_sender_by_id<Blob>(&sc, *id)));

    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENotOwner)]
fun the_previous_owner_can_no_longer_withdraw() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());

    sc.next_tx(BOB);
    entry_transfer::accept(&sys, &mut config, sc.ctx());

    sc.next_tx(ALICE);
    entry_withdraw::self_withdraw_blob(&sys, config, sc.ctx());

    finish(sys, wsys, funds, clk, sc);
}

// === Only the named recipient completes it ===

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENotTheOfferedRecipient)]
fun an_address_the_offer_did_not_name_cannot_accept() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());

    // The config is shared, so Mallory can reach it; the offer is what stops her.
    sc.next_tx(MALLORY);
    entry_transfer::accept(&sys, &mut config, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENoStandingOffer)]
fun a_config_with_no_offer_cannot_be_accepted() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(BOB);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::accept(&sys, &mut config, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::entry_transfer::ENotRegistered)]
fun an_unregistered_address_cannot_accept() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, STRANGER, sc.ctx());

    // Every path that creates a config puts it under a registered address, and
    // this is the only path that moves one. An unregistered owner would hold
    // content compaction could not touch, because the permission it consults
    // lives on an account object that does not exist.
    sc.next_tx(STRANGER);
    entry_transfer::accept(&sys, &mut config, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

// === Only the owner offers, and only the owner withdraws the offer ===

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENotOwner)]
fun a_stranger_cannot_offer_someone_elses_config() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(MALLORY);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, MALLORY, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENotOwner)]
fun a_stranger_cannot_cancel_an_offer() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());

    sc.next_tx(MALLORY);
    entry_transfer::cancel(&sys, &mut config, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::EOfferToSelf)]
fun a_config_cannot_be_offered_to_its_own_owner() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);

    // Refused rather than treated as a no-op. Accepting it would raise a custody
    // change in which nothing changed hands.
    entry_transfer::offer(&sys, &mut config, ALICE, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

// === Cancelling and replacing ===

#[test]
fun cancel_clears_the_offer_and_announces_it() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());

    sc.next_tx(ALICE);
    entry_transfer::cancel(&sys, &mut config, sc.ctx());

    assert!(blob_config::pending_owner(&config).is_none(), 0);
    assert!(blob_config::owner(&config) == ALICE, 1);

    let cancelled = event::events_by_type<BlobConfigOwnershipOfferCancelled>();
    assert!(cancelled.length() == 1, 2);
    let (_system_id, announced_config, owner, recipient) =
        storage_events::read_blob_config_ownership_offer_cancelled(&cancelled[0]);
    assert!(announced_config == config_id, 3);
    assert!(owner == ALICE, 4);
    assert!(recipient == BOB, 5);

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENoStandingOffer)]
fun accepting_a_cancelled_offer_is_refused() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());

    sc.next_tx(ALICE);
    entry_transfer::cancel(&sys, &mut config, sc.ctx());

    sc.next_tx(BOB);
    entry_transfer::accept(&sys, &mut config, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENoStandingOffer)]
fun cancelling_a_config_with_no_offer_is_refused() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    // The owner is acting on a belief about the config's state. A no-op would
    // confirm a belief that may be wrong.
    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::cancel(&sys, &mut config, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
fun a_second_offer_replaces_the_first() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());
    entry_transfer::offer(&sys, &mut config, CAROL, sc.ctx());

    // There is one custody to hand over, so a queue of candidates would be a
    // queue in which only the first to act mattered.
    assert!(blob_config::pending_owner(&config) == option::some(CAROL), 0);

    let offered = event::events_by_type<BlobConfigOwnershipOffered>();
    assert!(offered.length() == 2, 1);

    sc.next_tx(CAROL);
    entry_transfer::accept(&sys, &mut config, sc.ctx());
    assert!(blob_config::owner(&config) == CAROL, 2);

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

#[test]
#[expected_failure(abort_code = warlot::blob_config::ENotTheOfferedRecipient)]
fun the_replaced_recipient_cannot_still_accept() {
    let mut sc = ts::begin(ALICE);
    let (sys, wsys, funds, clk, config_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let mut config = ts::take_shared_by_id<BlobConfig>(&sc, config_id);
    entry_transfer::offer(&sys, &mut config, BOB, sc.ctx());
    entry_transfer::offer(&sys, &mut config, CAROL, sc.ctx());

    sc.next_tx(BOB);
    entry_transfer::accept(&sys, &mut config, sc.ctx());

    ts::return_shared(config);
    finish(sys, wsys, funds, clk, sc);
}

// === An offer is about the custody standing when it was made ===

#[test]
fun custody_moving_by_another_route_voids_a_standing_offer() {
    let mut sc = ts::begin(ALICE);
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());
    let file_id = fixtures::inner_file(
        &mut wsys,
        &mut sys,
        ALICE,
        b"alice",
        fixtures::commit_for(b"first"),
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let mut file = ts::take_shared_by_id<InnerFile>(&sc, file_id);
    let owner_pass = sc.take_from_sender<WriterPass>();
    entry_permission::grant(&mut sys, ALICE, BOB, true, false, false, false, false, false, sc.ctx());
    entry_file_access::create_pass(&sys, &file, BOB, PASS_EXPIRY_MS, false, &clk, sc.ctx());

    sc.next_tx(BOB);
    let bob_pass = sc.take_from_sender<WriterPass>();
    let raw_blob = fixtures::certified_blob(
        &mut wsys,
        fixtures::blob_size(),
        fixtures::blob_epochs_ahead(),
        &mut funds,
        sc.ctx(),
    );
    entry_file_write::write_(
        &mut file,
        &bob_pass,
        true,
        option::none(),
        &clk,
        &sys,
        vector[raw_blob],
        fixtures::commit_for(b"a proposal"),
        vector[],
        sc.ctx(),
    );

    // The draft's content is Bob's while it is only a proposal, so Bob may offer
    // it. Mallory is a stranger to the file and to Alice.
    sc.next_tx(BOB);
    let draft_config_id = ts::most_recent_id_shared<BlobConfig>().destroy_some();
    let mut draft_config = ts::take_shared_by_id<BlobConfig>(&sc, draft_config_id);
    entry_transfer::offer(&sys, &mut draft_config, MALLORY, sc.ctx());

    sc.next_tx(ALICE);
    entry_file_draft::merge_draft_into_file(
        &sys,
        &mut file,
        &owner_pass,
        &mut draft_config,
        0,
        true,
        vector[],
        &clk,
        sc.ctx(),
    );

    // Merging re-parents the config to the file's owner. Bob's offer does not
    // survive that: left standing it would let Mallory take the content out of
    // Alice's own history, which is not something Alice ever agreed to.
    assert!(blob_config::owner(&draft_config) == ALICE, 0);
    assert!(blob_config::pending_owner(&draft_config).is_none(), 1);

    let cancelled = event::events_by_type<BlobConfigOwnershipOfferCancelled>();
    assert!(cancelled.length() == 1, 2);
    let (_system_id, announced_config, owner, recipient) =
        storage_events::read_blob_config_ownership_offer_cancelled(&cancelled[0]);
    assert!(announced_config == draft_config_id, 3);
    assert!(owner == BOB, 4);
    assert!(recipient == MALLORY, 5);

    // And the void is not reported as an accept, so a consumer tells the two
    // apart by what accompanies the row.
    assert!(event::events_by_type<BlobConfigOwnershipAccepted>().length() == 0, 6);

    destroy(bob_pass);
    destroy(owner_pass);
    ts::return_shared(draft_config);
    ts::return_shared(file);
    finish(sys, wsys, funds, clk, sc);
}

// === A standing offer changes nothing else ===

#[test]
fun renewal_is_unchanged_by_a_standing_offer() {
    let mut sc = ts::begin(ALICE);
    let (sys, mut wsys, mut funds, clk, offered_id) = world(&mut sc);

    sc.next_tx(ALICE);
    let plain_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        SET,
        option::some(CYCLES),
        START_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    sc.next_tx(ALICE);
    let mut offered = ts::take_shared_by_id<BlobConfig>(&sc, offered_id);
    let mut plain = ts::take_shared_by_id<BlobConfig>(&sc, plain_id);
    entry_transfer::offer(&sys, &mut offered, BOB, sc.ctx());

    // Renewal is permissionless and addresses the config, not its owner, so a
    // pending recipient is not a party to it either way.
    sc.next_tx(CAROL);
    entry_renew::renew_blob(&sys, &mut wsys, &mut offered, &mut funds, sc.ctx());
    entry_renew::renew_blob(&sys, &mut wsys, &mut plain, &mut funds, sc.ctx());

    assert!(blob_config::cycle_limit(&offered) == blob_config::cycle_limit(&plain), 0);
    assert!(blob_config::epoch_set(&offered) == blob_config::epoch_set(&plain), 1);

    // The mandate is spent identically, and the offer is still standing after.
    assert!(blob_config::cycle_limit(&offered) == option::some(CYCLES - 1), 2);
    assert!(blob_config::pending_owner(&offered) == option::some(BOB), 3);
    assert!(blob_config::owner(&offered) == ALICE, 4);

    ts::return_shared(plain);
    ts::return_shared(offered);
    finish(sys, wsys, funds, clk, sc);
}

// === Private functions ===

/// Alice, Bob, Carol and Mallory registered, and one config Alice owns.
fun world(sc: &mut ts::Scenario): (SystemConfig, System, Coin<WAL>, clock::Clock, ID) {
    system_config::init_for_testing(sc.ctx());

    sc.next_tx(ALICE);
    let mut wsys = fixtures::walrus_system(sc.ctx());

    sc.next_tx(ALICE);
    let mut sys = sc.take_shared<SystemConfig>();
    let clk = clock::create_for_testing(sc.ctx());
    let mut funds = fixtures::wal(sc.ctx());

    entry_register::all_register_user_publicly(&mut sys, b"alice".to_string(), &clk, sc.ctx());

    sc.next_tx(BOB);
    entry_register::all_register_user_publicly(&mut sys, b"bob".to_string(), &clk, sc.ctx());

    sc.next_tx(CAROL);
    entry_register::all_register_user_publicly(&mut sys, b"carol".to_string(), &clk, sc.ctx());

    // Registered, so that a refusal aimed at her lands on the rule under test
    // rather than on the account check `accept` makes first.
    sc.next_tx(MALLORY);
    entry_register::all_register_user_publicly(&mut sys, b"mallory".to_string(), &clk, sc.ctx());

    sc.next_tx(ALICE);
    let config_id = fixtures::shared_config(
        &mut wsys,
        object::id(&sys),
        ALICE,
        SET,
        option::some(CYCLES),
        START_EPOCHS,
        &mut funds,
        &clk,
        sc.ctx(),
    );

    (sys, wsys, funds, clk, config_id)
}

fun finish(
    sys: SystemConfig,
    wsys: System,
    funds: Coin<WAL>,
    clk: clock::Clock,
    sc: ts::Scenario,
) {
    destroy(funds);
    destroy(wsys);
    clock::destroy_for_testing(clk);
    ts::return_shared(sys);
    sc.end();
}
