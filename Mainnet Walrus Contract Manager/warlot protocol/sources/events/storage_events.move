/// Declares the events blob custody raises: storing, re-parenting, renewing,
/// skipping a renewal, adopting from outside, and withdrawing.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::storage_events;

// === Imports ===

use sui::event;

// === Constants ===

/// A renewal did no work because the config's mandate is spent.
const RENEW_SKIP_CYCLE_EXHAUSTED: u8 = 0;
/// A renewal did no work on a blob because it is already paid past the target.
const RENEW_SKIP_ALREADY_FUNDED: u8 = 1;
/// A renewal did no work on a blob because its storage has already lapsed.
const RENEW_SKIP_EXPIRED: u8 = 2;

// === Events ===

/// Blobs were taken into custody under a config.
///
/// Carries `config_id`, which is what renewal addresses. An indexer holding only
/// blob object ids cannot construct a renewal call from its own database, and
/// there is no other on-chain announcement of the blob-to-config mapping.
///
/// `end_epoch` is the earliest expiry across the blobs this config holds, which
/// is the epoch by which the config must be renewed. The field carrying it used
/// to be called `current_epoch` and never held a current epoch.
public struct BlobStored has copy, drop, store {
    system_id: ID,
    config_id: ID,
    /// The address entitled to withdraw the content.
    owner: address,
    /// The address that executed the store. Differs from `owner` under delegation.
    stored_by: address,
    blobs_obj_id: vector<ID>,
    /// Unencoded size per blob, positionally matching `blobs_obj_id`.
    blob_sizes: vector<u64>,
    size: u64,
    encoded_size: u64,
    end_epoch: u32,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    fileMeta_id: Option<ID>,
    uploaded_on: u64,
}

/// A config was re-parented to another address.
public struct BlobConfigOwnerChanged has copy, drop, store {
    system_id: ID,
    config_id: ID,
    previous_owner: address,
    new_owner: address,
}

/// One blob's storage was extended.
///
/// Emitted from inside the renewal loop, the only place `wal_spent` and
/// `epochs_extended` exist: the cost is the payment coin's value measured either
/// side of the extension, and the extension is what the blob actually needed
/// rather than what the caller asked for.
public struct BlobRenewed has copy, drop, store {
    system_id: ID,
    config_id: ID,
    owner: address,
    blob_obj_id: ID,
    epoch_set: u32,
    /// The Walrus epoch the renewal ran in.
    current_epoch: u32,
    epochs_extended: u32,
    new_end_epoch: u32,
    wal_spent: u64,
    /// Renewal is permissionless, so who paid for it is user-visible information.
    executed_by: address,
}

/// A config's renewal mandate was charged one cycle.
///
/// Separate from `BlobRenewed` because the mandate belongs to the config and the
/// extension belongs to the blob. The cycle is spent once, after the work, and
/// only if some blob was actually extended.
public struct RenewCycleSpent has copy, drop, store {
    system_id: ID,
    config_id: ID,
    owner: address,
    blobs_extended: u64,
    wal_spent: u64,
    /// Cycles left after the charge; `none` for an indefinite mandate.
    cycles_remaining: Option<u64>,
    executed_by: address,
}

/// A renewal did no work, and why.
///
/// Without this a mandate that has been drained to zero is silent, which is what
/// makes a budget-exhaustion attack invisible. `blob_obj_id` is `none` when the
/// whole config was skipped and names the blob when only that blob was.
public struct RenewSkipped has copy, drop, store {
    system_id: ID,
    config_id: ID,
    owner: address,
    blob_obj_id: Option<ID>,
    /// One of the `renew_skip_*` constants this module publishes.
    reason: u8,
    epoch_set: u32,
    current_epoch: u32,
    executed_by: address,
}

/// A config was destroyed and the blobs it held handed back to its owner.
public struct BlobWithdrawn has copy, drop, store {
    system_id: ID,
    config_id: ID,
    owner: address,
    blobs_obj_id: vector<ID>,
}

/// A foreign-blob index was created for a user.
public struct ForeignMetaCreated has copy, drop, store {
    system_id: ID,
    foreign_meta_id: ID,
    owner: address,
}

/// Externally-sourced configs were recorded in a user's foreign-blob index.
public struct ForeignBlobsAdopted has copy, drop, store {
    system_id: ID,
    foreign_meta_id: ID,
    owner: address,
    adopted_by: address,
    /// Which of the index's vectors the ids landed in.
    chunk_index: u64,
    config_ids: vector<ID>,
    /// The index's running total after the change.
    total_blob_config: u64,
}

// === View functions ===

/// The `RenewSkipped` reason meaning the config's mandate is spent.
public fun renew_skip_cycle_exhausted(): u8 { RENEW_SKIP_CYCLE_EXHAUSTED }

/// The `RenewSkipped` reason meaning the blob is already paid past the target.
public fun renew_skip_already_funded(): u8 { RENEW_SKIP_ALREADY_FUNDED }

/// The `RenewSkipped` reason meaning the blob's storage has already lapsed.
public fun renew_skip_expired(): u8 { RENEW_SKIP_EXPIRED }

// === Package functions ===

/// Announce blobs taken into custody.
public(package) fun emit_blob_stored(
    system_id: ID,
    config_id: ID,
    owner: address,
    stored_by: address,
    blobs_obj_id: vector<ID>,
    blob_sizes: vector<u64>,
    size: u64,
    encoded_size: u64,
    end_epoch: u32,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    fileMeta_id: Option<ID>,
    uploaded_on: u64,
) {
    event::emit(BlobStored {
        system_id,
        config_id,
        owner,
        stored_by,
        blobs_obj_id,
        blob_sizes,
        size,
        encoded_size,
        end_epoch,
        epoch_set,
        cycle_limit,
        fileMeta_id,
        uploaded_on,
    })
}

/// Announce a config re-parented to another address.
public(package) fun emit_blob_config_owner_changed(
    system_id: ID,
    config_id: ID,
    previous_owner: address,
    new_owner: address,
) {
    event::emit(BlobConfigOwnerChanged {
        system_id,
        config_id,
        previous_owner,
        new_owner,
    })
}

/// Announce one blob's storage extended.
public(package) fun emit_blob_renewed(
    system_id: ID,
    config_id: ID,
    owner: address,
    blob_obj_id: ID,
    epoch_set: u32,
    current_epoch: u32,
    epochs_extended: u32,
    new_end_epoch: u32,
    wal_spent: u64,
    executed_by: address,
) {
    event::emit(BlobRenewed {
        system_id,
        config_id,
        owner,
        blob_obj_id,
        epoch_set,
        current_epoch,
        epochs_extended,
        new_end_epoch,
        wal_spent,
        executed_by,
    })
}

/// Announce a renewal mandate charged one cycle.
public(package) fun emit_renew_cycle_spent(
    system_id: ID,
    config_id: ID,
    owner: address,
    blobs_extended: u64,
    wal_spent: u64,
    cycles_remaining: Option<u64>,
    executed_by: address,
) {
    event::emit(RenewCycleSpent {
        system_id,
        config_id,
        owner,
        blobs_extended,
        wal_spent,
        cycles_remaining,
        executed_by,
    })
}

/// Announce a renewal that did no work.
public(package) fun emit_renew_skipped(
    system_id: ID,
    config_id: ID,
    owner: address,
    blob_obj_id: Option<ID>,
    reason: u8,
    epoch_set: u32,
    current_epoch: u32,
    executed_by: address,
) {
    event::emit(RenewSkipped {
        system_id,
        config_id,
        owner,
        blob_obj_id,
        reason,
        epoch_set,
        current_epoch,
        executed_by,
    })
}

/// Announce a destroyed config and the blobs it returned.
public(package) fun emit_blob_withdrawn(
    system_id: ID,
    config_id: ID,
    owner: address,
    blobs_obj_id: vector<ID>,
) {
    event::emit(BlobWithdrawn { system_id, config_id, owner, blobs_obj_id })
}

/// Announce a newly created foreign-blob index.
public(package) fun emit_foreign_meta_created(
    system_id: ID,
    foreign_meta_id: ID,
    owner: address,
) {
    event::emit(ForeignMetaCreated { system_id, foreign_meta_id, owner })
}

/// Announce configs recorded in a foreign-blob index.
public(package) fun emit_foreign_blobs_adopted(
    system_id: ID,
    foreign_meta_id: ID,
    owner: address,
    adopted_by: address,
    chunk_index: u64,
    config_ids: vector<ID>,
    total_blob_config: u64,
) {
    event::emit(ForeignBlobsAdopted {
        system_id,
        foreign_meta_id,
        owner,
        adopted_by,
        chunk_index,
        config_ids,
        total_blob_config,
    })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `BlobStored`, in declaration order.
public fun read_blob_stored(e: &BlobStored): (
    ID,
    ID,
    address,
    address,
    vector<ID>,
    vector<u64>,
    u64,
    u64,
    u32,
    u32,
    Option<u64>,
    Option<ID>,
    u64,
) {
    let BlobStored {
        system_id: _system_id,
        config_id: _config_id,
        owner: _owner,
        stored_by: _stored_by,
        blobs_obj_id: _blobs_obj_id,
        blob_sizes: _blob_sizes,
        size: _size,
        encoded_size: _encoded_size,
        end_epoch: _end_epoch,
        epoch_set: _epoch_set,
        cycle_limit: _cycle_limit,
        fileMeta_id: _fileMeta_id,
        uploaded_on: _uploaded_on,
    } = e;

    (
        *_system_id,
        *_config_id,
        *_owner,
        *_stored_by,
        *_blobs_obj_id,
        *_blob_sizes,
        *_size,
        *_encoded_size,
        *_end_epoch,
        *_epoch_set,
        *_cycle_limit,
        *_fileMeta_id,
        *_uploaded_on,
    )
}

#[test_only]
/// Every field of `BlobConfigOwnerChanged`, in declaration order.
public fun read_blob_config_owner_changed(e: &BlobConfigOwnerChanged): (ID, ID, address, address) {
    let BlobConfigOwnerChanged {
        system_id: _system_id,
        config_id: _config_id,
        previous_owner: _previous_owner,
        new_owner: _new_owner,
    } = e;

    (*_system_id, *_config_id, *_previous_owner, *_new_owner)
}

#[test_only]
/// Every field of `BlobRenewed`, in declaration order.
public fun read_blob_renewed(e: &BlobRenewed): (
    ID,
    ID,
    address,
    ID,
    u32,
    u32,
    u32,
    u32,
    u64,
    address,
) {
    let BlobRenewed {
        system_id: _system_id,
        config_id: _config_id,
        owner: _owner,
        blob_obj_id: _blob_obj_id,
        epoch_set: _epoch_set,
        current_epoch: _current_epoch,
        epochs_extended: _epochs_extended,
        new_end_epoch: _new_end_epoch,
        wal_spent: _wal_spent,
        executed_by: _executed_by,
    } = e;

    (
        *_system_id,
        *_config_id,
        *_owner,
        *_blob_obj_id,
        *_epoch_set,
        *_current_epoch,
        *_epochs_extended,
        *_new_end_epoch,
        *_wal_spent,
        *_executed_by,
    )
}

#[test_only]
/// Every field of `RenewCycleSpent`, in declaration order.
public fun read_renew_cycle_spent(e: &RenewCycleSpent): (
    ID,
    ID,
    address,
    u64,
    u64,
    Option<u64>,
    address,
) {
    let RenewCycleSpent {
        system_id: _system_id,
        config_id: _config_id,
        owner: _owner,
        blobs_extended: _blobs_extended,
        wal_spent: _wal_spent,
        cycles_remaining: _cycles_remaining,
        executed_by: _executed_by,
    } = e;

    (
        *_system_id,
        *_config_id,
        *_owner,
        *_blobs_extended,
        *_wal_spent,
        *_cycles_remaining,
        *_executed_by,
    )
}

#[test_only]
/// Every field of `RenewSkipped`, in declaration order.
public fun read_renew_skipped(e: &RenewSkipped): (
    ID,
    ID,
    address,
    Option<ID>,
    u8,
    u32,
    u32,
    address,
) {
    let RenewSkipped {
        system_id: _system_id,
        config_id: _config_id,
        owner: _owner,
        blob_obj_id: _blob_obj_id,
        reason: _reason,
        epoch_set: _epoch_set,
        current_epoch: _current_epoch,
        executed_by: _executed_by,
    } = e;

    (
        *_system_id,
        *_config_id,
        *_owner,
        *_blob_obj_id,
        *_reason,
        *_epoch_set,
        *_current_epoch,
        *_executed_by,
    )
}

#[test_only]
/// Every field of `BlobWithdrawn`, in declaration order.
public fun read_blob_withdrawn(e: &BlobWithdrawn): (ID, ID, address, vector<ID>) {
    let BlobWithdrawn {
        system_id: _system_id,
        config_id: _config_id,
        owner: _owner,
        blobs_obj_id: _blobs_obj_id,
    } = e;

    (*_system_id, *_config_id, *_owner, *_blobs_obj_id)
}

#[test_only]
/// Every field of `ForeignMetaCreated`, in declaration order.
public fun read_foreign_meta_created(e: &ForeignMetaCreated): (ID, ID, address) {
    let ForeignMetaCreated {
        system_id: _system_id,
        foreign_meta_id: _foreign_meta_id,
        owner: _owner,
    } = e;

    (*_system_id, *_foreign_meta_id, *_owner)
}

#[test_only]
/// Every field of `ForeignBlobsAdopted`, in declaration order.
public fun read_foreign_blobs_adopted(e: &ForeignBlobsAdopted): (
    ID,
    ID,
    address,
    address,
    u64,
    vector<ID>,
    u64,
) {
    let ForeignBlobsAdopted {
        system_id: _system_id,
        foreign_meta_id: _foreign_meta_id,
        owner: _owner,
        adopted_by: _adopted_by,
        chunk_index: _chunk_index,
        config_ids: _config_ids,
        total_blob_config: _total_blob_config,
    } = e;

    (
        *_system_id,
        *_foreign_meta_id,
        *_owner,
        *_adopted_by,
        *_chunk_index,
        *_config_ids,
        *_total_blob_config,
    )
}
