/// Owns `BlobConfig`: the shared object holding a user's blobs and their renewal
/// mandate.
///
/// Custody moves between users only with the recipient's consent. The owner names
/// an address in `pending_owner` and nothing changes until that address acts.
/// Ownership decides who may withdraw, so a one-sided move would let anybody make
/// anybody else the holder of content they never asked for, and there is no
/// accounting rule that closes that as cleanly as requiring the recipient to act.
///
/// That consent layer governs the transfer of an **existing** config between
/// users. It does not govern a store authorised by a delegation, and must never
/// be applied to one. A store under another address is already consented to, once,
/// at grant time: `add_blob_to_address` is that consent, and `store::raw_store_blob`
/// is the single place every byte-billing path asks for it. Extending
/// offer-and-accept to a store would break every operator write and every
/// delegated upload.
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
#[error]
const ENoStandingOffer: vector<u8> = b"THIS CONFIG CARRIES NO OWNERSHIP OFFER";
#[error]
const ENotTheOfferedRecipient: vector<u8> =
    b"THIS CONFIG'S OWNERSHIP OFFER NAMES A DIFFERENT ADDRESS";
#[error]
const EOfferToSelf: vector<u8> = b"A CONFIG CANNOT BE OFFERED TO ITS CURRENT OWNER";
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
    /// The address that may take custody, once it asks for it.
    ///
    /// `none` on every config until its owner offers it, which costs a config
    /// that is never handed on one byte. Cleared by any move of `owner`,
    /// deliberate or not ,  an offer is a statement about the custody standing
    /// when it was made, and a stale one would let the address it named take the
    /// config from an owner who never offered it anything.
    pending_owner: Option<address>,
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

#[test_only]
/// The address this config has been offered to, if it stands offered.
///
/// Test-only, like the layout accessors beside it. Nothing in `sources/` asks the
/// question: the offer is checked where it is acted on, and an off-chain reader
/// fetches the field from the shared object rather than through a call.
public fun pending_owner(blob_cfg: &BlobConfig): Option<address> {
    blob_cfg.pending_owner
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
        pending_owner: option::none(),
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

/// Name `recipient` as the address that may take custody of this config.
///
/// The offer moves nothing. It only records who is allowed to complete the move,
/// which is what makes the handover two-sided: withdrawal follows `owner`, so a
/// config pushed onto an address is content that address is now responsible for
/// and never asked for.
///
/// A second offer replaces the first rather than accumulating. There is one
/// custody to hand over, so a queue of candidates would be a queue in which only
/// the first to act mattered, and the owner would have no way to tell which of
/// their offers was still live.
public(package) fun offer_ownership(
    blob_cfg: &mut BlobConfig,
    system_id: ID,
    recipient: address,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == blob_cfg.owner, ENotOwner);

    // Refused rather than treated as a no-op. Accepting it would raise a custody
    // change in which nothing changed hands, which is a row a consumer replaying
    // the stream has to special-case.
    assert!(recipient != blob_cfg.owner, EOfferToSelf);

    blob_cfg.pending_owner = option::some(recipient);

    storage_events::emit_blob_config_ownership_offered(
        system_id,
        object::id(blob_cfg),
        blob_cfg.owner,
        recipient,
    );
}

/// Withdraw the standing offer, leaving custody where it is.
///
/// Refuses a config with no offer rather than passing silently: the owner is
/// acting on a belief about the config's state, and a no-op would confirm a
/// belief that may be wrong.
public(package) fun cancel_ownership_offer(
    blob_cfg: &mut BlobConfig,
    system_id: ID,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == blob_cfg.owner, ENotOwner);
    assert!(blob_cfg.pending_owner.is_some(), ENoStandingOffer);

    let recipient = blob_cfg.pending_owner.extract();

    storage_events::emit_blob_config_ownership_offer_cancelled(
        system_id,
        object::id(blob_cfg),
        blob_cfg.owner,
        recipient,
    );
}

/// Take up an offer made to the sender, moving custody.
///
/// The offer is cleared before the move rather than after, so `transfer_ownership`
/// sees no standing offer and raises no cancellation for one that was in fact
/// taken up.
public(package) fun accept_ownership(
    blob_cfg: &mut BlobConfig,
    system_id: ID,
    ctx: &TxContext,
) {
    assert!(blob_cfg.pending_owner.is_some(), ENoStandingOffer);
    assert!(blob_cfg.pending_owner.borrow() == ctx.sender(), ENotTheOfferedRecipient);

    let new_owner = blob_cfg.pending_owner.extract();
    let previous_owner = blob_cfg.owner;

    transfer_ownership(blob_cfg, system_id, new_owner);

    storage_events::emit_blob_config_ownership_accepted(
        system_id,
        object::id(blob_cfg),
        previous_owner,
        new_owner,
    );
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
    let config_id = object::id(blob_cfg);

    blob_cfg.owner = new_owner;

    // Custody moving voids any offer left standing, however it moved. This is
    // also the function that hands a merged draft's config to the file's owner,
    // and an offer its writer had left open would otherwise let the address it
    // named take the config from an owner who offered it nothing.
    if (blob_cfg.pending_owner.is_some()) {
        let stale_recipient = blob_cfg.pending_owner.extract();

        storage_events::emit_blob_config_ownership_offer_cancelled(
            system_id,
            config_id,
            previous_owner,
            stale_recipient,
        );
    };

    storage_events::emit_blob_config_owner_changed(
        system_id,
        config_id,
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
    let BlobConfig { id, owner, pending_owner: _, blobs, epoch_set: _, cycle_limit: _, layout: _ }
        = blob_cfg;
    id.delete();

    let mut blobs_obj_id = vector<ID>[];

    // Bounded by the blobs this config was created holding.
    blobs.do_ref!(|blob_x| blobs_obj_id.push_back(blob::object_id(blob_x)));

    storage_events::emit_blob_withdrawn(system_id, config_id, owner, blobs_obj_id);

    (owner, blobs)
}
