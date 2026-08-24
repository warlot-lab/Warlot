/// Returns a user's blobs to them.
module warlot::entry_withdraw;

// === Imports ===

use warlot::{registry::Registry, store, system_config::SystemConfig};

// === Public functions ===

/// Unwrap one of the sender's blob configs and transfer its blobs back to them.
public fun self_withdraw_blob(
    registry: &mut Registry,
    system_cfg: &mut SystemConfig,
    blob_obj_id: address,
    ctx: &TxContext,
) {
    let user: address = registry.get_user();
    assert!(ctx.sender() == user, 3);

    store::withdraw_blob(system_cfg, blob_obj_id, user).do!(|blob| {
        transfer::public_transfer(blob, user);
    })
}
