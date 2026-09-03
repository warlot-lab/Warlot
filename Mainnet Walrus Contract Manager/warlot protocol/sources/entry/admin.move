/// Composes the privileged operations an `AdminCap` holder may perform.
module warlot::entry_admin;

// === Imports ===

use sui::clock::Clock;
use wal::wal::WAL;
use warlot::{admin_cap::{Self, AdminCap}, system_config::{Self, SystemConfig}, vault};

// === Errors ===

#[error]
const ENotOriginalCap: vector<u8> = b"THIS OPERATION NEEDS THE ORIGINAL ADMIN CAPABILITY";
#[error]
const ECapForAnotherSystem: vector<u8> = b"THIS ADMIN CAPABILITY WAS MINTED FOR A DIFFERENT SYSTEM";
#[error]
const ESuccessorAlreadyMinted: vector<u8> = b"THIS SYSTEM HAS ALREADY NAMED ITS SUCCESSOR";

// === Admin functions ===

/// Withdraw WAL from the system vault to the caller.
#[allow(lint(self_transfer))]
public fun withdraw_system_wal(
    system_cfg: &mut SystemConfig,
    admin_cap: &mut AdminCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    let vault = system_cfg.get_vault_mut();

    // The payout is announced from inside the vault, so a route added later
    // cannot take value out of the treasury without saying so.
    let withdrawn_coin = vault::withdraw<WAL>(vault, admin_cap, amount, ctx);

    transfer::public_transfer(withdrawn_coin, ctx.sender());
}

/// Withdraw any accepted coin type from the system vault to the caller.
#[allow(lint(self_transfer))]
public fun withdraw_system_coin<T>(
    system_cfg: &mut SystemConfig,
    admin_cap: &mut AdminCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    let vault = system_cfg.get_vault_mut();

    // Aborts with `ENoBalanceFound` when the vault holds none of this type.
    let withdrawn_coin = vault::withdraw<T>(vault, admin_cap, amount, ctx);

    transfer::public_transfer(withdrawn_coin, ctx.sender());
}

/// Accept a new coin type into the system vault.
public fun add_coin_type<T>(admin_cap: &mut AdminCap, system_cfg: &mut SystemConfig) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    let vault = system_cfg.get_vault_mut();
    vault::add_supported_coin<T>(vault, admin_cap);
}

/// Stop accepting a coin type. Balances already held stay withdrawable.
public fun remove_supported_coin<T>(admin_cap: &mut AdminCap, system_cfg: &mut SystemConfig) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    let vault = system_cfg.get_vault_mut();
    vault::remove_supported_coin<T>(vault, admin_cap);
}

/// Mint the next system in the chain, share it, and hand the caller the original
/// capability for it.
///
/// The successor gets its own capability because capabilities are bound to the
/// system they name: without one minted here, nothing could ever administer the
/// system this call creates.
public fun mint_system(
    admin_cap: &mut AdminCap,
    old_system: &mut SystemConfig,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    ctx: &mut TxContext,
) {
    old_system.assert_version();

    // System minting is linear: an old system may name only one successor.
    assert!(option::is_none(old_system.next_system()), ESuccessorAlreadyMinted);

    assert_original_cap_for(admin_cap, object::id(old_system));

    // The successor opens selling what its predecessor sold. A ladder that reset
    // to nothing would leave the new system unable to take a single upload until
    // somebody remembered to configure it.
    let new_system = system_config::new(
        object::id(old_system),
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
        *old_system.tier_table(),
        old_system.max_epochs_ahead(),
        ctx,
    );

    let new_system_id = object::id(&new_system);

    admin_cap.increase_total_system();
    old_system.set_next_system(new_system_id, ctx.sender());

    let successor_cap = admin_cap::new(new_system_id, admin_cap::state_original(), 0, ctx);

    transfer::public_share_object(new_system);
    admin_cap::transfer_to(successor_cap, ctx.sender(), ctx);
}

/// Overwrite the registry modification fees.
public fun update_cost(
    admin_cap: &mut AdminCap,
    system: &mut SystemConfig,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    ctx: &TxContext,
) {
    system.assert_version();
    assert_original_cap_for(admin_cap, object::id(system));

    system.set_costs(
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
        ctx.sender(),
    );
}

/// Replace the storage terms this system sells and the horizon they sit inside.
///
/// The ladder is configuration rather than a compile-time constant so that it can
/// be retuned, and so that a change to the storage horizon upstream is answered
/// here instead of by republishing the package.
public fun update_tier_table(
    admin_cap: &mut AdminCap,
    system: &mut SystemConfig,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    ctx: &TxContext,
) {
    system.assert_version();
    assert_original_cap_for(admin_cap, object::id(system));

    system.set_tier_table(tier_table, max_epochs_ahead, ctx.sender());
}

/// Raise the system to the package version.
///
/// The one entry point that must not assert the version, because a stale version
/// is the condition it exists to clear. It asserts the opposite instead: the
/// system is behind the package, so there is something to do.
public fun migrate_version(
    admin_cap: &mut AdminCap,
    system: &mut SystemConfig,
    ctx: &TxContext,
) {
    assert_original_cap_for(admin_cap, object::id(system));

    system.update_version(ctx.sender());
}

/// Mint a duplicate admin capability for `receiver`.
public fun mint_admin(
    system_cfg: &SystemConfig,
    receiver: address,
    admin_cap: &AdminCap,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    let new_cap = admin_cap::new(
        object::id(system_cfg),
        admin_cap::state_duplicate(),
        0,
        ctx,
    );

    admin_cap::transfer_to(new_cap, receiver, ctx);
}

/// Give `operator_cap` a slot in the system's operator set until `until_ms`.
///
/// The slot is named by capability **id**, not by the address holding it, so
/// moving the capability to another wallet costs nothing here. Only enrolling,
/// refreshing or retiring a slot is a transaction.
///
/// The id is taken rather than the capability object, because the capability is
/// already in the backend's hands by the time a slot is wanted, and requiring
/// the admin to hold both would mean minting and enrolling could never be
/// separated. Nothing is trusted about the id as a result: `operator::authorise`
/// re-checks at every use that the capability presented is a duplicate and names
/// this system.
///
/// Refuses an id that already holds a slot. Extending one is `refresh_operator`,
/// and the two are separate because an enrolment that quietly became an extension
/// would move a live key's deadline while the admin believed they were onboarding
/// a new one.
public fun enrol_operator(
    system_cfg: &mut SystemConfig,
    admin_cap: &AdminCap,
    operator_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    clock: &Clock,
    ctx: &TxContext,
) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    system_cfg.enrol_operator(
        operator_cap,
        until_ms,
        may_bypass_draft,
        clock.timestamp_ms(),
        ctx.sender(),
    );
}

/// Replace the terms of a slot `operator_cap` already holds.
///
/// How a deadline is moved without a gap in which the backend cannot sign, and
/// the only way to change a slot's bypass bit. Refuses an id holding no slot, so
/// a refresh cannot silently enrol a key that was retired out from under it.
public fun refresh_operator(
    system_cfg: &mut SystemConfig,
    admin_cap: &AdminCap,
    operator_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    clock: &Clock,
    ctx: &TxContext,
) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    system_cfg.refresh_operator(
        operator_cap,
        until_ms,
        may_bypass_draft,
        clock.timestamp_ms(),
        ctx.sender(),
    );
}

/// Drop `operator_cap`'s slot in the system's operator set.
///
/// Retiring an id that holds no slot is not an error. This is the call that pulls
/// a leaked key, and one that can abort is one that can fail inside the batch
/// pulling it.
public fun retire_operator(
    system_cfg: &mut SystemConfig,
    admin_cap: &AdminCap,
    operator_cap: ID,
    ctx: &TxContext,
) {
    system_cfg.assert_version();
    assert_original_cap_for(admin_cap, object::id(system_cfg));

    system_cfg.retire_operator(operator_cap, ctx.sender());
}

// === Private functions ===

/// Assert `admin_cap` is an original and was minted for `system_cfg_id`.
///
/// Every admin function goes through here. A capability that merely exists is
/// not authority over an arbitrary system: `mint_system` builds successors and
/// `migrate_system` moves users between them, so a capability that carried
/// across systems would collapse the isolation those two are for.
fun assert_original_cap_for(admin_cap: &AdminCap, system_cfg_id: ID) {
    assert!(admin_cap.state() == admin_cap::state_original(), ENotOriginalCap);
    assert!(admin_cap.system_config_id() == system_cfg_id, ECapForAnotherSystem);
}
