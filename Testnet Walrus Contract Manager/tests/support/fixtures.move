/// Shared constructors for the objects the tests need from Walrus.
#[test_only]
module warlot::fixtures;

// === Imports ===

use sui::coin::{Self, Coin};
use wal::wal::WAL;
use walrus::{blob::{Self, Blob}, encoding, system::{Self, System}};

// === Constants ===

/// RedStuff with Reed-Solomon, the only encoding Walrus currently accepts.
const RS2: u8 = 1;

/// Enough WAL to cover reservation and write payments in a test.
const TEST_WAL: u64 = 1_000_000_000;

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
