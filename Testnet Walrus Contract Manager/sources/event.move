module setandrenew::event;
use sui::event;

// Events emitted for indexing and off-chain processing

// Emitted when a new user is registered
public struct NewUser has copy, drop, store {
    user_id: ID,
    registry_id: ID,
    user: address,
}

// Emitted when a user makes a deposit
public struct Deposit has copy, drop, store {
    user: address,
    amount: u64,
}

// Emitted when a wallet is created for a user
public struct WalletCreated has copy, drop, store {
    wallet_id: ID,
    user: address,
}

// Emitted when the system mint is updated
public struct SystemMint has copy, drop, store {
    new_system: ID,
    old_system: ID,
    minter: address,
}

// Emitted when an admin mints new tokens
public struct AdminMint has copy, drop, store {
    new_admin: ID,
    minter: address,
}

// Emitted when a blob is stored in the Warlot file system
public struct WarlotFileStore has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
    blob_cfg_id: ID,
    epoch_set: u32,
    cycle_end: u64,
}

// Emitted each time a blob's renewal cycle is processed
public struct RenewDigest has copy, drop, store {
    blob_obj_id: ID,
    user: address,
    epoch: u32,
    amount: u64,
}

// Emitted when managed blobs are added for a user
public struct ManagedBlobs has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
    blob_cfg_id: ID,
    epoch_set: u32,
    cycle_end: u64,
}

// Emitted when a blob is withdrawn
public struct WithdrawBlob has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
}

// Emitters

public(package) fun emit_new_user(user_id: ID, registry_id: ID, user: address) {
    event::emit(NewUser { user_id, registry_id, user });
}

public(package) fun emit_deposit(user: address, amount: u64) {
    event::emit(Deposit { user, amount });
}

public(package) fun emit_wallet_created(wallet_id: ID, user: address) {
    event::emit(WalletCreated { wallet_id, user });
}

public(package) fun emit_system_mint(new_system: ID, old_system: ID, minter: address) {
    event::emit(SystemMint { new_system, old_system, minter });
}

public(package) fun emit_admin_mint(new_admin: ID, minter: address) {
    event::emit(AdminMint { new_admin, minter });
}

public(package) fun emit_warlot_file_store(
    owner: address,
    blob_obj_id: ID,
    blob_cfg_id: ID,
    epoch_set: u32,
    cycle_end: u64
) {
    event::emit(WarlotFileStore { owner, blob_obj_id, blob_cfg_id, epoch_set, cycle_end });
}

public(package) fun emit_renew_digest(
    blob_obj_id: ID,
    user: address,
    epoch: u32,
    amount: u64
) {
    event::emit(RenewDigest { blob_obj_id, user, epoch, amount });
}

public(package) fun emit_managed_blobs(
    owner: address,
    blob_obj_id: ID,
    blob_cfg_id: ID,
    epoch_set: u32,
    cycle_end: u64
) {
    event::emit(ManagedBlobs { owner, blob_obj_id, blob_cfg_id, epoch_set, cycle_end });
}

public(package) fun emit_withdraw_blob(owner: address, blob_obj_id: ID) {
    event::emit(WithdrawBlob { owner, blob_obj_id });
}
