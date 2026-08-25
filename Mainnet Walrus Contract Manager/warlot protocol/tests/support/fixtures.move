/// Shared constructors for the objects the tests need from Walrus and from custody.
#[test_only]
module warlot::fixtures;

// === Imports ===

use sui::{clock::Clock, coin::{Self, Coin}};
use wal::wal::WAL;
use walrus::{blob::{Self, Blob}, encoding, messages, system::{Self, System}};
use warlot::{blob_config, entry_innerfile, entry_register, system_config::SystemConfig};

// === Constants ===

/// RedStuff with Reed-Solomon, the only encoding Walrus currently accepts.
const RS2: u8 = 1;

/// Enough WAL to cover reservation, write and extension payments in a test.
const TEST_WAL: u64 = 1_000_000_000;

/// The unencoded size of every blob a fixture mints.
const BLOB_SIZE: u64 = 1_024;

/// How far past the current epoch a fixture blob's storage already reaches.
const BLOB_EPOCHS_AHEAD: u32 = 5;

/// The storage term a fixture file's revisions are bought under.
const FILE_EPOCH_SET: u32 = 13;

/// How many renewal cycles a fixture file's revisions are bought for.
const FILE_CYCLES: u64 = 2;

/// How many drafts a writer may hold open on a fixture file.
const FILE_WRITERS: u8 = 5;

/// How many revisions a fixture file's rollback window holds.
const FILE_TRACK_BACK: u8 = 3;

/// How many epochs a draft on a fixture file lives for.
const FILE_DRAFT_EPOCHS: u32 = 1;

// === Test-only helpers ===

/// A Walrus system at epoch zero.
public fun walrus_system(ctx: &mut TxContext): System {
    system::new_for_testing(ctx)
}

/// A WAL coin large enough to pay for the blobs a test registers.
public fun wal(ctx: &mut TxContext): Coin<WAL> {
    coin::mint_for_testing<WAL>(TEST_WAL, ctx)
}

/// A registered, deletable blob of `size` bytes whose storage runs `epochs_ahead`
/// epochs past the system's current epoch.
public fun blob(
    walrus_system: &mut System,
    size: u64,
    epochs_ahead: u32,
    payment: &mut Coin<WAL>,
    ctx: &mut TxContext,
): Blob {
    let encoded_size = encoding::encoded_blob_length(size, RS2, walrus_system.n_shards());
    let storage = walrus_system.reserve_space(encoded_size, epochs_ahead, payment, ctx);

    let root_hash = 0u256;
    let blob_id = blob::derive_blob_id(root_hash, RS2, size);

    walrus_system.register_blob(storage, blob_id, root_hash, size, RS2, true, payment, ctx)
}

/// The same blob, certified.
///
/// `walrus::system::extend_blob` refuses an uncertified blob, so any test that
/// renews has to mint one the way the network would rather than stopping at
/// registration.
public fun certified_blob(
    walrus_system: &mut System,
    size: u64,
    epochs_ahead: u32,
    payment: &mut Coin<WAL>,
    ctx: &mut TxContext,
): Blob {
    let mut raw_blob = blob(walrus_system, size, epochs_ahead, payment, ctx);

    let message = messages::certified_deletable_blob_message_for_testing(
        blob::blob_id(&raw_blob),
        object::id(&raw_blob),
    );
    blob::certify_with_certified_msg_for_testing(
        &mut raw_blob,
        walrus_system.epoch(),
        message,
    );

    raw_blob
}

/// Publish a config owned by `owner` holding one certified blob, and return its id.
///
/// `blob_epochs_ahead` sets where the blob's storage term already reaches, so a
/// test can put it short of `epoch_set` when renewal should do work and past it
/// when it should not.
public fun shared_config(
    walrus_system: &mut System,
    owner: address,
    epoch_set: u32,
    cycle_limit: Option<u64>,
    blob_epochs_ahead: u32,
    payment: &mut Coin<WAL>,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let raw_blob = certified_blob(walrus_system, BLOB_SIZE, blob_epochs_ahead, payment, ctx);

    let config = blob_config::new(
        owner,
        vector[raw_blob],
        epoch_set,
        cycle_limit,
        option::none(),
        clock,
        ctx,
    );
    let config_id = blob_config::config_id(&config);

    blob_config::share(config);

    config_id
}

/// Register the sender and publish an inner file they own, returning its id.
///
/// The first revision goes through the real upload path, so a test that reads
/// the file's history gets the object graph the protocol actually builds. The
/// sender must be `owner`: registration keys the record off the sender.
public fun inner_file(
    walrus_system: &mut System,
    system_cfg: &mut SystemConfig,
    owner: address,
    username: vector<u8>,
    commit: vector<u8>,
    payment: &mut Coin<WAL>,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    entry_register::all_register_user_publicly(system_cfg, username.to_string(), clock, ctx);

    let first_revision = certified_blob(walrus_system, BLOB_SIZE, BLOB_EPOCHS_AHEAD, payment, ctx);

    entry_innerfile::create_file(
        system_cfg,
        owner,
        FILE_WRITERS,
        FILE_TRACK_BACK,
        vector[first_revision],
        FILE_EPOCH_SET,
        FILE_CYCLES,
        clock,
        commit,
        FILE_DRAFT_EPOCHS,
        false,
        0,
        ctx,
    )
}

/// The storage term a fixture file's revisions are bought under.
public fun file_epoch_set(): u32 { FILE_EPOCH_SET }

/// How many renewal cycles a fixture file's revisions are bought for.
public fun file_cycles(): u64 { FILE_CYCLES }

/// The unencoded size of every blob a fixture mints.
public fun blob_size(): u64 { BLOB_SIZE }

/// How far past the current epoch a fixture blob's storage already reaches.
public fun blob_epochs_ahead(): u32 { BLOB_EPOCHS_AHEAD }
