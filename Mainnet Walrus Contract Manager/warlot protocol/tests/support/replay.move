/// An off-chain consumer, built from nothing but the event stream.
///
/// The next scope deletes on-chain state on the grounds that this stream can
/// rebuild it. That is only true if a replay from genesis reproduces what the
/// chain holds, so the replay is written here and compared against the chain
/// rather than described.
///
/// Two things make it a real reconstruction rather than a restatement:
///
/// 1. **Aggregates are derived, not copied.** The registered-user count, the
///    treasury and wallet balances, the open-draft count and the deny count are
///    accumulated from the deltas the events carry, and only then compared with
///    the counters the chain keeps. Reading a count out of an event and asserting
///    the chain agrees would prove only that the emitter can read a field.
/// 2. **The replay refuses to ignore anything.** `absorb` counts the events it
///    consumed and asserts that against `event::num_events()`, so an event type
///    the ledger does not know how to apply fails the rebuild instead of being
///    quietly dropped. Adding an event to the protocol and not teaching the
///    ledger about it is a test failure, which is the property that keeps this
///    from decaying into a green tick.
///
/// **The one thing a Move test cannot see.** `event::events_by_type` returns the
/// events of one type raised in the current transaction, in emission order, and
/// the buffer is cleared by `next_tx`. So the harness has to drain after every
/// transaction, and it cannot observe the relative order of two *different*
/// types within one transaction. It applies types in a fixed dependency order
/// instead ,  creations, then mutations, then removals. A real consumer has the
/// envelope's event sequence number and needs none of this.
#[test_only]
module warlot::replay;

// === Imports ===

use std::string::String;
use sui::event;
use walrus::events::{BlobCertified, BlobDeleted, BlobRegistered};
use warlot::{
    draft_events::{Self, DraftDeleted, DraftMerged, DraftPinned},
    identity_events::{
        Self,
        OperatorRoleGranted,
        OperatorRoleRevoked,
        PermissionGranted,
        PermissionRevoked,
        RegistryMigrated,
        UserJoinedSystem,
        UserLeftSystem,
        UserRegistered,
        UsernameUpdated,
        WalletCreated,
        WalletDeposited,
        WalletWithdrawn
    },
    innerfile_events::{
        Self,
        FileOperatorPolicySet,
        HeadAdvanced,
        InnerFileCreated,
        RevisionRetired,
        RootChangeRemoved,
        RootChangeSet
    },
    pass_events::{
        Self,
        WriterDenied,
        WriterPassDestroyed,
        WriterPassMinted,
        WriterPassRevoked,
        WriterUndenied
    },
    storage_events::{
        Self,
        BlobConfigOwnerChanged,
        BlobRenewed,
        BlobStored,
        BlobWithdrawn,
        ForeignBlobsAdopted,
        RenewCycleSpent,
        RenewSkipped
    },
    system_events::{
        Self,
        AdminCapMinted,
        SystemCreated,
        SystemFeesChanged,
        SystemOperatorEnrolled,
        SystemOperatorRefreshed,
        SystemOperatorRetired,
        SystemSucceeded,
        SystemTiersChanged,
        SystemVersionMigrated
    },
    treasury_events::{Self, SystemWithdraw, VaultCoinSupportChanged, VaultDeposited},
    upgrade_events::{
        Self,
        UpgradeAuthorised,
        UpgradeAuthorityCreated,
        UpgradeAuthorityDestroyed,
        UpgradeCommitted,
        UpgradePolicyRestricted
    }
};

// === Errors ===

const EUnknownEventType: u64 = 0;

/// The address a delegation row carries when it is the operator role rather than
/// a grant to a named key. The role names no address, so the reconstruction needs
/// a key of its own for it, and the zero address is one no signer can hold.
const OPERATOR_ROLE: address = @0x0;
const ENoSuchRow: u64 = 1;

// === Structs ===

/// One system, as the stream describes it.
public struct SystemRow has drop {
    system_id: ID,
    previous_system: ID,
    next_system: Option<ID>,
    version: u64,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    /// Joins minus leaves. The chain keeps no such counter any more, so this is
    /// the only place the number exists at all.
    users: u64,
    /// Deposits minus payouts, never read off an event.
    vault_wal: u64,
    accepted_coins: vector<String>,
    admin_caps: vector<ID>,
    /// The operator slots the stream shows live, and their terms.
    operator_caps: vector<ID>,
    operator_until: vector<u64>,
    operator_bypass: vector<bool>,
}

/// One user, as the stream describes them.
public struct UserRow has drop {
    user: address,
    user_id: ID,
    system_id: ID,
    registry_id: ID,
    public_username: String,
    created_at: u64,
    decay_at: u64,
    updated_at: u64,
    wallet_id: ID,
    /// Deposits minus withdrawals, never read off an event.
    wallet_wal: u64,
    /// The configs the stream says this user adopted from outside the protocol.
    foreign_configs: vector<ID>,
    /// How many blobs those adoptions carried.
    foreign_blobs: u64,
    joined: bool,
}

/// One delegation row.
///
/// `delegate` is the address the bits were granted to, and is the zero address on
/// the row that carries the operator role ,  which names no address by design, so
/// the stream has nothing else to key it by.
public struct PermRow has drop {
    system_id: ID,
    owner: address,
    delegate: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
    can_set_root: bool,
    live: bool,
}

/// One blob config.
public struct ConfigRow has drop {
    config_id: ID,
    system_id: ID,
    owner: address,
    stored_by: address,
    blobs_obj_id: vector<ID>,
    blob_sizes: vector<u64>,
    size: u64,
    encoded_size: u64,
    end_epoch: u32,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    uploaded_on: u64,
    wal_spent: u64,
    renewals: u64,
    skips: u64,
    live: bool,
}

/// One inner file, its rollback window newest first.
public struct FileRow has drop {
    file_id: ID,
    system_id: ID,
    owner: address,
    created_by: address,
    writers_length: u8,
    track_back_length: u8,
    epoch_set: u32,
    cycle_end: Option<u64>,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    operators_may_draft: bool,
    created_at_ms: u64,
    last_modified: u64,
    window_commits: vector<vector<u8>>,
    window_configs: vector<ID>,
    window_authors: vector<address>,
    root_change: Option<ID>,
    root_commit: vector<u8>,
    /// Pins minus merges and deletes, never read off an event.
    total_draft: u64,
    /// One past the highest index ever pinned, never read off an event.
    available_index: u64,
    retired: u64,
}

/// One writer pass, and whether it can still be presented.
public struct PassRow has drop {
    file_id: ID,
    pass_id: ID,
    holder: address,
    duration: u64,
    admin_privilege: bool,
    revoked: bool,
    destroyed: bool,
}

/// One denial recorded on a file.
public struct DenyRow has drop {
    file_id: ID,
    writer: address,
    until_ms: u64,
    live: bool,
}

/// Everything the stream says the chain holds.
/// The package's upgrade authority, as the stream describes it.
public struct UpgradeRow has drop {
    authority_id: ID,
    system_id: ID,
    /// The package the authority governs, moved on by every commit.
    package: ID,
    version: u64,
    policy: u8,
    /// False once the authority has been destroyed and the package frozen.
    live: bool,
}

public struct Ledger has drop {
    systems: vector<SystemRow>,
    users: vector<UserRow>,
    permissions: vector<PermRow>,
    configs: vector<ConfigRow>,
    files: vector<FileRow>,
    passes: vector<PassRow>,
    denials: vector<DenyRow>,
    upgrades: vector<UpgradeRow>,
    /// How many events the replay has applied, for the completeness guard.
    applied: u64,
}

// === Public functions ===

/// An empty off-chain view, before a single event.
public fun new(): Ledger {
    Ledger {
        systems: vector[],
        users: vector[],
        permissions: vector[],
        configs: vector[],
        files: vector[],
        passes: vector[],
        denials: vector[],
        upgrades: vector[],
        applied: 0,
    }
}

/// Apply every event raised in the current transaction, and prove none was left.
///
/// Must be called before `next_tx`, which clears the buffer. The count assertion
/// is what stops the replay from being a restatement of the events it happens to
/// understand: an event type it cannot apply makes the total disagree.
public fun absorb(ledger: &mut Ledger) {
    let before = ledger.applied;

    // Creations first, then the mutations that name them, then the removals.
    ledger.apply_system();
    ledger.apply_upgrade();
    ledger.apply_treasury();
    ledger.apply_identity();
    ledger.apply_storage();
    ledger.apply_innerfile();

    let consumed = ledger.applied - before;

    // Every event raised in this transaction is either one the ledger applied or
    // one Walrus raised. A protocol event nobody taught the ledger about makes
    // the two sides disagree, which is the point.
    assert!(consumed + walrus_events() == (event::num_events() as u64), EUnknownEventType);
}

// === View functions ===

/// The reconstructed system, or an abort if the stream never announced one.
public fun system(ledger: &Ledger, system_id: ID): &SystemRow {
    let i = ledger.systems.find_index!(|row| row.system_id == system_id);
    assert!(i.is_some(), ENoSuchRow);
    &ledger.systems[i.destroy_some()]
}

/// The reconstructed user.
public fun user(ledger: &Ledger, user: address): &UserRow {
    let i = ledger.users.find_index!(|row| row.user == user);
    assert!(i.is_some(), ENoSuchRow);
    &ledger.users[i.destroy_some()]
}

/// The reconstructed blob config.
public fun config(ledger: &Ledger, config_id: ID): &ConfigRow {
    let i = ledger.configs.find_index!(|row| row.config_id == config_id);
    assert!(i.is_some(), ENoSuchRow);
    &ledger.configs[i.destroy_some()]
}

/// The reconstructed inner file.
public fun file(ledger: &Ledger, file_id: ID): &FileRow {
    let i = ledger.files.find_index!(|row| row.file_id == file_id);
    assert!(i.is_some(), ENoSuchRow);
    &ledger.files[i.destroy_some()]
}

/// The reconstructed upgrade authority.
public fun upgrade(ledger: &Ledger, authority_id: ID): &UpgradeRow {
    let i = ledger.upgrades.find_index!(|row| row.authority_id == authority_id);
    assert!(i.is_some(), ENoSuchRow);
    &ledger.upgrades[i.destroy_some()]
}

/// The reconstructed writer pass.
public fun pass(ledger: &Ledger, pass_id: ID): &PassRow {
    let i = ledger.passes.find_index!(|row| row.pass_id == pass_id);
    assert!(i.is_some(), ENoSuchRow);
    &ledger.passes[i.destroy_some()]
}

/// Whether the stream still shows `delegate` holding capabilities on `owner`.
public fun delegation_live(ledger: &Ledger, owner: address, delegate: address): bool {
    let i = ledger.permissions.find_index!(|row| row.owner == owner && row.delegate == delegate);
    if (i.is_none()) return false;
    ledger.permissions[i.destroy_some()].live
}

/// The capability bits the stream shows `delegate` holding, in declaration order.
public fun delegation_bits(
    ledger: &Ledger,
    owner: address,
    delegate: address,
): (bool, bool, bool, bool, bool, bool) {
    let i = ledger.permissions.find_index!(|row| row.owner == owner && row.delegate == delegate);
    assert!(i.is_some(), ENoSuchRow);
    let row = &ledger.permissions[i.destroy_some()];

    (
        row.add_blob_to_address,
        row.create_inner_file,
        row.create_writer_pass,
        row.can_init_db,
        row.can_compact,
        row.can_set_root,
    )
}

/// Whether the stream still shows the operator role holding capabilities on
/// `owner`.
public fun operator_role_live(ledger: &Ledger, owner: address): bool {
    ledger.delegation_live(owner, OPERATOR_ROLE)
}

/// The capability bits the stream shows the operator role holding on `owner`.
public fun operator_role_bits(
    ledger: &Ledger,
    owner: address,
): (bool, bool, bool, bool, bool, bool) {
    ledger.delegation_bits(owner, OPERATOR_ROLE)
}

/// Whether the stream shows `file_id` admitting operators, and which of the two
/// routes it leaves them: straight into history, into the draft queue, or both.
public fun file_operator_policy(ledger: &Ledger, file_id: ID): (bool, bool, bool) {
    let i = ledger.files.find_index!(|row| row.file_id == file_id);
    assert!(i.is_some(), ENoSuchRow);
    let row = &ledger.files[i.destroy_some()];

    (row.operators_allowed, row.operators_may_bypass_draft, row.operators_may_draft)
}

/// How many writers the stream shows `file_id` denying.
public fun denials_live(ledger: &Ledger, file_id: ID): u64 {
    let mut count = 0;
    ledger.denials.do_ref!(|row| if (row.file_id == file_id && row.live) count = count + 1);
    count
}

/// The deadline the stream shows for one denial; zero means indefinitely.
public fun denial_until(ledger: &Ledger, file_id: ID, writer: address): u64 {
    let i = ledger.denials.find_index!(|row| row.file_id == file_id && row.writer == writer);
    assert!(i.is_some(), ENoSuchRow);
    ledger.denials[i.destroy_some()].until_ms
}

/// The blobs the stream says came back to `owner` outright: every blob held by a
/// config of theirs that the stream shows destroyed.
///
/// A replay that could not represent a removal would report none of these, and
/// would still show the content sitting in custody it left long ago.
public fun released_blobs(ledger: &Ledger, owner: address): vector<ID> {
    let mut ids = vector<ID>[];
    ledger.configs.do_ref!(|row| {
        if (row.owner == owner && !row.live) {
            row.blobs_obj_id.do_ref!(|blob_id| ids.push_back(*blob_id));
        };
    });
    ids
}

/// How many configs the stream still shows alive under `owner`.
public fun live_configs(ledger: &Ledger, owner: address): u64 {
    let mut count = 0;
    ledger.configs.do_ref!(|row| if (row.owner == owner && row.live) count = count + 1);
    count
}

/// How many events the replay has applied.
public fun applied(ledger: &Ledger): u64 { ledger.applied }

// === View functions ,  upgrade rows ===

public fun upgrade_system(row: &UpgradeRow): ID { row.system_id }

public fun upgrade_package(row: &UpgradeRow): ID { row.package }

public fun upgrade_version(row: &UpgradeRow): u64 { row.version }

public fun upgrade_policy(row: &UpgradeRow): u8 { row.policy }

public fun upgrade_live(row: &UpgradeRow): bool { row.live }

// === View functions ,  system rows ===

public fun system_users(row: &SystemRow): u64 { row.users }

public fun system_vault_wal(row: &SystemRow): u64 { row.vault_wal }

public fun system_version(row: &SystemRow): u64 { row.version }

public fun system_previous(row: &SystemRow): ID { row.previous_system }

public fun system_next(row: &SystemRow): Option<ID> { row.next_system }

public fun system_tier_table(row: &SystemRow): vector<u32> { row.tier_table }

public fun system_max_epochs_ahead(row: &SystemRow): u32 { row.max_epochs_ahead }

/// The capability ids the stream shows holding an operator slot.
public fun system_operator_caps(row: &SystemRow): vector<ID> { row.operator_caps }

/// Whether the stream shows `admin_cap` holding an operator slot.
public fun system_has_operator(row: &SystemRow, admin_cap: ID): bool {
    row.operator_caps.contains(&admin_cap)
}

/// The terms the stream shows for one operator slot.
public fun system_operator_terms(row: &SystemRow, admin_cap: ID): (u64, bool) {
    let i = row.operator_caps.find_index!(|cap| *cap == admin_cap);
    assert!(i.is_some(), ENoSuchRow);
    let i = i.destroy_some();

    (row.operator_until[i], row.operator_bypass[i])
}

public fun system_costs(row: &SystemRow): (u64, u64, u64, u64) {
    (
        row.cost_change_apikey_forms,
        row.cost_to_migrate_system,
        row.cost_to_update_name,
        row.cost_to_delete,
    )
}

public fun system_accepts(row: &SystemRow, coin_type: String): bool {
    row.accepted_coins.contains(&coin_type)
}

public fun system_admin_caps(row: &SystemRow): vector<ID> { row.admin_caps }

// === View functions ,  user rows ===

public fun user_id(row: &UserRow): ID { row.user_id }

public fun user_system(row: &UserRow): ID { row.system_id }

public fun user_registry(row: &UserRow): ID { row.registry_id }

public fun user_username(row: &UserRow): String { row.public_username }

public fun user_created_at(row: &UserRow): u64 { row.created_at }

public fun user_decay_at(row: &UserRow): u64 { row.decay_at }

public fun user_updated_at(row: &UserRow): u64 { row.updated_at }

public fun user_wallet(row: &UserRow): ID { row.wallet_id }

public fun user_wallet_wal(row: &UserRow): u64 { row.wallet_wal }

public fun user_foreign_configs(row: &UserRow): vector<ID> { row.foreign_configs }

public fun user_foreign_blobs(row: &UserRow): u64 { row.foreign_blobs }

public fun user_joined(row: &UserRow): bool { row.joined }

// === View functions ,  config rows ===

public fun config_owner(row: &ConfigRow): address { row.owner }

public fun config_stored_by(row: &ConfigRow): address { row.stored_by }

public fun config_blobs(row: &ConfigRow): vector<ID> { row.blobs_obj_id }

public fun config_blob_sizes(row: &ConfigRow): vector<u64> { row.blob_sizes }

public fun config_size(row: &ConfigRow): u64 { row.size }

public fun config_encoded_size(row: &ConfigRow): u64 { row.encoded_size }

public fun config_end_epoch(row: &ConfigRow): u32 { row.end_epoch }

public fun config_epoch_set(row: &ConfigRow): u32 { row.epoch_set }

public fun config_cycle_limit(row: &ConfigRow): Option<u64> { row.cycle_limit }

public fun config_uploaded_on(row: &ConfigRow): u64 { row.uploaded_on }

public fun config_wal_spent(row: &ConfigRow): u64 { row.wal_spent }

public fun config_renewals(row: &ConfigRow): u64 { row.renewals }

public fun config_skips(row: &ConfigRow): u64 { row.skips }

public fun config_live(row: &ConfigRow): bool { row.live }

// === View functions ,  file rows ===

public fun file_owner(row: &FileRow): address { row.owner }

public fun file_created_by(row: &FileRow): address { row.created_by }

public fun file_system(row: &FileRow): ID { row.system_id }

public fun file_writers_length(row: &FileRow): u8 { row.writers_length }

public fun file_track_back_length(row: &FileRow): u8 { row.track_back_length }

public fun file_epoch_set(row: &FileRow): u32 { row.epoch_set }

public fun file_cycle_end(row: &FileRow): Option<u64> { row.cycle_end }

public fun file_created_at_ms(row: &FileRow): u64 { row.created_at_ms }

public fun file_last_modified(row: &FileRow): u64 { row.last_modified }

public fun file_window_commits(row: &FileRow): vector<vector<u8>> { row.window_commits }

public fun file_window_configs(row: &FileRow): vector<ID> { row.window_configs }

public fun file_window_authors(row: &FileRow): vector<address> { row.window_authors }

public fun file_root_change(row: &FileRow): Option<ID> { row.root_change }

public fun file_root_commit(row: &FileRow): vector<u8> { row.root_commit }

public fun file_total_draft(row: &FileRow): u64 { row.total_draft }

public fun file_available_index(row: &FileRow): u64 { row.available_index }

public fun file_retired(row: &FileRow): u64 { row.retired }

// === View functions ,  pass rows ===

public fun pass_file(row: &PassRow): ID { row.file_id }

public fun pass_holder(row: &PassRow): address { row.holder }

public fun pass_duration(row: &PassRow): u64 { row.duration }

public fun pass_admin_privilege(row: &PassRow): bool { row.admin_privilege }

public fun pass_revoked(row: &PassRow): bool { row.revoked }

public fun pass_destroyed(row: &PassRow): bool { row.destroyed }

// === Private functions ===

/// The events Walrus raises under the fixtures' own calls, which the protocol
/// neither owns nor replays.
fun walrus_events(): u64 {
    event::events_by_type<BlobRegistered>().length() +
    event::events_by_type<BlobCertified>().length() +
    event::events_by_type<BlobDeleted>().length()
}

fun system_mut(ledger: &mut Ledger, system_id: ID): &mut SystemRow {
    let i = ledger.systems.find_index!(|row| row.system_id == system_id);
    assert!(i.is_some(), ENoSuchRow);
    &mut ledger.systems[i.destroy_some()]
}

fun upgrade_mut(ledger: &mut Ledger, authority_id: ID): &mut UpgradeRow {
    let i = ledger.upgrades.find_index!(|row| row.authority_id == authority_id);
    assert!(i.is_some(), ENoSuchRow);
    &mut ledger.upgrades[i.destroy_some()]
}

fun user_mut(ledger: &mut Ledger, user: address): &mut UserRow {
    let i = ledger.users.find_index!(|row| row.user == user);
    assert!(i.is_some(), ENoSuchRow);
    &mut ledger.users[i.destroy_some()]
}

fun config_mut(ledger: &mut Ledger, config_id: ID): &mut ConfigRow {
    let i = ledger.configs.find_index!(|row| row.config_id == config_id);
    assert!(i.is_some(), ENoSuchRow);
    &mut ledger.configs[i.destroy_some()]
}

fun file_mut(ledger: &mut Ledger, file_id: ID): &mut FileRow {
    let i = ledger.files.find_index!(|row| row.file_id == file_id);
    assert!(i.is_some(), ENoSuchRow);
    &mut ledger.files[i.destroy_some()]
}

fun apply_system(ledger: &mut Ledger) {
    event::events_by_type<SystemCreated>().do_ref!(|e| {
        let (
            system_id,
            previous_system,
            _minted_by,
            version,
            tier_table,
            max_epochs_ahead,
            cost_change_apikey_forms,
            cost_to_migrate_system,
            cost_to_update_name,
            cost_to_delete,
        ) = system_events::read_system_created(e);

        ledger.systems.push_back(SystemRow {
            system_id,
            previous_system,
            next_system: option::none(),
            version,
            tier_table,
            max_epochs_ahead,
            cost_change_apikey_forms,
            cost_to_migrate_system,
            cost_to_update_name,
            cost_to_delete,
            users: 0,
            vault_wal: 0,
            accepted_coins: vector[],
            admin_caps: vector[],
            operator_caps: vector[],
            operator_until: vector[],
            operator_bypass: vector[],
        });
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemSucceeded>().do_ref!(|e| {
        let (system_id, next_system, _) = system_events::read_system_succeeded(e);
        ledger.system_mut(system_id).next_system.fill(next_system);
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemFeesChanged>().do_ref!(|e| {
        let (system_id, apikey, migrate, name, del, _) = system_events::read_system_fees_changed(e);
        let row = ledger.system_mut(system_id);
        row.cost_change_apikey_forms = apikey;
        row.cost_to_migrate_system = migrate;
        row.cost_to_update_name = name;
        row.cost_to_delete = del;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemTiersChanged>().do_ref!(|e| {
        let (system_id, tier_table, max_epochs_ahead, _) =
            system_events::read_system_tiers_changed(e);
        let row = ledger.system_mut(system_id);
        row.tier_table = tier_table;
        row.max_epochs_ahead = max_epochs_ahead;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemVersionMigrated>().do_ref!(|e| {
        let (system_id, version, _) = system_events::read_system_version_migrated(e);
        ledger.system_mut(system_id).version = version;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<AdminCapMinted>().do_ref!(|e| {
        let (system_id, admin_cap, _state, _total, _recipient, _minted_by) =
            system_events::read_admin_cap_minted(e);
        ledger.system_mut(system_id).admin_caps.push_back(admin_cap);
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemOperatorEnrolled>().do_ref!(|e| {
        let (system_id, admin_cap, until_ms, may_bypass_draft, _enrolled_by) =
            system_events::read_system_operator_enrolled(e);
        let row = ledger.system_mut(system_id);

        // An enrolment always takes a slot the id did not hold. The chain refuses
        // the other case by name, so a replay that quietly updated in place here
        // would be reproducing a system that does not exist.
        assert!(row.operator_caps.find_index!(|cap| *cap == admin_cap).is_none(), ENoSuchRow);

        row.operator_caps.push_back(admin_cap);
        row.operator_until.push_back(until_ms);
        row.operator_bypass.push_back(may_bypass_draft);
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemOperatorRefreshed>().do_ref!(|e| {
        let (system_id, admin_cap, until_ms, may_bypass_draft, _refreshed_by) =
            system_events::read_system_operator_refreshed(e);
        let row = ledger.system_mut(system_id);

        let held = row.operator_caps.find_index!(|cap| *cap == admin_cap);
        assert!(held.is_some(), ENoSuchRow);

        let i = held.destroy_some();
        *&mut row.operator_until[i] = until_ms;
        *&mut row.operator_bypass[i] = may_bypass_draft;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemOperatorRetired>().do_ref!(|e| {
        let (system_id, admin_cap, _retired_by) = system_events::read_system_operator_retired(e);
        let row = ledger.system_mut(system_id);
        let held = row.operator_caps.find_index!(|cap| *cap == admin_cap);
        if (held.is_some()) {
            let i = held.destroy_some();
            row.operator_caps.remove(i);
            row.operator_until.remove(i);
            row.operator_bypass.remove(i);
        };
        ledger.applied = ledger.applied + 1;
    });
}

fun apply_upgrade(ledger: &mut Ledger) {
    event::events_by_type<UpgradeAuthorityCreated>().do_ref!(|e| {
        let (system_id, authority_id, _upgrade_cap, package, version, policy, _created_by) =
            upgrade_events::read_upgrade_authority_created(e);

        ledger.upgrades.push_back(UpgradeRow {
            authority_id,
            system_id,
            package,
            version,
            policy,
            live: true,
        });
        ledger.applied = ledger.applied + 1;
    });

    // The authorisation moves nothing the reconstruction keeps. Its package id is
    // the one being left behind and its digest names a build, neither of which is
    // state; what makes it worth carrying is that a consumer can tell which build
    // an upgrade installed, and the count below is what makes ignoring it here a
    // deliberate choice rather than an omission.
    event::events_by_type<UpgradeAuthorised>().do_ref!(|e| {
        let (_system_id, authority_id, _package, _policy, _digest, _authorised_by) =
            upgrade_events::read_upgrade_authorised(e);
        ledger.upgrade_mut(authority_id);
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<UpgradePolicyRestricted>().do_ref!(|e| {
        let (_system_id, authority_id, policy, _restricted_by) =
            upgrade_events::read_upgrade_policy_restricted(e);
        ledger.upgrade_mut(authority_id).policy = policy;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<UpgradeCommitted>().do_ref!(|e| {
        let (_system_id, authority_id, package, version, _committed_by) =
            upgrade_events::read_upgrade_committed(e);
        let row = ledger.upgrade_mut(authority_id);
        row.package = package;
        row.version = version;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<UpgradeAuthorityDestroyed>().do_ref!(|e| {
        let (_system_id, authority_id, package, version, _destroyed_by) =
            upgrade_events::read_upgrade_authority_destroyed(e);
        let row = ledger.upgrade_mut(authority_id);
        row.package = package;
        row.version = version;
        row.live = false;
        ledger.applied = ledger.applied + 1;
    });
}

fun apply_treasury(ledger: &mut Ledger) {
    event::events_by_type<VaultCoinSupportChanged>().do_ref!(|e| {
        let (system_id, coin_type, supported) =
            treasury_events::read_vault_coin_support_changed(e);
        let row = ledger.system_mut(system_id);
        let held = row.accepted_coins.find_index!(|c| c == coin_type);
        if (supported) {
            if (held.is_none()) {
                row.accepted_coins.push_back(coin_type);
            } else {
                held.destroy_some();
            };
        } else if (held.is_some()) {
            row.accepted_coins.remove(held.destroy_some());
        };
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<VaultDeposited>().do_ref!(|e| {
        let (system_id, _coin_type, amount, _new_balance) =
            treasury_events::read_vault_deposited(e);
        let row = ledger.system_mut(system_id);
        row.vault_wal = row.vault_wal + amount;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<SystemWithdraw>().do_ref!(|e| {
        let (system_id, _operator, _coin_type, amount, _new_balance) =
            treasury_events::read_system_withdraw(e);
        let row = ledger.system_mut(system_id);
        row.vault_wal = row.vault_wal - amount;
        ledger.applied = ledger.applied + 1;
    });
}

fun apply_identity(ledger: &mut Ledger) {
    event::events_by_type<UserRegistered>().do_ref!(|e| {
        let (system_id, user_id, registry_id, user, public_username, created_at, decay_at) =
            identity_events::read_user_registered(e);

        ledger.users.push_back(UserRow {
            user,
            user_id,
            system_id,
            registry_id,
            public_username,
            created_at,
            decay_at,
            updated_at: created_at,
            wallet_id: user_id,
            wallet_wal: 0,
            foreign_configs: vector<ID>[],
            foreign_blobs: 0,
            joined: false,
        });
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WalletCreated>().do_ref!(|e| {
        let (_system_id, wallet_id, user, _created_at) = identity_events::read_wallet_created(e);
        ledger.user_mut(user).wallet_id = wallet_id;
        ledger.applied = ledger.applied + 1;
    });

    // A migration detaches before it attaches, so removals are applied first ,
    // the reverse order would leave the user a member of neither system.
    event::events_by_type<UserLeftSystem>().do_ref!(|e| {
        let (system_id, user, _user_id) = identity_events::read_user_left_system(e);
        let row = ledger.system_mut(system_id);
        row.users = row.users - 1;
        ledger.user_mut(user).joined = false;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<UserJoinedSystem>().do_ref!(|e| {
        let (system_id, user, _user_id) = identity_events::read_user_joined_system(e);
        let row = ledger.system_mut(system_id);
        row.users = row.users + 1;
        let user_row = ledger.user_mut(user);
        user_row.joined = true;
        user_row.system_id = system_id;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<UsernameUpdated>().do_ref!(|e| {
        let (_system_id, _registry_id, user, public_username) =
            identity_events::read_username_updated(e);
        ledger.user_mut(user).public_username = public_username;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<RegistryMigrated>().do_ref!(|e| {
        let (system_id, _previous_system, _registry_id, user, updated_at) =
            identity_events::read_registry_migrated(e);
        let row = ledger.user_mut(user);
        row.system_id = system_id;
        row.updated_at = updated_at;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WalletDeposited>().do_ref!(|e| {
        let (_system_id, user, _coin_type, amount, _new_balance) =
            identity_events::read_wallet_deposited(e);
        let row = ledger.user_mut(user);
        row.wallet_wal = row.wallet_wal + amount;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WalletWithdrawn>().do_ref!(|e| {
        let (_system_id, user, _coin_type, amount, _new_balance) =
            identity_events::read_wallet_withdrawn(e);
        let row = ledger.user_mut(user);
        row.wallet_wal = row.wallet_wal - amount;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<PermissionGranted>().do_ref!(|e| {
        let (
            system_id,
            owner,
            delegate,
            add_blob_to_address,
            create_inner_file,
            create_writer_pass,
            can_init_db,
            can_compact,
            can_set_root,
        ) = identity_events::read_permission_granted(e);

        let held = ledger
            .permissions
            .find_index!(|row| row.owner == owner && row.delegate == delegate);

        if (held.is_some()) {
            let row = &mut ledger.permissions[held.destroy_some()];
            row.add_blob_to_address = add_blob_to_address;
            row.create_inner_file = create_inner_file;
            row.create_writer_pass = create_writer_pass;
            row.can_init_db = can_init_db;
            row.can_compact = can_compact;
            row.can_set_root = can_set_root;
            row.live = true;
        } else {
            ledger.permissions.push_back(PermRow {
                system_id,
                owner,
                delegate,
                add_blob_to_address,
                create_inner_file,
                create_writer_pass,
                can_init_db,
                can_compact,
                can_set_root,
                live: true,
            });
        };
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<PermissionRevoked>().do_ref!(|e| {
        let (_system_id, owner, delegate) = identity_events::read_permission_revoked(e);
        let held = ledger
            .permissions
            .find_index!(|row| row.owner == owner && row.delegate == delegate);
        if (held.is_some()) {
            ledger.permissions[held.destroy_some()].live = false;
        };
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<OperatorRoleGranted>().do_ref!(|e| {
        let (
            system_id,
            owner,
            add_blob_to_address,
            create_inner_file,
            create_writer_pass,
            can_init_db,
            can_compact,
            can_set_root,
        ) = identity_events::read_operator_role_granted(e);

        let held = ledger
            .permissions
            .find_index!(|row| row.owner == owner && row.delegate == OPERATOR_ROLE);

        if (held.is_some()) {
            let row = &mut ledger.permissions[held.destroy_some()];
            row.add_blob_to_address = add_blob_to_address;
            row.create_inner_file = create_inner_file;
            row.create_writer_pass = create_writer_pass;
            row.can_init_db = can_init_db;
            row.can_compact = can_compact;
            row.can_set_root = can_set_root;
            row.live = true;
        } else {
            ledger.permissions.push_back(PermRow {
                system_id,
                owner,
                delegate: OPERATOR_ROLE,
                add_blob_to_address,
                create_inner_file,
                create_writer_pass,
                can_init_db,
                can_compact,
                can_set_root,
                live: true,
            });
        };
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<OperatorRoleRevoked>().do_ref!(|e| {
        let (_system_id, owner) = identity_events::read_operator_role_revoked(e);
        let held = ledger
            .permissions
            .find_index!(|row| row.owner == owner && row.delegate == OPERATOR_ROLE);
        if (held.is_some()) {
            ledger.permissions[held.destroy_some()].live = false;
        };
        ledger.applied = ledger.applied + 1;
    });
}

fun apply_storage(ledger: &mut Ledger) {
    event::events_by_type<BlobStored>().do_ref!(|e| {
        let (
            system_id,
            config_id,
            owner,
            stored_by,
            blobs_obj_id,
            blob_sizes,
            size,
            encoded_size,
            end_epoch,
            epoch_set,
            cycle_limit,
            uploaded_on,
        ) = storage_events::read_blob_stored(e);

        ledger.configs.push_back(ConfigRow {
            config_id,
            system_id,
            owner,
            stored_by,
            blobs_obj_id,
            blob_sizes,
            size,
            encoded_size,
            end_epoch,
            epoch_set,
            cycle_limit,
            uploaded_on,
            wal_spent: 0,
            renewals: 0,
            skips: 0,
            live: true,
        });
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<BlobConfigOwnerChanged>().do_ref!(|e| {
        let (_system_id, config_id, _previous_owner, new_owner) =
            storage_events::read_blob_config_owner_changed(e);
        ledger.config_mut(config_id).owner = new_owner;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<BlobRenewed>().do_ref!(|e| {
        let (
            _system_id,
            config_id,
            _owner,
            _blob_obj_id,
            _epoch_set,
            _current_epoch,
            _epochs_extended,
            new_end_epoch,
            wal_spent,
            _executed_by,
        ) = storage_events::read_blob_renewed(e);

        let row = ledger.config_mut(config_id);
        row.wal_spent = row.wal_spent + wal_spent;
        row.renewals = row.renewals + 1;
        row.end_epoch = new_end_epoch;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<RenewCycleSpent>().do_ref!(|e| {
        let (_system_id, config_id, _owner, _extended, _wal_spent, cycles_remaining, _by) =
            storage_events::read_renew_cycle_spent(e);
        ledger.config_mut(config_id).cycle_limit = cycles_remaining;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<RenewSkipped>().do_ref!(|e| {
        let (_system_id, config_id, _owner, _blob, _reason, _set, _epoch, _by) =
            storage_events::read_renew_skipped(e);
        let row = ledger.config_mut(config_id);
        row.skips = row.skips + 1;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<ForeignBlobsAdopted>().do_ref!(|e| {
        let (_system_id, owner, _adopted_by, config_id, blob_count) =
            storage_events::read_foreign_blobs_adopted(e);
        let row = ledger.user_mut(owner);
        row.foreign_configs.push_back(config_id);
        row.foreign_blobs = row.foreign_blobs + blob_count;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<BlobWithdrawn>().do_ref!(|e| {
        let (_system_id, config_id, _owner, _blobs_obj_id) =
            storage_events::read_blob_withdrawn(e);
        ledger.config_mut(config_id).live = false;
        ledger.applied = ledger.applied + 1;
    });
}

fun apply_innerfile(ledger: &mut Ledger) {
    event::events_by_type<InnerFileCreated>().do_ref!(|e| {
        let (
            system_id,
            file_id,
            owner,
            created_by,
            writers_length,
            track_back_length,
            epoch_set,
            cycle_end,
            _draft_epoch_duration,
            operators_allowed,
            operators_may_bypass_draft,
            operators_may_draft,
            created_at_ms,
            commit,
            blob_config_id,
        ) = innerfile_events::read_inner_file_created(e);

        ledger.files.push_back(FileRow {
            file_id,
            system_id,
            owner,
            created_by,
            writers_length,
            track_back_length,
            epoch_set,
            cycle_end,
            operators_allowed,
            operators_may_bypass_draft,
            operators_may_draft,
            created_at_ms,
            last_modified: created_at_ms,
            window_commits: vector[commit],
            window_configs: vector[blob_config_id],
            window_authors: vector[created_by],
            root_change: option::none(),
            root_commit: vector[],
            total_draft: 0,
            available_index: 0,
            retired: 0,
        });
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<FileOperatorPolicySet>().do_ref!(|e| {
        let (
            _s,
            file_id,
            operators_allowed,
            operators_may_bypass_draft,
            operators_may_draft,
            _set_by,
        ) = innerfile_events::read_file_operator_policy_set(e);
        let row = ledger.file_mut(file_id);
        row.operators_allowed = operators_allowed;
        row.operators_may_bypass_draft = operators_may_bypass_draft;
        row.operators_may_draft = operators_may_draft;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<DraftPinned>().do_ref!(|e| {
        let (
            _s,
            file_id,
            _draft_id,
            draft_index,
            _credential,
            _credential_kind,
            _issue,
            _c,
            _by,
            _cfg,
            _t,
            last_modified,
        ) = draft_events::read_draft_pinned(e);
        let row = ledger.file_mut(file_id);
        row.total_draft = row.total_draft + 1;
        row.available_index = draft_index + 1;
        row.last_modified = last_modified;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<DraftMerged>().do_ref!(|e| {
        let (_s, file_id, _index, _by, _commit, _cfg, _total, last_modified) =
            draft_events::read_draft_merged(e);
        let row = ledger.file_mut(file_id);
        row.total_draft = row.total_draft - 1;
        row.last_modified = last_modified;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<DraftDeleted>().do_ref!(|e| {
        let (_s, file_id, _index, _by, _total, last_modified) =
            draft_events::read_draft_deleted(e);
        let row = ledger.file_mut(file_id);
        row.total_draft = row.total_draft - 1;
        row.last_modified = last_modified;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<HeadAdvanced>().do_ref!(|e| {
        let (
            _system_id,
            file_id,
            commit,
            commit_by,
            blob_config_id,
            _previous_commit,
            _previous_blob_config,
            window_depth,
            last_modified,
        ) = innerfile_events::read_head_advanced(e);

        let row = ledger.file_mut(file_id);
        row.window_commits.insert(commit, 0);
        row.window_configs.insert(blob_config_id, 0);
        row.window_authors.insert(commit_by, 0);

        // The window is bounded, and the event says where it now ends.
        while (row.window_commits.length() > window_depth) {
            row.window_commits.pop_back();
            row.window_configs.pop_back();
            row.window_authors.pop_back();
        };

        row.last_modified = last_modified;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<RootChangeSet>().do_ref!(|e| {
        let (_system_id, file_id, commit, _commit_by, blob_config_id, _previous) =
            innerfile_events::read_root_change_set(e);
        let row = ledger.file_mut(file_id);
        row.root_change.swap_or_fill(blob_config_id);
        row.root_commit = commit;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<RootChangeRemoved>().do_ref!(|e| {
        let (_system_id, file_id, _blob_config_id, _removed_by) =
            innerfile_events::read_root_change_removed(e);
        let row = ledger.file_mut(file_id);
        row.root_change.extract();
        row.root_commit = vector[];
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<RevisionRetired>().do_ref!(|e| {
        let (_system_id, file_id, _blob_config, _commit, _commit_by, _released) =
            innerfile_events::read_revision_retired(e);
        let row = ledger.file_mut(file_id);
        row.retired = row.retired + 1;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WriterPassMinted>().do_ref!(|e| {
        let (_system_id, file_id, pass_id, holder, duration, admin_privilege, _minted_by) =
            pass_events::read_writer_pass_minted(e);
        ledger.passes.push_back(PassRow {
            file_id,
            pass_id,
            holder,
            duration,
            admin_privilege,
            revoked: false,
            destroyed: false,
        });
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WriterPassRevoked>().do_ref!(|e| {
        let (_system_id, _file_id, pass_id, _revoked_by) =
            pass_events::read_writer_pass_revoked(e);
        let i = ledger.passes.find_index!(|row| row.pass_id == pass_id);
        assert!(i.is_some(), ENoSuchRow);
        ledger.passes[i.destroy_some()].revoked = true;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WriterPassDestroyed>().do_ref!(|e| {
        let (_file_id, pass_id, _destroyed_by) = pass_events::read_writer_pass_destroyed(e);
        let i = ledger.passes.find_index!(|row| row.pass_id == pass_id);
        assert!(i.is_some(), ENoSuchRow);
        ledger.passes[i.destroy_some()].destroyed = true;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WriterDenied>().do_ref!(|e| {
        let (_system_id, file_id, writer, until_ms, _denied_by) =
            pass_events::read_writer_denied(e);
        let held = ledger
            .denials
            .find_index!(|row| row.file_id == file_id && row.writer == writer);
        if (held.is_some()) {
            let row = &mut ledger.denials[held.destroy_some()];
            row.until_ms = until_ms;
            row.live = true;
        } else {
            ledger.denials.push_back(DenyRow { file_id, writer, until_ms, live: true });
        };
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WriterUndenied>().do_ref!(|e| {
        let (_system_id, file_id, writer, _undenied_by) =
            pass_events::read_writer_undenied(e);
        let held = ledger
            .denials
            .find_index!(|row| row.file_id == file_id && row.writer == writer);
        assert!(held.is_some(), ENoSuchRow);
        ledger.denials[held.destroy_some()].live = false;
        ledger.applied = ledger.applied + 1;
    });
}
