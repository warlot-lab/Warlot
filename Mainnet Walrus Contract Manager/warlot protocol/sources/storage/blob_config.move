/// Owns `BlobConfig`: the shared object holding a user's blobs and their renewal mandate.
module warlot::blob_config;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::{Self, Blob};
use warlot::{layout::Layout, storage_events};

// === Errors ===

#[error]
const ENotOwner: vector<u8> = b"NOT THE OWNER OF THIS BLOB CONFIG";
#[error]
const ELayoutAlreadyRegistered: vector<u8> =
    b"THIS CONFIG ALREADY CARRIES A LAYOUT";
#[test_only]
#[error]
const ENoLayout: vector<u8> = b"THIS CONFIG CARRIES NO LAYOUT";

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
    /// How the content under this config is laid out, and what it replaced.
    ///
    /// `none` on every config an ordinary upload creates, which costs it one
    /// byte. A compaction fills it once and it is never moved again: the config
    /// *is* the generation, so rewriting its receipt would mean rewriting what
    /// the chain already attested that generation contained.
    layout: Option<Layout>,
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

/// How many blobs this config holds.
///
/// One for a quilt, which is a single Walrus blob however many patches it
/// carries.
public(package) fun blob_count(blob_cfg: &BlobConfig): u64 {
    blob_cfg.blobs.length()
}

#[test_only]
/// Whether a compaction has registered a layout on this config.
public fun has_layout(blob_cfg: &BlobConfig): bool {
    blob_cfg.layout.is_some()
}

#[test_only]
/// This config's layout, or an abort because it carries none.
public fun layout(blob_cfg: &BlobConfig): &Layout {
    assert!(blob_cfg.layout.is_some(), ENoLayout);

    blob_cfg.layout.borrow()
}

/// How many repacks deep this config's content is, and zero for content that has
/// never been compacted.
///
/// Zero is the honest answer for an uncompacted config rather than a missing one:
/// a compaction's generation must exceed every generation it supersedes, and raw
/// uploads are the floor that ordering starts from.
public(package) fun generation(blob_cfg: &BlobConfig): u32 {
    if (blob_cfg.layout.is_none()) {
        return 0
    };

    blob_cfg.layout.borrow().generation()
}

/// Whether the mandate still authorises a renewal. An indefinite mandate always
/// does.
public(package) fun has_cycles(blob_cfg: &BlobConfig): bool {
    if (blob_cfg.cycle_limit.is_none()) {
        return true
    };

    *blob_cfg.cycle_limit.borrow() > 0
}

// === Test-only helpers ===

#[test_only]
/// The object ids of the blobs under this config's custody.
public fun blob_ids(blob_cfg: &BlobConfig): vector<ID> {
    let mut ids = vector<ID>[];
    blob_cfg.blobs.do_ref!(|blob_x| ids.push_back(blob::object_id(blob_x)));
    ids
}

// === Package functions ===

/// Wrap `blobs` in a config owned by `owner` and carrying the given renewal mandate.
///
/// Construction is deliberately separate from `share`, so the caller can read the
/// new config's id ,  or act on it ,  while it is still owned by the transaction.
public(package) fun new(
    system_id: ID,
    owner: address,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    clock: &Clock,
    ctx: &mut TxContext,
): BlobConfig {
    let uploaded_on = clock.timestamp_ms();

    let blob_cfg = BlobConfig {
        id: object::new(ctx),
        owner,
        blobs,
        epoch_set,
        cycle_limit,
        layout: option::none(),
    };

    // Announced here rather than on either upload path, because this is the one
    // place where the config's id exists alongside the blobs it took custody of.
    // An event raised before the config is built cannot name it, and renewal
    // addresses configs ,  so a consumer indexing only blob ids has no way to
    // construct a renewal call from its own records.
    let mut blobs_obj_id = vector<ID>[];
    let mut blob_sizes = vector<u64>[];
    let mut size = 0;
    let mut encoded_size = 0;
    let mut end_epoch = blob::end_epoch(&blob_cfg.blobs[0]);

    // Bounded by the blobs handed in, which the transaction carrying them bounds.
    blob_cfg.blobs.do_ref!(|blob_x| {
        blobs_obj_id.push_back(blob::object_id(blob_x));
        blob_sizes.push_back(blob::size(blob_x));
        size = size + blob::size(blob_x);
        encoded_size = encoded_size + blob::storage(blob_x).size();
        if (end_epoch > blob::end_epoch(blob_x)) {
            end_epoch = blob::end_epoch(blob_x)
        };
    });

    storage_events::emit_blob_stored(
        system_id,
        object::id(&blob_cfg),
        owner,
        ctx.sender(),
        blobs_obj_id,
        blob_sizes,
        size,
        encoded_size,
        end_epoch,
        epoch_set,
        cycle_limit,
        uploaded_on,
    );

    blob_cfg
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

/// Record how this config's content is laid out, and what it replaced.
///
/// Write-once. A config that already carries a layout is refused rather than
/// overwritten: the receipt is what a holder of the superseded content checked
/// before deleting it, so a layout that could be replaced is a receipt Warlot
/// could rewrite after the fact. A new generation is a new config.
///
/// `public(package)` and unauthorised here on purpose ,  the permission bit and
/// the homogeneity of the predecessors are settled by `compaction`, which is the
/// only caller.
public(package) fun set_layout(blob_cfg: &mut BlobConfig, layout: Layout) {
    assert!(blob_cfg.layout.is_none(), ELayoutAlreadyRegistered);

    blob_cfg.layout.fill(layout);
}

/// Re-parent the config to `new_owner`.
///
/// Custody is a field rather than Sui object ownership, so moving it is a write
/// and not a transfer. Nothing here decides *whether* the move is allowed: this
/// is `public(package)` and the caller is the only thing standing between an
/// owner and a stranger, so every call site must already have established that
/// the current owner consented or that the new owner is the party the content was
/// approved by.
public(package) fun transfer_ownership(
    blob_cfg: &mut BlobConfig,
    system_id: ID,
    new_owner: address,
) {
    let previous_owner = blob_cfg.owner;

    blob_cfg.owner = new_owner;

    storage_events::emit_blob_config_owner_changed(
        system_id,
        object::id(blob_cfg),
        previous_owner,
        new_owner,
    );
}

/// Destroy the config and return the blobs it held.
///
/// The owner's exit is unconditional and has no repair step: the config is the
/// only place custody was recorded, so deleting it is the whole operation.
public(package) fun unwrap(
    blob_cfg: BlobConfig,
    system_id: ID,
    ctx: &TxContext,
): vector<Blob> {
    assert!(ctx.sender() == blob_cfg.owner, ENotOwner);

    let (_, blobs) = destroy(blob_cfg, system_id);

    blobs
}

/// Destroy the config on behalf of whoever owns it, returning that address
/// alongside the blobs.
///
/// The sender is not the owner on this path: a revision leaving a file's rollback
/// window is retired by whoever wrote the revision that displaced it. Returning
/// the owner rather than taking a recipient is what keeps that safe ,  the caller
/// chooses when the content is released and never where it goes.
public(package) fun unwrap_for_owner(
    blob_cfg: BlobConfig,
    system_id: ID,
): (address, vector<Blob>) {
    destroy(blob_cfg, system_id)
}

// === Private functions ===

/// Delete the config, announce it, and hand back its owner and its blobs.
///
/// Every exit path runs through here, so a consumer replaying the stream sees
/// the row disappear however the config was consumed. A replay that only ever
/// adds reconstructs a state that never existed.
fun destroy(blob_cfg: BlobConfig, system_id: ID): (address, vector<Blob>) {
    let config_id = object::id(&blob_cfg);
    let BlobConfig { id, owner, blobs, epoch_set: _, cycle_limit: _, layout: _ } = blob_cfg;
    id.delete();

    let mut blobs_obj_id = vector<ID>[];

    // Bounded by the blobs this config was created holding.
    blobs.do_ref!(|blob_x| blobs_obj_id.push_back(blob::object_id(blob_x)));

    storage_events::emit_blob_withdrawn(system_id, config_id, owner, blobs_obj_id);

    (owner, blobs)
}
