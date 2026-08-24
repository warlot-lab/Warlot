/// Holds `Registry`, the owned object that binds a user's address to a system.
module warlot::registry;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use warlot::events;

// === Constants ===

/// Time in ms after which an API key form is no longer accepted.
const API_DECAY: u64 = 10000000000;

// === Structs ===

/// The Warlot user identifier, owned by the user it names.
public struct Registry has key {
    id: UID,
    /// The address this registry identifies.
    user: address,
    /// The one label the user claims on chain.
    public_username: String,
    /// Which system, user object and project holder this registry points at.
    system_details: SystemDetail,
    created_at: u64,
    updated_at: u64,
    /// When the registry's API key form stops being accepted.
    decay_at: u64,
}

/// The on-chain objects this registry names.
public struct SystemDetail has store {
    user_object_id: ID,
    system_id: ID,
    project_holder: Option<ID>,
}

// === View functions ===

/// The address this registry identifies.
public fun get_user(registry: &Registry): address {
    registry.user
}

/// The system this registry belongs to.
public fun get_system(registry: &Registry): ID {
    registry.system_details.system_id
}

// === Package functions ===

/// Create a registry for the sender and transfer it to them.
public(package) fun create_registry(
    public_username: String,
    user_object_id: ID,
    system_id: ID,
    project_holder: Option<ID>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let registry_state = Registry {
        id: object::new(ctx),
        user: ctx.sender(),
        public_username,
        system_details: SystemDetail {
            user_object_id,
            system_id,
            project_holder,
        },
        created_at: clock.timestamp_ms(),
        updated_at: clock.timestamp_ms(),
        decay_at: clock.timestamp_ms() + API_DECAY,
    };

    events::emit_new_user(user_object_id, object::id(&registry_state), ctx.sender());
    transfer::transfer(registry_state, ctx.sender());
}

/// Replace the public username.
public(package) fun update_username(registry: &mut Registry, new_username: String) {
    registry.public_username = new_username;
}

/// Repoint the registry at another system.
public(package) fun migrate_system(registry: &mut Registry, next_system_id: ID, clock: &Clock) {
    registry.system_details.system_id = next_system_id;
    registry.updated_at = clock.timestamp_ms();
}
