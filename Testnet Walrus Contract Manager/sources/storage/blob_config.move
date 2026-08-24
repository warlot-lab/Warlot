/// Owns `BlobConfig`: the shared object holding a user's blobs and their renewal mandate.
module warlot::blob_config;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::events;

// === Errors ===

#[error]
const ENotOwner: vector<u8> = b"NOT THE OWNER OF THIS BLOB CONFIG";

// === Structs ===

/// Every blob stored with Warlot is wrapped in a config that names its owner and
/// tells the renewal system how to keep it alive.
///
/// The config is shared rather than owned, because renewal is permissionless and
/// an owned object can only be used in a transaction its owner signed. Custody is
/// therefore mediated by `owner` rather than by Sui object ownership: anyone may
/// pass a config to renewal, only `owner` may pass it to withdrawal.
///
/// `key` without `store`, so a config can never be wrapped inside another object
/// or transferred away from the shared pool. It is created, shared once, and
/// consumed by `unwrap`.
public struct BlobConfig has key {
    id: UID,
    /// The address that may withdraw these blobs. The only authorization this
    /// object needs.
    owner: address,
    /// The blobs under this config's custody.
    blobs: vector<Blob>,
    /// How many epochs ahead the blobs are kept paid for.
    epoch_set: u32,
    /// How many renewal cycles remain; `none` for an indefinite mandate.
    cycle_limit: Option<u64>,
    /// The `FileMeta` naming this config, if one exists.
    fileMeta_id: Option<ID>,
    uploaded_on: u64,
}

// === View functions ===

/// This config's object id.
public(package) fun config_id(blob_cfg: &BlobConfig): ID {
    object::id(blob_cfg)
}

/// The address entitled to withdraw these blobs.
public(package) fun owner(blob_cfg: &BlobConfig): address {
    blob_cfg.owner
}

/// How many epochs ahead the blobs are kept paid for.
public(package) fun epoch_set(blob_cfg: &BlobConfig): u32 {
    blob_cfg.epoch_set
}

/// How many renewal cycles remain, or `none` for an indefinite mandate.
public(package) fun cycle_limit(blob_cfg: &BlobConfig): Option<u64> {
    blob_cfg.cycle_limit
}

/// Whether the mandate still authorises a renewal. An indefinite mandate always
/// does.
public(package) fun has_cycles(blob_cfg: &BlobConfig): bool {
    if (blob_cfg.cycle_limit.is_none()) {
        return true
    };

    *blob_cfg.cycle_limit.borrow() > 0
}

// === Package functions ===

/// Wrap `blobs` in a config owned by `owner` and carrying the given renewal mandate.
///
/// Construction is deliberately separate from `share`, so the caller can read the
/// new config's id ,  or act on it ,  while it is still owned by the transaction.
public(package) fun new(
    owner: address,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    fileMeta_id: Option<ID>,
    clock: &Clock,
    ctx: &mut TxContext,
): BlobConfig {
    BlobConfig {
        id: object::new(ctx),
        owner,
        blobs,
        epoch_set,
        cycle_limit,
        fileMeta_id,
        uploaded_on: clock.timestamp_ms(),
    }
}

/// Publish the config, making it reachable by any renewer.
public(package) fun share(blob_cfg: BlobConfig) {
    transfer::share_object(blob_cfg);
}

/// Mutable access to the wrapped blobs.
public(package) fun blobs_mut(blob_cfg: &mut BlobConfig): &mut vector<Blob> {
    &mut blob_cfg.blobs
}

/// Spend one renewal cycle. An indefinite mandate is left alone.
///
/// Guarded by `has_cycles`, which the caller checks before doing the work the
/// cycle pays for; spending from an exhausted mandate underflows rather than
/// wrapping the count round.
public(package) fun consume_cycle(blob_cfg: &mut BlobConfig) {
    if (blob_cfg.cycle_limit.is_none()) {
        return
    };

    let remaining = blob_cfg.cycle_limit.borrow_mut();
    *remaining = *remaining - 1;
}

/// Destroy the config and return the blobs it held.
///
/// The owner's exit is unconditional and has no repair step: the config is the
/// only place custody was recorded, so deleting it is the whole operation.
public(package) fun unwrap(blob_cfg: BlobConfig, ctx: &TxContext): vector<Blob> {
    assert!(ctx.sender() == blob_cfg.owner, ENotOwner);

    let config_id = object::id(&blob_cfg);
    let BlobConfig {
        id,
        owner,
        blobs,
        epoch_set: _,
        cycle_limit: _,
        fileMeta_id: _,
        uploaded_on: _,
    } = blob_cfg;
    id.delete();

    events::emit_withdraw_blob(owner, config_id);

    blobs
}
