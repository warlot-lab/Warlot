/// Adopts externally-sourced blobs into the protocol's renewal management.
module warlot::entry_upload;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{
    admin_cap::AdminCap,
    operator::OperatorAuth,
    storage_events,
    store,
    system_config::SystemConfig,
    tier,
};

// === Errors ===

#[error]
const EBatchTooLarge: vector<u8> = b"TOO MANY BLOBS FOR ONE ADOPTION";

// === Constants ===

/// The largest number of blobs one adoption may carry.
///
/// The blobs live inline on the config this call creates, and renewal walks all
/// of them inside one transaction, so the bound is what keeps both the object and
/// the renewal call within reach. It used to bound something else ,  a shared
/// object created and an event emitted per blob ,  which is the cost this call no
/// longer pays.
const MAX_ADOPTION_BATCH: u64 = 100;

// === Public functions ===

/// Take `blobs` sourced outside the protocol into custody under `owner`, in one
/// config.
///
/// One config per call, not one per blob. A quilt is a single Walrus blob, so a
/// quilt is adopted as one config and its renewal mandate covers the whole quilt
/// ,  which is the only granularity Walrus offers, since a patch cannot be
/// extended or deleted on its own. Blobs adopted together are bound together:
/// they share one mandate and are withdrawn in one call.
///
/// `owner` is an address rather than a `&Registry`, as it is on every other path
/// that stores on someone's behalf. The registry this used to take is an owned
/// object with no `store`, so only the address it names could ever pass it ,
/// which meant a delegate could not adopt at all, and the operator sibling below
/// could not be executed by anybody: one transaction cannot take two owned
/// objects belonging to two different addresses. The registry also checked
/// nothing that is not checked anyway. `raw_store_blob` looks `owner` up on this
/// system and refuses a sender who holds no `add_blob` grant against them, which
/// is the same authorisation `create_file` runs on the same argument.
public fun foreign_blob_add(
    system_cfg: &SystemConfig,
    owner: address,
    cycle_end: Option<u64>,
    epoch_set: u32,
    blobs: vector<Blob>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    adopt(
        system_cfg,
        owner,
        cycle_end,
        epoch_set,
        blobs,
        option::none(),
        clock,
        ctx,
    )
}

/// The same adoption, made on the strength of an operator credential rather than
/// a grant against the sender's address.
///
/// The sibling exists because `Option<&AdminCap>` is not a type Move will
/// accept, so the credential cannot be an optional argument to the call above.
public fun foreign_blob_add_as_operator(
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    owner: address,
    cycle_end: Option<u64>,
    epoch_set: u32,
    blobs: vector<Blob>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());

    adopt(
        system_cfg,
        owner,
        cycle_end,
        epoch_set,
        blobs,
        option::some(auth),
        clock,
        ctx,
    )
}

// === Private functions ===

/// Take `blobs` into custody under `owner`, in one config.
fun adopt(
    system_cfg: &SystemConfig,
    owner: address,
    cycle_end: Option<u64>,
    epoch_set: u32,
    blobs: vector<Blob>,
    operator: Option<OperatorAuth>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    assert!(blobs.length() <= MAX_ADOPTION_BATCH, EBatchTooLarge);

    // Adoption buys a term, so the term is checked here. The store itself no
    // longer checks: doing it there put the same check on every revision of every
    // file, where the term is the file's own and cannot be changed.
    tier::validate(system_cfg, epoch_set);

    let blob_count = blobs.length();

    // The custody itself is announced from the config's construction, which is
    // the only place the config's id exists alongside the blobs it took. This
    // adds the one thing that announcement cannot say: that the content came
    // from outside the protocol rather than from an upload through it.
    let (config_id, _) = store::store_blob_internal(
        system_cfg,
        blobs,
        epoch_set,
        cycle_end,
        owner,
        operator,
        clock,
        ctx,
    );

    storage_events::emit_foreign_blobs_adopted(
        object::id(system_cfg),
        owner,
        ctx.sender(),
        config_id,
        blob_count,
    );
}
