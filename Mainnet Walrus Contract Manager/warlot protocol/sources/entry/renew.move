/// Exposes renewal as one call per blob config, composable in a transaction block.
module warlot::entry_renew;

// === Imports ===

use sui::coin::Coin;
use wal::wal::WAL;
use walrus::system::System;
use warlot::{blob_config::BlobConfig, renew, system_config::SystemConfig};

// === Public functions ===

/// Extend one config's blobs back out to the term the config was bought under,
/// paying out of `payment` and leaving the change in it.
///
/// Permissionless by design. Any address may renew any config, which is what lets
/// a background service keep storage alive without holding the owner's key; the
/// caller pays, and the mandate on the config is the only thing that bounds what
/// they can do. A caller renewing many configs issues one call per config inside a
/// single programmable transaction block ,  the transaction is the unit of
/// batching, because Move cannot take a vector of mutable references.
///
/// The horizon is read from the config rather than taken from the caller. The
/// term is what the owner bought; letting a renewer name a different one would
/// let a stranger decide how much storage the owner's mandate is spent on.
public fun renew_blob(
    system_cfg: &SystemConfig,
    walrus_system: &mut System,
    config: &mut BlobConfig,
    payment: &mut Coin<WAL>,
) {
    system_cfg.assert_version();

    renew::renew_blob_cfg(config, walrus_system, payment);
}
