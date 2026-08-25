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

// === Errors ===

#[error]
const ERegistryForAnotherSystem: vector<u8> = b"THIS REGISTRY BELONGS TO A DIFFERENT SYSTEM";
#[error]
const EBatchTooLarge: vector<u8> = b"TOO MANY BLOBS FOR ONE ADOPTION";

// === Constants ===

/// The largest number of blobs one adoption may carry.
///
/// Each blob costs a shared object created and an event emitted, so the call's
/// gas grows linearly and would otherwise be bounded only by the gas budget ,
/// which is to say, bounded by failing. The cap also keeps a single call well
/// short of the point where the index vector it appends to could overflow a Sui
/// object on its own. Conservative until the per-blob cost is measured on a live
/// network.
const MAX_ADOPTION_BATCH: u64 = 100;

// === Public functions ===

/// Take `blobs` sourced outside the protocol into custody under the registry's
/// owner, one config per blob, and index them in the user's foreign meta.
public fun foreign_blob_add(
    registry: &Registry,
    system_cfg: &SystemConfig,
    user_foreign_meta: &mut ForeignMeta,
    cycle_end: u64,
    epoch_set: u32,
    mut blobs: vector<Blob>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    // A registry names the system it belongs to, so a call that pairs one with a
    // different system is asking two objects that know nothing about each other
    // to agree on who the user is.
    assert!(registry.get_system() == object::id(system_cfg), ERegistryForAnotherSystem);
    assert!(blobs.length() <= MAX_ADOPTION_BATCH, EBatchTooLarge);

    let set = tier::validate(system_cfg, epoch_set);

    let mut meta_peak = foreign_meta::verify_peak(user_foreign_meta);
    let avg_len = foreign_meta::avg_len();

    let mut config_list: vector<ID> = vector::empty<ID>();

    // Bounded by `MAX_ADOPTION_BATCH`.
    while (!blobs.is_empty()) {
        let raw_blob = blobs.pop_back();

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

    blobs.destroy_empty()
}
