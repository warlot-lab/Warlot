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
        ForeignMetaCreated,
        RenewCycleSpent,
        RenewSkipped
    },
    system_events::{
        Self,
        AdminCapMinted,
        SystemCreated,
        SystemFeesChanged,
        SystemSucceeded,
        SystemTiersChanged,
        SystemVersionMigrated
    },
    treasury_events::{Self, SystemWithdraw, VaultCoinSupportChanged, VaultDeposited}
};

// === Errors ===

const EUnknownEventType: u64 = 0;
const ENoSuchRow: u64 = 1;

// === Structs ===

/// One system, as the stream describes it.
public struct SystemRow has drop {
    system_id: ID,
    previous_system: ID,
    next_system: Option<ID>,
    version: u64,
    warlot_allowed_address: address,
    tier_table: vector<u32>,
    max_epochs_ahead: u32,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    /// Joins minus leaves, never read off an event.
    users: u64,
    /// Deposits minus payouts, never read off an event.
    vault_wal: u64,
    accepted_coins: vector<String>,
    admin_caps: vector<ID>,
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
    foreign_meta_id: Option<ID>,
    /// Deposits minus withdrawals, never read off an event.
    wallet_wal: u64,
    foreign_configs: u64,
    foreign_chunk: u64,
    joined: bool,
}

/// One delegation row.
public struct PermRow has drop {
    system_id: ID,
    owner: address,
    delegate: address,
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    can_compact: bool,
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
    fileMeta_id: Option<ID>,
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
    cycle_end: u64,
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
public struct Ledger has drop {
    systems: vector<SystemRow>,
    users: vector<UserRow>,
    permissions: vector<PermRow>,
    configs: vector<ConfigRow>,
    files: vector<FileRow>,
    passes: vector<PassRow>,
    denials: vector<DenyRow>,
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
): (bool, bool, bool, bool, bool) {
    let i = ledger.permissions.find_index!(|row| row.owner == owner && row.delegate == delegate);
    assert!(i.is_some(), ENoSuchRow);
    let row = &ledger.permissions[i.destroy_some()];

    (
        row.add_blob_to_address,
        row.create_inner_file,
        row.create_writer_pass,
        row.can_init_db,
        row.can_compact,
    )
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

// === View functions ,  system rows ===

public fun system_users(row: &SystemRow): u64 { row.users }

public fun system_vault_wal(row: &SystemRow): u64 { row.vault_wal }

public fun system_version(row: &SystemRow): u64 { row.version }

public fun system_previous(row: &SystemRow): ID { row.previous_system }

public fun system_next(row: &SystemRow): Option<ID> { row.next_system }

public fun system_tier_table(row: &SystemRow): vector<u32> { row.tier_table }

public fun system_max_epochs_ahead(row: &SystemRow): u32 { row.max_epochs_ahead }

public fun system_warlot_address(row: &SystemRow): address { row.warlot_allowed_address }

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

public fun user_foreign_meta(row: &UserRow): Option<ID> { row.foreign_meta_id }

public fun user_foreign_configs(row: &UserRow): u64 { row.foreign_configs }

public fun user_foreign_chunk(row: &UserRow): u64 { row.foreign_chunk }

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

public fun config_file_meta(row: &ConfigRow): Option<ID> { row.fileMeta_id }

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

public fun file_cycle_end(row: &FileRow): u64 { row.cycle_end }

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
            warlot_allowed_address,
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
            warlot_allowed_address,
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
            foreign_meta_id: option::none(),
            wallet_wal: 0,
            foreign_configs: 0,
            foreign_chunk: 0,
            joined: false,
        });
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<WalletCreated>().do_ref!(|e| {
        let (_system_id, wallet_id, user, _created_at) = identity_events::read_wallet_created(e);
        ledger.user_mut(user).wallet_id = wallet_id;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<ForeignMetaCreated>().do_ref!(|e| {
        let (_system_id, foreign_meta_id, owner) = storage_events::read_foreign_meta_created(e);
        ledger.user_mut(owner).foreign_meta_id.fill(foreign_meta_id);
        ledger.applied = ledger.applied + 1;
    });

    // A migration detaches before it attaches, so removals are applied first ,
    // the reverse order would leave the user a member of neither system.
    event::events_by_type<UserLeftSystem>().do_ref!(|e| {
        let (system_id, user, _user_id, _users) = identity_events::read_user_left_system(e);
        let row = ledger.system_mut(system_id);
        row.users = row.users - 1;
        ledger.user_mut(user).joined = false;
        ledger.applied = ledger.applied + 1;
    });

    event::events_by_type<UserJoinedSystem>().do_ref!(|e| {
        let (system_id, user, _user_id, _users) = identity_events::read_user_joined_system(e);
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
            fileMeta_id,
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
            fileMeta_id,
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
        let (_system_id, _meta_id, owner, _adopted_by, chunk_index, config_ids, total) =
            storage_events::read_foreign_blobs_adopted(e);
        let row = ledger.user_mut(owner);
        row.foreign_configs = row.foreign_configs + config_ids.length();
        row.foreign_chunk = chunk_index;
        assert!(row.foreign_configs == total, ENoSuchRow);
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

    event::events_by_type<DraftPinned>().do_ref!(|e| {
        let (_s, file_id, _draft_id, draft_index, _pass, _issue, _c, _by, _cfg, _t, last_modified) =
            draft_events::read_draft_pinned(e);
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
        let (_system_id, file_id, writer, until_ms, _denied_by, _count) =
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
        let (_system_id, file_id, writer, _undenied_by, _count) =
            pass_events::read_writer_undenied(e);
        let held = ledger
            .denials
            .find_index!(|row| row.file_id == file_id && row.writer == writer);
        assert!(held.is_some(), ENoSuchRow);
        ledger.denials[held.destroy_some()].live = false;
        ledger.applied = ledger.applied + 1;
    });
}
