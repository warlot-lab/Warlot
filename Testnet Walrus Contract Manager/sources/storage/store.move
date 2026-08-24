/// Attaches blob configs to a user and detaches them again, maintaining the epoch-set list.
module warlot::store;

// === Imports ===

use sui::{clock::Clock, dynamic_object_field as ofields, table::{Self, Table}};
use walrus::blob::{Self, Blob};
use warlot::{
    blob_config::{Self, BlobConfig},
    events,
    system_config::{Self, SystemConfig},
    tier,
    user::{Self, User},
};

// === Errors ===

#[error]
const EInvalidConfigId: vector<u8> = b"INVALID CONFIG ID";

// === View functions ===

/// The head of the blob-config list for `epoch_set`, if the user has one.
public(package) fun get_epoch_set_head(user: &User, epoch_set: u32): Option<ID> {
    let index = user::index(user);
    if (!table::contains(index, epoch_set)) {
        return option::none()
    };
    option::some(*table::borrow(index, epoch_set))
}

/// Mutable access to one of the user's blob configs.
public(package) fun get_blob_config_by_id(user: &mut User, blob_config_id: ID): &mut BlobConfig {
    ofields::borrow_mut<ID, BlobConfig>(user::uid_mut(user), blob_config_id)
}

/// Whether the user holds a config with this id.
public(package) fun check_blob_config_id(user: &User, blob_config_id: ID): bool {
    ofields::exists_<ID>(user::uid(user), blob_config_id)
}

// === Package functions ===

/// Prepend `blob_cfg` to the user's list for `epoch`, and attach it to the user.
public(package) fun add_blob(
    user: &mut User,
    mut blob_cfg: BlobConfig,
    epoch: u32,
    ctx: &TxContext,
): ID {
    if (ctx.sender() != user::owner(user)) {
        user::check_permission_add_blob(user, ctx);
    };

    let blob_cfg_id = blob_config::config_id(&blob_cfg);

    if (user::index(user).contains<u32, ID>(epoch)) {
        let old_head_id = *user::index(user).borrow<u32, ID>(epoch);

        blob_config::set_next(&mut blob_cfg, old_head_id);

        ofields::borrow_mut<ID, BlobConfig>(user::uid_mut(user), old_head_id)
            .set_next(blob_cfg_id);

        *table::borrow_mut<u32, ID>(user::index_mut(user), epoch) = blob_cfg_id;
    } else {
        user::index_mut(user).add<u32, ID>(epoch, blob_cfg_id)
    };

    // Every config lives in the user's dynamic fields regardless of its epoch set.
    // Renewal and sync walk the list rather than these fields.
    ofields::add<ID, BlobConfig>(user::uid_mut(user), blob_cfg_id, blob_cfg);

    blob_cfg_id
}

/// Detach a config from the user and repair the list around it.
public(package) fun remove_blob_cfg_from_user(user: &mut User, blob_cfg_id: ID): BlobConfig {
    assert!(ofields::exists_(user::uid(user), blob_cfg_id), EInvalidConfigId);
    let blob_cfg = ofields::remove<ID, BlobConfig>(user::uid_mut(user), blob_cfg_id);

    let pre = blob_cfg.pre();
    let next = blob_cfg.next();
    let epoch_set = blob_cfg.epoch_set();

    // Repair the forward link, pre -> next.
    if (option::is_some(pre)) {
        let pre_id = *option::borrow(pre);
        if (option::is_some(next)) {
            ofields::borrow_mut<ID, BlobConfig>(user::uid_mut(user), pre_id)
                .set_next(*option::borrow(next));
        } else {
            ofields::borrow_mut<ID, BlobConfig>(user::uid_mut(user), pre_id)
                .set_next_none();
        }
    };

    // Repair the backward link, next -> pre.
    if (option::is_some(next)) {
        let next_id = *option::borrow(next);
        if (option::is_some(pre)) {
            ofields::borrow_mut<ID, BlobConfig>(user::uid_mut(user), next_id)
                .set_pre(*option::borrow(pre));
        } else {
            // The head is being removed, so the index must point at `next`.
            ofields::borrow_mut<ID, BlobConfig>(user::uid_mut(user), next_id)
                .set_pre_none();

            *table::borrow_mut(user::index_mut(user), epoch_set) = next_id;
        }
    } else {
        if (option::is_none(pre)) {
            // Neither neighbour: this was the only node, so the index entry goes.
            table::remove(user::index_mut(user), epoch_set);
        }
        // A tail node leaves the index alone, since the index names the head.
    };

    user::reduce_dash_data(user, blob_config::blob_cfg_size(&blob_cfg) as u128);
    blob_cfg
}

/// Wrap `blobs` in a config, attach it to `user`, and return the config's id.
public(package) fun raw_store_blob(
    system_cfg: &mut SystemConfig,
    blobs: vector<Blob>,
    file_size: u64,
    epoch_set: u32,
    cycle_limit: u64,
    fileMeta_id: Option<ID>,
    user: address,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let set = epoch_set;

    let blob_setting: BlobConfig = blob_config::new_config_blob(
        blobs,
        set,
        option::some(cycle_limit),
        fileMeta_id,
        clock,
        ctx,
    );

    let user = user::get_user_mut(system_cfg, user);

    let config_obj_id = add_blob(user, blob_setting, set, ctx);
    user::update_dash_data(user, 1, file_size as u128);
    system_config::increase_managed_blobs(system_cfg);

    config_obj_id
}

/// Measure `raw_blobs`, announce the store, and take them into custody under `user`.
public(package) fun store_blob_internal(
    system_cfg: &mut SystemConfig,
    raw_blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    fileMeta_id: Option<ID>,
    user: address,
    clock: &Clock,
    ctx: &mut TxContext,
): (ID, u64) {
    let set = tier::get_set(epoch_set);

    let mut size = 0;
    let mut storage_size = 0;
    let mut end_epoch = blob::end_epoch(&raw_blobs[0]);

    let mut raw_blobs_id = vector::empty<ID>();

    raw_blobs.do_ref!(|blob_x| {
        size = size + blob::size(blob_x);
        storage_size = storage_size + blob::storage(blob_x).size();
        raw_blobs_id.push_back(blob::object_id(blob_x));
        if (end_epoch > blob::end_epoch(blob_x)) {
            end_epoch = blob::end_epoch(blob_x)
        };
    });

    events::emit_warlot_file_store(
        user,
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
        size,
        set,
        cycle_end,
        fileMeta_id,
        user,
        clock,
        ctx,
    );

    (config_id, size)
}

/// Detach a config from `user` and return the blobs it held.
public(package) fun withdraw_blob(
    system_cfg: &mut SystemConfig,
    blob_obj_id: address,
    user: address,
): vector<Blob> {
    let user_ref = user::get_user_mut(system_cfg, user);
    let raw_blob = remove_blob_cfg_from_user(user_ref, object::id_from_address(blob_obj_id))
        .withdraw_and_burn();

    system_config::decrease_managed_blobs(system_cfg);
    events::emit_withdraw_blob(user, object::id_from_address(blob_obj_id));

    raw_blob
}
