/// Moves a blob config's custody from one user to another, in two acts.
///
/// Ownership on a config decides who may withdraw the blobs under it, so custody
/// arriving is a responsibility and not only a gift. The owner offers, the named
/// recipient accepts, and until they do nothing has moved. That closes the
/// push-content-at-a-stranger vector by construction rather than by an inbound
/// policy, a quota or a byte budget, none of which are needed once the move
/// requires the recipient to act.
///
/// This is the consent layer for the transfer of an **existing** config between
/// users. It does not govern a store made under another address on the strength
/// of a delegation, and must never be extended to one. That store was consented
/// to once already, at grant time: `add_blob_to_address` is the consent, and
/// `store::raw_store_blob` is the single place every byte-billing path asks for
/// it. A direct operator write is born owned by the file's owner and transfers
/// nothing; a draft merge is the owner's own act; a rejected draft stays with the
/// writer who pushed it. Requiring an accept on any of those would break every
/// operator write and every delegated upload while protecting nobody.
module warlot::entry_transfer;

// === Imports ===

use warlot::{blob_config::{Self, BlobConfig}, system_config::SystemConfig, user};

// === Errors ===

#[error]
const ENotRegistered: vector<u8> =
    b"THE ADDRESS TAKING THIS CONFIG IS NOT REGISTERED ON THIS SYSTEM";

// === Public functions ===

/// Name `recipient` as the address that may take custody of `config`.
///
/// The sender must be the current owner. A second offer replaces the first.
public fun offer(
    system_cfg: &SystemConfig,
    config: &mut BlobConfig,
    recipient: address,
    ctx: &TxContext,
) {
    system_cfg.assert_version();

    blob_config::offer_ownership(config, object::id(system_cfg), recipient, ctx);
}

/// Take up an offer made to the sender, moving custody to them.
///
/// The sender must be registered. Every path that creates a config puts it under
/// a registered address ,  `store::raw_store_blob` resolves the owner's account
/// before it wraps anything ,  and this is the only path that moves one, so it is
/// the only place that invariant could be lost. An unregistered owner would hold
/// content that compaction could not touch, because the permission it consults
/// lives on an account object that does not exist.
public fun accept(system_cfg: &SystemConfig, config: &mut BlobConfig, ctx: &TxContext) {
    system_cfg.assert_version();
    assert!(user::check_user(system_cfg, ctx.sender()), ENotRegistered);

    blob_config::accept_ownership(config, object::id(system_cfg), ctx);
}

/// Withdraw the standing offer, leaving custody where it is.
///
/// The sender must be the current owner. A config with no standing offer is
/// refused rather than passed over.
public fun cancel(system_cfg: &SystemConfig, config: &mut BlobConfig, ctx: &TxContext) {
    system_cfg.assert_version();

    blob_config::cancel_ownership_offer(config, object::id(system_cfg), ctx);
}
