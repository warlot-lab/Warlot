/// Holds `SystemConfig`: the protocol's version, fees, mint lineage, treasury and user index.
module warlot::system_config;

// === Imports ===

use sui::{
    dynamic_field as dfield,
    dynamic_object_field as ofields,
    table::{Self, Table},
    table_vec::{Self, TableVec},
};
use wal::wal::WAL;
use warlot::{
    admin_cap::{Self, AdminCap},
    vault::{Self, Vault},
    version,
};

// === Constants ===

const VERSION: u64 = 1;

/// Dynamic field key for the append-only list of registered addresses.
const USERINDEX: vector<u8> = b"user indexer";
/// Dynamic field key for the address to index map backing O(1) lookups.
const USER_INDEX_MAP: vector<u8> = b"user_index_map";
/// Dynamic object field key for the protocol treasury.
const SYSTEM_VAULT: vector<u8> = b"system_vault";

// === Structs ===

/// The shared object holding the protocol's configuration and treasury.
public struct SystemConfig has key, store {
    id: UID,
    /// The delegate offered to users at registration.
    warlot_allowed_address: address,
    /// Count of registered users.
    users: u64,
    /// Count of blob configs under management.
    managed_blobs: u64,
    /// The upgrade gate.
    version: u64,
    /// Enforces that systems are minted in a single chain.
    mint_cap: SystemMintCap,
    /// The fees charged for registry modifications.
    user_modification_cfg: UserMdCfg,
}

/// Links a system to the one it was minted from and the one minted after it,
/// which is what keeps system minting linear.
public struct SystemMintCap has store {
    previous_system: ID,
    next_system: Option<ID>,
}

/// The costs charged for modifying a user registry.
public struct UserMdCfg has store {
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
}

// === View functions ===

/// The fee charged to change the API key forms.
public fun cost_change_apikey_forms(system_cfg: &SystemConfig): u64 {
    system_cfg.user_modification_cfg.cost_change_apikey_forms
}

/// The fee charged to update a registry username.
public fun cost_to_update_name(system_cfg: &SystemConfig): u64 {
    system_cfg.user_modification_cfg.cost_to_update_name
}

/// The version this system is gated at.
public fun get_system_version(system_cfg: &SystemConfig): u64 {
    system_cfg.version
}

/// The balance of `T` held in the system vault.
public fun get_system_balance<T>(system_cfg: &SystemConfig): u64 {
    let vault = ofields::borrow<vector<u8>, Vault>(&system_cfg.id, SYSTEM_VAULT);
    vault::balance_of<T>(vault)
}

/// The default delegate this system offers at registration.
public(package) fun get_warlot_address(system_cfg: &SystemConfig): address {
    system_cfg.warlot_allowed_address
}

/// The append-only list of registered addresses.
public(package) fun get_indexer(system_cfg: &SystemConfig): &TableVec<address> {
    dfield::borrow<vector<u8>, TableVec<address>>(&system_cfg.id, USERINDEX)
}

/// The dynamic field key naming the append-only address list.
public(package) fun user_index_key(): vector<u8> {
    USERINDEX
}

/// The dynamic field key naming the address to index map.
public(package) fun user_index_map_key(): vector<u8> {
    USER_INDEX_MAP
}

/// The fee charged to migrate to another system.
public(package) fun cost_to_migrate_system(system_cfg: &SystemConfig): u64 {
    system_cfg.user_modification_cfg.cost_to_migrate_system
}

/// The system minted after this one, if any.
public(package) fun next_system(system_cfg: &SystemConfig): &Option<ID> {
    &system_cfg.mint_cap.next_system
}

// === Package functions ===

/// Raise the registered-user count by one.
public(package) fun increase_user_count(system_cfg: &mut SystemConfig) {
    let old_user_count = system_cfg.users;
    system_cfg.users = old_user_count + 1;
}

/// Lower the registered-user count by one.
public(package) fun decrease_user_count(system_cfg: &mut SystemConfig) {
    let old_user_count = system_cfg.users;
    system_cfg.users = old_user_count - 1;
}

/// Raise the managed-blob count by one.
public(package) fun increase_managed_blobs(system_cfg: &mut SystemConfig) {
    let old_m_blob = system_cfg.managed_blobs;
    system_cfg.managed_blobs = old_m_blob + 1;
}

/// Lower the managed-blob count by one.
public(package) fun decrease_managed_blobs(system_cfg: &mut SystemConfig) {
    let old_m_blob = system_cfg.managed_blobs;
    system_cfg.managed_blobs = old_m_blob - 1;
}

/// Mutable access to the system treasury.
public(package) fun get_vault_mut(system_cfg: &mut SystemConfig): &mut Vault {
    ofields::borrow_mut<vector<u8>, Vault>(&mut system_cfg.id, SYSTEM_VAULT)
}

/// The system's UID, so sibling modules can attach their own dynamic fields.
public(package) fun uid(system_cfg: &SystemConfig): &UID {
    &system_cfg.id
}

/// Mutable access to the system's UID, so sibling modules can attach their own
/// dynamic fields.
public(package) fun uid_mut(system_cfg: &mut SystemConfig): &mut UID {
    &mut system_cfg.id
}

/// Raise the system to the package version.
public(package) fun update_version(system_cfg: &mut SystemConfig) {
    assert!(system_cfg.version < version::get_version(), 1);

    system_cfg.version = version::get_version();
}

/// Overwrite the registry modification fees.
public(package) fun set_costs(
    system: &mut SystemConfig,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
) {
    system.user_modification_cfg.cost_change_apikey_forms = cost_change_apikey_forms;
    system.user_modification_cfg.cost_to_migrate_system = cost_to_migrate_system;
    system.user_modification_cfg.cost_to_update_name = cost_to_update_name;
}

/// Record `new_system_id` as the system minted after `system_cfg`.
public(package) fun set_next_system(system_cfg: &mut SystemConfig, new_system_id: ID) {
    option::fill(&mut system_cfg.mint_cap.next_system, new_system_id);
}

/// Build a system descending from `previous_system`, with its treasury and user
/// index already attached. The caller decides custody.
public(package) fun new(
    previous_system: ID,
    version: u64,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    ctx: &mut TxContext,
): SystemConfig {
    let mut system_cfg = SystemConfig {
        id: object::new(ctx),
        warlot_allowed_address: ctx.sender(),
        users: 0,
        managed_blobs: 0,
        version,
        mint_cap: SystemMintCap {
            previous_system,
            next_system: option::none(),
        },
        user_modification_cfg: UserMdCfg {
            cost_change_apikey_forms,
            cost_to_migrate_system,
            cost_to_update_name,
            cost_to_delete,
        },
    };

    let mut vault = vault::create_vault(ctx);
    vault::add_supported_coin<WAL>(&mut vault);
    ofields::add(&mut system_cfg.id, SYSTEM_VAULT, vault);

    dfield::add<vector<u8>, TableVec<address>>(
        &mut system_cfg.id,
        USERINDEX,
        table_vec::empty<address>(ctx),
    );
    dfield::add<vector<u8>, Table<address, u64>>(
        &mut system_cfg.id,
        USER_INDEX_MAP,
        table::new<address, u64>(ctx),
    );

    system_cfg
}

// === Private functions ===

/// Initialize the system and mint the first `AdminCap` in the original state.
fun init(ctx: &mut TxContext) {
    let system_cfg = new(
        object::id_from_address(@0x0),
        VERSION,
        100,
        100,
        100,
        100,
        ctx,
    );

    let admin = admin_cap::new(
        object::id(&system_cfg),
        admin_cap::state_original(),
        0,
        ctx,
    );

    transfer::public_share_object(system_cfg);
    admin_cap::transfer_to(admin, ctx.sender());
}

// === Test-only helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
