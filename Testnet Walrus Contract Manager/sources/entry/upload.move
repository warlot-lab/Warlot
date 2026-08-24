/// Adopts externally-sourced blobs into the protocol's renewal management.
module warlot::entry_upload;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::{Self, Blob};
use warlot::{
    events,
    foreign_meta::{Self, ForeignMeta},
    registry::Registry,
    store,
    system_config::SystemConfig,
    tier,
};

// === Public functions ===

/// Take `blobs` sourced outside the protocol into custody under the registry's
/// owner, one config per blob, and index them in the user's foreign meta.
public fun foreign_blob_add(
    registry: &Registry,
    system_cfg: &SystemConfig,
    user_foreign_meta: &mut ForeignMeta,
    cycle_end: u64,
    epoch_set: u32,
    blobs: vector<Blob>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let set = tier::get_set(epoch_set);

    let mut temp_list = vector::empty<Blob>();
    temp_list.append(blobs);

    let mut meta_peak = foreign_meta::verify_peak(user_foreign_meta);
    let avg_len = foreign_meta::avg_len();

    let mut config_list: vector<ID> = vector::empty<ID>();

    while (!temp_list.is_empty()) {
        let raw_blob = temp_list.pop_back();

        events::emit_managed_blobs(
            registry.get_user(),
            blob::object_id(&raw_blob),
            blob::size(&raw_blob),
            blob::storage(&raw_blob).size(),
            blob::end_epoch(&raw_blob),
            set,
            cycle_end,
        );

        vector::push_back(
            &mut config_list,
            store::raw_store_blob(
                system_cfg,
                vector::singleton(raw_blob),
                set,
                cycle_end,
                option::none(),
                registry.get_user(),
                clock,
                ctx,
            ),
        );

        meta_peak = meta_peak + 1;

        if (meta_peak == avg_len) {
            foreign_meta::add_foreign_blob(user_foreign_meta, config_list);
            config_list = vector::empty<ID>();
            meta_peak = 0;
        }
    };
    foreign_meta::add_foreign_blob(user_foreign_meta, config_list);

    temp_list.destroy_empty()
}
