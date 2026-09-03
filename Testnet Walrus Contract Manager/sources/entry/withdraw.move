/// Returns a user's blobs to them.
module warlot::entry_withdraw;

// === Imports ===

use warlot::{blob_config::{Self, BlobConfig}, system_config::SystemConfig};

// === Public functions ===

/// Unwrap one of the sender's blob configs and transfer its blobs back to them.
///
/// The shared config is taken by value and destroyed. Because the config is the
/// only record of who holds what, nothing else has to be updated to match.
public fun self_withdraw_blob(
    system_cfg: &SystemConfig,
    config: BlobConfig,
    ctx: &TxContext,
) {
    system_cfg.assert_version();

    release(config, object::id(system_cfg), ctx);
}

/// The same withdrawal, over as many of the sender's configs as one transaction
/// can carry.
///
/// This saves the per-call overhead. It does not lift a ceiling: every config is
/// still named as a shared-object input, so Sui's input limit binds exactly as it
/// did. What it makes practical is clearing a retired wallet, which one config
/// per transaction does not.
///
/// Ownership is checked per config rather than once for the vector. They need not
/// share an owner to be handed in together, and `unwrap` is the assert either
/// way, so hoisting the check would add a rule the mechanism does not have.
public fun self_withdraw_blobs(
    system_cfg: &SystemConfig,
    configs: vector<BlobConfig>,
    ctx: &TxContext,
) {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);

    // Bounded by the configs the transaction carries, which the shared-object
    // input limit bounds.
    configs.destroy!(|config| release(config, system_id, ctx));
}

// === Private functions ===

/// Destroy one config and send its blobs to the address that held it.
fun release(config: BlobConfig, system_id: ID, ctx: &TxContext) {
    let owner = config.owner();

    blob_config::unwrap(config, system_id, ctx).do!(|blob| {
        transfer::public_transfer(blob, owner);
    })
}
