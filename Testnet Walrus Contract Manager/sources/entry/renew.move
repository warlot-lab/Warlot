/// Exposes renewal as one call per blob config, composable in a transaction block.
module warlot::entry_renew;

// === Imports ===

use sui::coin::Coin;
use wal::wal::WAL;
use walrus::system::System;
use warlot::{blob_config::BlobConfig, renew};

// === Public functions ===

/// Extend one config's blobs to `ahead` epochs beyond the current one, paying out
/// of `payment` and leaving the change in it.
///
/// Permissionless by design. Any address may renew any config, which is what lets
/// a background service keep storage alive without holding the owner's key; the
/// caller pays, and the mandate on the config is the only thing that bounds what
/// they can do. A caller renewing many configs issues one call per config inside a
/// single programmable transaction block ,  the transaction is the unit of
/// batching, because Move cannot take a vector of mutable references.
public fun renew_blob(
    walrus_system: &mut System,
    config: &mut BlobConfig,
    payment: &mut Coin<WAL>,
    ahead: u32,
) {
    renew::renew_blob_cfg(config, walrus_system, ahead, payment);
}
