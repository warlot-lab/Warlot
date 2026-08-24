/// Declares every protocol event struct and its emitter.
///
/// One module, because Sui's `MoveEventModule` filter matches the module an event
/// is *defined* in and no package-wide filter exists. Declaring every event here
/// lets an indexer subscribe to the whole protocol with one filter and one cursor.
/// The emit call sites stay at the point of state change.
module warlot::events;

// === Imports ===

use std::string::String;
use sui::event;

// === Events ===

/// A new user was registered.
public struct NewUser has copy, drop, store {
    user_id: ID,
    registry_id: ID,
    user: address,
}

/// A user funded their internal wallet.
public struct Deposit has copy, drop, store {
    user: address,
    amount: u64,
}

/// A wallet was created for a user.
public struct WalletCreated has copy, drop, store {
    wallet_id: ID,
    user: address,
}

/// A new system was minted from an existing one.
public struct SystemMint has copy, drop, store {
    new_system: ID,
    old_system: ID,
    minter: address,
}

/// A duplicate admin capability was minted.
public struct AdminMint has copy, drop, store {
    new_admin: ID,
    minter: address,
}

/// Blobs were taken into custody under a user.
public struct WarlotFileStore has copy, drop, store {
    owner: address,
    blobs_obj_id: vector<ID>,
    size: u64,
    encoded_size: u64,
    current_epoch: u32,
    epoch_set: u32,
    cycle_end: u64,
}

/// A blob's renewal cycle was processed.
public struct RenewDigest has copy, drop, store {
    user: address,
    blob_obj_id: ID,
    epoch: u32,
    amount: u64,
    size: u64,
}

/// Externally-sourced blobs were adopted under a user.
public struct ManagedBlobs has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
    current_epoch: u32,
    size: u64,
    encoded_size: u64,
    epoch_set: u32,
    cycle_end: u64,
}

/// A blob config was unwrapped and its blobs returned.
public struct WithdrawBlob has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
}

/// A blob's storage term changed.
public struct BlobUpdate has copy, drop {
    owner: address,
    blob_obj_id: ID,
    current_epoch: u32,
}

/// A blob was labelled within a project and bucket.
public struct BlobWarlotAttribut has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
    project_name: String,
    bucket_name: String,
    file_name: String,
    file_type: String,
}

/// The protocol treasury paid out.
public struct SystemWithdraw has copy, drop, store {
    operator: address,
    system: ID,
    amount: u64,
}

// === Package functions ===

/// Announce a newly registered user.
public(package) fun emit_new_user(user_id: ID, registry_id: ID, user: address) {
    event::emit(NewUser { user_id, registry_id, user });
}

/// Announce a wallet deposit.
public(package) fun emit_deposit(user: address, amount: u64) {
    event::emit(Deposit { user, amount });
}

/// Announce a newly created wallet.
public(package) fun emit_wallet_created(wallet_id: ID, user: address) {
    event::emit(WalletCreated { wallet_id, user });
}

/// Announce a newly minted system.
public(package) fun emit_system_mint(new_system: ID, old_system: ID, minter: address) {
    event::emit(SystemMint { new_system, old_system, minter });
}

/// Announce a newly minted admin capability.
public(package) fun emit_admin_mint(new_admin: ID, minter: address) {
    event::emit(AdminMint { new_admin, minter });
}

/// Announce blobs taken into custody.
public(package) fun emit_warlot_file_store(
    owner: address,
    blobs_obj_id: vector<ID>,
    size: u64,
    encoded_size: u64,
    current_epoch: u32,
    epoch_set: u32,
    cycle_end: u64,
) {
    event::emit(WarlotFileStore {
        owner,
        blobs_obj_id,
        size,
        encoded_size,
        current_epoch,
        epoch_set,
        cycle_end,
    });
}

/// Announce one processed renewal cycle.
public(package) fun emit_renew_digest(
    user: address,
    blob_obj_id: ID,
    epoch: u32,
    amount: u64,
    size: u64,
) {
    event::emit(RenewDigest { user, blob_obj_id, epoch, amount, size });
}

/// Announce externally-sourced blobs adopted under a user.
public(package) fun emit_managed_blobs(
    owner: address,
    blob_obj_id: ID,
    size: u64,
    encoded_size: u64,
    current_epoch: u32,
    epoch_set: u32,
    cycle_end: u64,
) {
    event::emit(ManagedBlobs {
        owner,
        blob_obj_id,
        current_epoch,
        size,
        encoded_size,
        epoch_set,
        cycle_end,
    });
}

/// Announce blobs returned to their owner.
public(package) fun emit_withdraw_blob(owner: address, blob_obj_id: ID) {
    event::emit(WithdrawBlob { owner, blob_obj_id });
}

/// Announce a change to a blob's storage term.
public(package) fun emit_update_blob(owner: address, blob_obj_id: ID, current_epoch: u32) {
    event::emit(BlobUpdate { owner, blob_obj_id, current_epoch })
}

/// Announce a blob's project and bucket labels.
public(package) fun emit_warlot_attribute(
    owner: address,
    blob_obj_id: ID,
    project_name: String,
    bucket_name: String,
    file_name: String,
    file_type: String,
) {
    event::emit(BlobWarlotAttribut {
        owner,
        blob_obj_id,
        project_name,
        bucket_name,
        file_name,
        file_type,
    })
}

/// Announce a treasury payout.
public(package) fun emit_system_withdraw(operator: address, system: ID, amount: u64) {
    event::emit(SystemWithdraw { operator, system, amount })
}
