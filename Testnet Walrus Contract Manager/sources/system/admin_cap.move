/// Mints and inspects `AdminCap`, the capability that guards privileged system operations.
module warlot::admin_cap;

// === Imports ===

use warlot::system_events;

// === Constants ===

/// The original admin key, minted once at `init`.
const STATE_ORIGINAL: u8 = 0;
/// A duplicate of the admin key, minted from an original.
const STATE_DUPLICATE: u8 = 1;

// === Structs ===

/// Admin capability, carrying along a state tag.
public struct AdminCap has key, store {
    id: UID,
    /// The system this capability was minted for.
    system_config_id: ID,
    /// `STATE_ORIGINAL` or `STATE_DUPLICATE`.
    state: u8,
    /// How many systems have been minted through this capability.
    total_system: u8,
}

// === View functions ===

/// The state tag carried by this capability.
public fun state(admin_cap: &AdminCap): u8 {
    admin_cap.state
}

/// The tag identifying an original capability.
public fun state_original(): u8 {
    STATE_ORIGINAL
}

/// The tag identifying a duplicate capability.
public fun state_duplicate(): u8 {
    STATE_DUPLICATE
}

/// The system this capability names.
public fun system_config_id(admin_cap: &AdminCap): ID {
    admin_cap.system_config_id
}

/// How many systems have been minted through this capability.
public fun total_system(admin_cap: &AdminCap): u8 {
    admin_cap.total_system
}

// === Package functions ===

/// Mint a capability naming `system_config_id`.
public(package) fun new(
    system_config_id: ID,
    state: u8,
    total_system: u8,
    ctx: &mut TxContext,
): AdminCap {
    AdminCap {
        id: object::new(ctx),
        system_config_id,
        state,
        total_system,
    }
}

/// Hand a capability to `receiver`. The capability cannot be transferred from
/// outside this module, so custody changes route through here.
///
/// The announcement is made here rather than at the mint, because a capability
/// nobody holds is not authority over anything: the holder is part of what has
/// to be announced, and this is the one place it is known.
public(package) fun transfer_to(admin_cap: AdminCap, receiver: address, ctx: &TxContext) {
    system_events::emit_admin_cap_minted(
        admin_cap.system_config_id,
        object::id(&admin_cap),
        admin_cap.state,
        admin_cap.total_system,
        receiver,
        ctx.sender(),
    );

    transfer::transfer(admin_cap, receiver);
}

/// Record one more system minted through this capability.
public(package) fun increase_total_system(admin_cap: &mut AdminCap) {
    let old_count = admin_cap.total_system;
    admin_cap.total_system = old_count + 1;
}
