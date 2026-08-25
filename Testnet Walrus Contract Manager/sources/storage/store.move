/// Takes blobs into custody, one shared blob config per store.
module warlot::store;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::{Self, Blob};
use warlot::{blob_config, events, system_config::SystemConfig, tier, user};

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
public(package) fun raw_store_blob(
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_limit: u64,
    fileMeta_id: Option<ID>,
    owner: address,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    user::check_permission_add_blob(user::get_user(system_cfg, owner), ctx);

    let blob_setting = blob_config::new(
        owner,
        blobs,
        epoch_set,
        option::some(cycle_limit),
        fileMeta_id,
        clock,
        ctx,
    );

    let config_obj_id = blob_config::config_id(&blob_setting);

    blob_config::share(blob_setting);

    config_obj_id
}

/// Measure `raw_blobs`, announce the store, and take them into custody under `owner`.
public(package) fun store_blob_internal(
    system_cfg: &SystemConfig,
    raw_blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    fileMeta_id: Option<ID>,
    owner: address,
    clock: &Clock,
    ctx: &mut TxContext,
): (ID, u64) {
    assert!(!raw_blobs.is_empty(), ENoBlobs);

    let set = tier::validate(system_cfg, epoch_set);

    let mut size = 0;
    let mut storage_size = 0;
    let mut end_epoch = blob::end_epoch(&raw_blobs[0]);

    let mut raw_blobs_id = vector<ID>[];

    // Bounded by the blobs the caller handed in, which the transaction carrying
    // them already bounds.
    raw_blobs.do_ref!(|blob_x| {
        size = size + blob::size(blob_x);
        storage_size = storage_size + blob::storage(blob_x).size();
        raw_blobs_id.push_back(blob::object_id(blob_x));
        if (end_epoch > blob::end_epoch(blob_x)) {
            end_epoch = blob::end_epoch(blob_x)
        };
    });

    events::emit_warlot_file_store(
        owner,
        raw_blobs_id,
        size,
        storage_size,
        end_epoch,
        set,
        cycle_end,
    );

    let config_id = raw_store_blob(
        system_cfg,
        raw_blobs,
        set,
        cycle_end,
        fileMeta_id,
        owner,
        clock,
        ctx,
    );

    (config_id, size)
}
