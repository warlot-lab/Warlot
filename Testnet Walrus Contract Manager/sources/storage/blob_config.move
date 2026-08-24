/// Owns `BlobConfig`: the object wrapping a user's blobs and carrying their renewal mandate.
module warlot::blob_config;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;

// === Structs ===

/// Every blob stored with Warlot is wrapped in a config that tells the renewal
/// system how to keep it alive.
public struct BlobConfig has key, store {
    id: UID,
    /// The blobs under this config's custody.
    blobs: vector<Blob>,
    /// How many epochs ahead the blobs are kept paid for.
    epoch_set: u32,
    /// How many renewal cycles remain; `none` for an indefinite mandate.
    cycle_limit: Option<u64>,
    /// The `FileMeta` naming this config, if one exists.
    fileMeta_id: Option<ID>,
    /// An address paying for renewal without owning the data, used by platforms
    /// that fund storage on a user's behalf.
    sponsor: Option<address>,
    /// Addresses sharing the cost of this config.
    share_payment: SharedPayment,
    uploaded_on: u64,
    /// This config's position in its owner's epoch-set list.
    index: Index,
}

/// Links a config to its neighbours in the owner's epoch-set list.
public struct Index has drop, store {
    pre: Option<ID>,
    next: Option<ID>,
}

/// The addresses sharing the cost of a config.
public struct SharedPayment has store, drop {
    assist: vector<address>,
}

// === Package functions ===

/// This config's object id.
public(package) fun config_id(blob_cfg: &BlobConfig): ID {
    object::id(blob_cfg)
}

/// Wrap `blobs` in a config carrying the given renewal mandate.
public(package) fun new_config_blob(
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    fileMeta_id: Option<ID>,
    clock: &Clock,
    ctx: &mut TxContext,
): BlobConfig {
    BlobConfig {
        id: object::new(ctx),
        blobs,
        epoch_set,
        cycle_limit,
        fileMeta_id,
        sponsor: option::none(),
        share_payment: SharedPayment { assist: vector::empty() },
        uploaded_on: clock.timestamp_ms(),
        index: Index {
            pre: option::none(),
            next: option::none(),
        },
    }
}

/// The config preceding this one in the epoch-set list.
public(package) fun pre(blob_cfg: &BlobConfig): &Option<ID> {
    &blob_cfg.index.pre
}

/// The config following this one in the epoch-set list.
public(package) fun next(blob_cfg: &BlobConfig): &Option<ID> {
    &blob_cfg.index.next
}

/// Set this config's predecessor, returning what it displaced.
public(package) fun set_pre(blob_cfg: &mut BlobConfig, pre: ID): Option<ID> {
    option::swap_or_fill(&mut blob_cfg.index.next, pre)
}

/// Set this config's successor, returning what it displaced.
public(package) fun set_next(blob_cfg: &mut BlobConfig, next: ID): Option<ID> {
    option::swap_or_fill(&mut blob_cfg.index.next, next)
}

/// Clear this config's predecessor, returning what it held.
public(package) fun set_pre_none(blob_cfg: &mut BlobConfig): ID {
    option::extract(&mut blob_cfg.index.pre)
}

/// Clear this config's successor, returning what it held.
public(package) fun set_next_none(blob_cfg: &mut BlobConfig): ID {
    option::extract(&mut blob_cfg.index.next)
}

/// Mutable access to the wrapped blobs.
public(package) fun blob(blob_cfg: &mut BlobConfig): &mut vector<Blob> {
    &mut blob_cfg.blobs
}

/// How many epochs ahead the blobs are kept paid for.
public(package) fun epoch_set(blob_cfg: &BlobConfig): u32 {
    blob_cfg.epoch_set
}

/// How many renewal cycles remain, or `none` for an indefinite mandate.
public(package) fun cycle_limit(blob_cfg: &BlobConfig): Option<u64> {
    if (option::is_none(&blob_cfg.cycle_limit)) {
        return option::none()
    };
    option::some(*option::borrow<u64>(&blob_cfg.cycle_limit))
}

/// Mutable access to the remaining renewal cycles.
public(package) fun cycle_limit_mut(blob_cfg: &mut BlobConfig): &mut Option<u64> {
    &mut blob_cfg.cycle_limit
}

/// Whether every wrapped blob is deletable.
public(package) fun is_deletable(blob_cfg: &BlobConfig): bool {
    let mut deletable = true;
    blob_cfg.blobs.do_ref!(|blob| {
        if (!blob.is_deletable()) {
            deletable = false;
            return
        }
    });

    return deletable
}

/// The total unencoded size of the wrapped blobs.
public(package) fun blob_cfg_size(blob_cfg: &BlobConfig): u64 {
    let mut size = 0;
    blob_cfg.blobs.do_ref!(|blob| { size = size + blob.size() });
    size
}

/// Destroy the config and return the blobs it held.
public(package) fun withdraw_and_burn(blob_cfg: BlobConfig): vector<Blob> {
    let BlobConfig {
        id,
        blobs,
        epoch_set: _,
        cycle_limit: _,
        fileMeta_id: _,
        sponsor: _,
        share_payment: _,
        uploaded_on: _,
        index: _,
    } = blob_cfg;
    id.delete();
    blobs
}

// === Test-only helpers ===

#[test_only]
public fun create_dummy_config(epoch: u32, clock: &Clock, ctx: &mut TxContext): BlobConfig {
    new_config_blob(vector[], epoch, option::none(), option::none(), clock, ctx)
}

#[test_only]
public fun destroy_dummy_config(cfg: BlobConfig) {
    let blobs = withdraw_and_burn(cfg);

    vector::destroy_empty(blobs);
}
