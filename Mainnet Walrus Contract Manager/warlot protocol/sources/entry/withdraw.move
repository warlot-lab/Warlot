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

    let owner = config.owner();

    blob_config::unwrap(config, ctx).do!(|blob| {
        transfer::public_transfer(blob, owner);
    })
}
