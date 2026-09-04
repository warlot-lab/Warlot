/// Takes blobs into custody, one shared blob config per store.
module warlot::store;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::{Self, Blob};
use warlot::{blob_config, operator::OperatorAuth, system_config::SystemConfig, user};

// === Errors ===

#[error]
const ENoBlobs: vector<u8> = b"A STORE MUST CARRY AT LEAST ONE BLOB";

// === Package functions ===

/// Wrap `blobs` in a config owned by `owner`, publish it, and return its id.
///
/// `system_cfg` is read and never written. The only thing it supplies is the
/// delegation table that decides whether a sender other than `owner` may store on
/// their behalf; custody itself lives on the config, so an upload changes no state
/// shared with any other user.
///
/// `operator` carries the proof that the sender presented a live operator
/// credential, and is `none` wherever none was offered. It is threaded down here
/// rather than resolved here because the capability is an argument to the entry
/// point, and `Option<&AdminCap>` is not a type Move will accept.
public(package) fun raw_store_blob(
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    owner: address,
    operator: Option<OperatorAuth>,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    user::check_permission_add_blob(user::get_user(system_cfg, owner), operator, ctx);

    let blob_setting = blob_config::new(
        object::id(system_cfg),
        owner,
        blobs,
        epoch_set,
        cycle_limit,
        clock,
        ctx,
    );

    let config_obj_id = blob_config::config_id(&blob_setting);

    blob_config::share(blob_setting);

    config_obj_id
}

/// Measure `raw_blobs` and take them into custody under `owner`.
///
/// **`epoch_set` arrives already validated, and this function does not re-check
/// it.** The two places that do are `upload::adopt` and `creation::new_file` ,
/// the funnels every path that *buys* a term passes through. A caller added later
/// that reaches here without going through one of them would store on a term the
/// system does not sell, and nothing here would stop it.
///
/// It is written this way because the alternative was worse. Validating on every
/// store put the check on the revision path too, where the term is the file's own,
/// fixed at creation with no setter; retuning the tier table then froze every
/// existing file bought on a dropped term, permanently, with no action available
/// to its owner. `tier::validate` exists to refuse a caller *buying* a term the
/// system does not sell, and a revision is not a purchase ,  it is the system
/// honouring a term it already sold.
///
/// `tier_tests::a_dropped_term_freezes_no_file` pins both halves of that, so a
/// later change that puts the check back on the write path, or takes it off a
/// buying path, fails there rather than in production.
public(package) fun store_blob_internal(
    system_cfg: &SystemConfig,
    raw_blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: Option<u64>,
    owner: address,
    operator: Option<OperatorAuth>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ID, u64) {
    assert!(!raw_blobs.is_empty(), ENoBlobs);

    let mut size = 0;

    // Bounded by the blobs the caller handed in, which the transaction carrying
    // them already bounds. The store itself is announced from `blob_config::new`,
    // where the config's id exists; this total is what the caller is handed back.
    raw_blobs.do_ref!(|blob_x| size = size + blob::size(blob_x));

    let config_id = raw_store_blob(
        system_cfg,
        raw_blobs,
        epoch_set,
        cycle_end,
        owner,
        operator,
        clock,
        ctx,
    );

    (config_id, size)
}
