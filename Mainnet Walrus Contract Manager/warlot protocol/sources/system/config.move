/// Holds `SystemConfig`: the protocol's version, fees, mint lineage and treasury.
module warlot::system_config;

// === Imports ===

use sui::dynamic_object_field as ofields;
use wal::wal::WAL;
use warlot::{
    admin_cap::{Self, AdminCap},
    operator::{Self, OperatorSet},
    system_events,
    vault::{Self, Vault},
    version
};

// === Errors ===

#[error]
const EVersionNotOlder: vector<u8> = b"SYSTEM IS ALREADY AT THE PACKAGE VERSION";
#[error]
const EInvalidTierTable: vector<u8> = b"A TIER TABLE MUST BE SHORT, NON-EMPTY AND STRICTLY ASCENDING";
#[error]
const ETierTableExceedsHorizon: vector<u8> =
    b"THE TOP TIER AND ITS RESERVE EPOCH MUST FIT INSIDE THE STORAGE HORIZON";

// === Constants ===

/// The storage terms the protocol sells, in epochs.
///
/// Chosen by nearest epoch against a two-week mainnet epoch: roughly two weeks,
/// one month, three months, six months, nine months, a year and two years. The
/// same numbers serve both networks; only the human label differs.
const DEFAULT_TIER_TABLE: vector<u32> = vector[1, 2, 7, 13, 20, 26, 52];

/// How far ahead storage may be bought, in epochs.
///
/// Kept here rather than read from Walrus so that a change upstream becomes a
/// refused registration attributable to one tier, rather than a renewal that
/// fails months later inside a batch.
const DEFAULT_MAX_EPOCHS_AHEAD: u32 = 53;

/// The longest tier table the system will hold. A tier table lives inline on a
/// shared object and is scanned on every registration, so it is bounded for the
/// same reason every other on-object vector is.
const MAX_TIER_COUNT: u64 = 16;

/// Dynamic object field key for the protocol treasury.
const SYSTEM_VAULT: vector<u8> = b"system_vault";

// === Structs ===

/// The shared object holding the protocol's configuration and treasury.
public struct SystemConfig has key, store {
    id: UID,
    /// The capabilities this system accepts as backend operator credentials.
    ///
    /// Replaces the single `warlot_allowed_address` this field used to hold. That
    /// address was fixed at `mint_system` and had no setter, so a system
    /// supported exactly one backend key: a second signing wallet held nothing,
    /// and a lost first key could not be rotated without every user re-granting
    /// by hand.
    operators: OperatorSet,
    /// The upgrade gate. Equal to the package version while the system is current.
    version: u64,
    /// Enforces that systems are minted in a single chain.
    mint_cap: SystemMintCap,
    /// The fees charged for registry modifications.
    user_modification_cfg: UserMdCfg,
    /// The storage terms this system sells, strictly ascending.
    tier_table: vector<u32>,
    /// How far ahead this system will let storage be bought, in epochs.
    max_epochs_ahead: u32,
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

/// The storage terms this system sells, in epochs, strictly ascending.
public fun tier_table(system_cfg: &SystemConfig): &vector<u32> {
    &system_cfg.tier_table
}

/// How far ahead this system will let storage be bought, in epochs.
public fun max_epochs_ahead(system_cfg: &SystemConfig): u32 {
    system_cfg.max_epochs_ahead
}

/// The capabilities this system accepts as backend operator credentials.
public fun operator_set(system_cfg: &SystemConfig): &OperatorSet {
    &system_cfg.operators
}

/// Abort unless `admin_cap` is a live operator credential for this system, and
/// hand back the proof that it is.
///
/// Written once here rather than at each entry point that offers an operator
/// sibling: every one of them needs the same four checks against the same set,
/// and a copy of the call that drifted would be an authorisation gate that is
/// weaker in one place than in the others.
public fun authorise_operator(
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    now_ms: u64,
): operator::OperatorAuth {
    operator::authorise(&system_cfg.operators, admin_cap, object::id(system_cfg), now_ms)
}

/// The fee charged to delete a registry.
public fun cost_to_delete(system_cfg: &SystemConfig): u64 {
    system_cfg.user_modification_cfg.cost_to_delete
}

/// Abort unless this system is at the package version.
///
/// The gate every public entry point opens with. Its purpose is to fence a
/// half-migrated state: after a package upgrade the old code and the new code can
/// both still be called, and until the system is raised to the new version only
/// the code that agrees with it may act on it.
public fun assert_version(system_cfg: &SystemConfig) {
    version::panic_invalid(system_cfg.version);
}

/// The balance of `T` held in the system vault.
public fun get_system_balance<T>(system_cfg: &SystemConfig): u64 {
    let vault = ofields::borrow<vector<u8>, Vault>(&system_cfg.id, SYSTEM_VAULT);
    vault::balance_of<T>(vault)
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
public(package) fun update_version(system_cfg: &mut SystemConfig, migrated_by: address) {
    assert!(system_cfg.version < version::get_version(), EVersionNotOlder);

    system_cfg.version = version::get_version();

    system_events::emit_system_version_migrated(
        object::id(system_cfg),
        system_cfg.version,
        migrated_by,
    );
}

/// Overwrite the registry modification fees.
///
/// Every fee, including the deletion fee the previous form left behind: a partial
/// setter means one of the four can only ever hold whatever it was given when the
/// system was minted.
public(package) fun set_costs(
    system: &mut SystemConfig,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    changed_by: address,
) {
    system.user_modification_cfg.cost_change_apikey_forms = cost_change_apikey_forms;
    system.user_modification_cfg.cost_to_migrate_system = cost_to_migrate_system;
    system.user_modification_cfg.cost_to_update_name = cost_to_update_name;
    system.user_modification_cfg.cost_to_delete = cost_to_delete;

    system_events::emit_system_fees_changed(
        object::id(system),
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
        changed_by,
    );
}

/// Replace the storage terms this system sells and the horizon they sit inside.
///
/// The table is validated rather than trusted: it must be short enough to scan
/// cheaply, strictly ascending so the top tier is unambiguous, and it must leave
/// room for the reserve epoch above its longest term.
public(package) fun set_tier_table(
    system_cfg: &mut SystemConfig,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    changed_by: address,
) {
    assert_tier_table(&tier_table, max_epochs_ahead);

    system_cfg.tier_table = tier_table;
    system_cfg.max_epochs_ahead = max_epochs_ahead;

    system_events::emit_system_tiers_changed(
        object::id(system_cfg),
        tier_table,
        max_epochs_ahead,
        changed_by,
    );
}

/// Give `admin_cap` a slot in the operator set it does not already hold.
public(package) fun enrol_operator(
    system_cfg: &mut SystemConfig,
    admin_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    now_ms: u64,
    enrolled_by: address,
) {
    operator::enrol(&mut system_cfg.operators, admin_cap, until_ms, may_bypass_draft, now_ms);

    system_events::emit_system_operator_enrolled(
        object::id(system_cfg),
        admin_cap,
        until_ms,
        may_bypass_draft,
        enrolled_by,
    );
}

/// Replace the terms of a slot `admin_cap` already holds.
public(package) fun refresh_operator(
    system_cfg: &mut SystemConfig,
    admin_cap: ID,
    until_ms: u64,
    may_bypass_draft: bool,
    now_ms: u64,
    refreshed_by: address,
) {
    operator::refresh(&mut system_cfg.operators, admin_cap, until_ms, may_bypass_draft, now_ms);

    system_events::emit_system_operator_refreshed(
        object::id(system_cfg),
        admin_cap,
        until_ms,
        may_bypass_draft,
        refreshed_by,
    );
}

/// Drop `admin_cap`'s slot in the operator set.
///
/// Announced only when a slot was there to drop, so the stream never reports a
/// retirement that did not happen. Retiring an id that holds no slot leaves the
/// caller with the state they asked for and is not an error.
public(package) fun retire_operator(
    system_cfg: &mut SystemConfig,
    admin_cap: ID,
    retired_by: address,
) {
    if (!operator::remove(&mut system_cfg.operators, admin_cap)) {
        return
    };

    system_events::emit_system_operator_retired(object::id(system_cfg), admin_cap, retired_by);
}

/// Record `new_system_id` as the system minted after `system_cfg`.
public(package) fun set_next_system(
    system_cfg: &mut SystemConfig,
    new_system_id: ID,
    minted_by: address,
) {
    option::fill(&mut system_cfg.mint_cap.next_system, new_system_id);

    system_events::emit_system_succeeded(object::id(system_cfg), new_system_id, minted_by);
}

/// Build a system descending from `previous_system`, with its treasury already
/// attached. The caller decides custody.
public(package) fun new(
    previous_system: ID,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    ctx: &mut TxContext,
): SystemConfig {
    assert_tier_table(&tier_table, max_epochs_ahead);

    let mut system_cfg = SystemConfig {
        id: object::new(ctx),
        // A system opens with no operator. The capability minted beside it is an
        // original, and an original is refused as a credential, so the hot key
        // has to be minted and enrolled deliberately.
        operators: operator::empty(),
        // The field is the upgrade gate, not a position in the mint chain: a system
        // is born at the version of the package that minted it, or it is born
        // unusable.
        version: version::get_version(),
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
        tier_table,
        max_epochs_ahead,
    };

    let mut vault = vault::create_vault(object::id(&system_cfg), ctx);
    vault::support_coin_on_creation<WAL>(&mut vault);
    ofields::add(&mut system_cfg.id, SYSTEM_VAULT, vault);

    system_events::emit_system_created(
        object::id(&system_cfg),
        previous_system,
        ctx.sender(),
        system_cfg.version,
        system_cfg.tier_table,
        system_cfg.max_epochs_ahead,
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
    );

    system_cfg
}

// === Private functions ===

/// Abort unless `tier_table` is a table this system can sell from.
fun assert_tier_table(tier_table: &vector<u32>, max_epochs_ahead: u32) {
    let count = tier_table.length();
    assert!(count > 0 && count <= MAX_TIER_COUNT, EInvalidTierTable);

    let mut i = 1;
    while (i < count) {
        assert!(tier_table[i - 1] < tier_table[i], EInvalidTierTable);
        i = i + 1;
    };

    // The longest term is registered one epoch above itself, so that a blob on it
    // is never sitting on the ceiling with nowhere left to extend to.
    assert!(tier_table[count - 1] < max_epochs_ahead, ETierTableExceedsHorizon);
}

/// Initialize the system and mint the first `AdminCap` in the original state.
fun init(ctx: &mut TxContext) {
    let system_cfg = new(
        object::id_from_address(@0x0),
        100,
        100,
        100,
        100,
        DEFAULT_TIER_TABLE,
        DEFAULT_MAX_EPOCHS_AHEAD,
        ctx,
    );

    let admin = admin_cap::new(
        object::id(&system_cfg),
        admin_cap::state_original(),
        0,
        ctx,
    );

    transfer::public_share_object(system_cfg);
    admin_cap::transfer_to(admin, ctx.sender(), ctx);
}

// === Test-only helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun set_version_for_testing(system_cfg: &mut SystemConfig, version: u64) {
    system_cfg.version = version;
}
