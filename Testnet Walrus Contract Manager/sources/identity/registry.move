/// Holds `Registry`, the owned object that binds a user's address to a system.
module warlot::registry;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use warlot::identity_events;

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
    /// Which system and user object this registry points at.
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

// === Test-only helpers ===

#[test_only]
/// The one label this registry claims on chain.
public fun public_username(registry: &Registry): String {
    registry.public_username
}

#[test_only]
/// When this registry was minted.
public fun created_at(registry: &Registry): u64 {
    registry.created_at
}

#[test_only]
/// When this registry was last repointed.
public fun updated_at(registry: &Registry): u64 {
    registry.updated_at
}

#[test_only]
/// When this registry's API key form stops being accepted.
public fun decay_at(registry: &Registry): u64 {
    registry.decay_at
}

// === Package functions ===

/// Create a registry for the sender and transfer it to them.
public(package) fun create_registry(
    public_username: String,
    user_object_id: ID,
    system_id: ID,
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
        },
        created_at: clock.timestamp_ms(),
        updated_at: clock.timestamp_ms(),
        decay_at: clock.timestamp_ms() + API_DECAY,
    };

    identity_events::emit_user_registered(
        system_id,
        user_object_id,
        object::id(&registry_state),
        ctx.sender(),
        registry_state.public_username,
        registry_state.created_at,
        registry_state.decay_at,
    );

    transfer::transfer(registry_state, ctx.sender());
}

/// Replace the public username.
public(package) fun update_username(registry: &mut Registry, new_username: String) {
    registry.public_username = new_username;

    identity_events::emit_username_updated(
        registry.system_details.system_id,
        object::id(registry),
        registry.user,
        new_username,
    );
}

/// Repoint the registry at another system.
public(package) fun migrate_system(registry: &mut Registry, next_system_id: ID, clock: &Clock) {
    let previous_system = registry.system_details.system_id;

    registry.system_details.system_id = next_system_id;
    registry.updated_at = clock.timestamp_ms();

    identity_events::emit_registry_migrated(
        next_system_id,
        previous_system,
        object::id(registry),
        registry.user,
        registry.updated_at,
    );
}
