module warlot::event;
use sui::event;
use std::string::String;

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
    size: u64,
    encoded_size: u64,
    current_epoch: u32,
    epoch_set: u32,
    cycle_end: u64,
}

// Emitted each time a blob's renewal cycle is processed
public struct RenewDigest has copy, drop, store {
    user: address,
    blob_obj_id: ID,
    epoch: u32,
    amount: u64,
    size: u64,
}

// Emitted when managed blobs are added for a user
public struct ManagedBlobs has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
    current_epoch: u32,
    size: u64,
    encoded_size: u64,
    epoch_set: u32,
    cycle_end: u64,
}

// Emitted when a blob is withdrawn
public struct WithdrawBlob has copy, drop, store {
    owner: address,
    blob_obj_id: ID,
}

//Emitted when a blob is updated
public struct BlobUpdate has copy, drop{
    owner: address,
    blob_obj_id: ID,
    current_epoch: u32,
}

//Emitted when a blob is given is in a project 
public struct BlobWarlotAttribut has copy, drop, store{
    owner: address,
    blob_obj_id: ID,
    project_name: String,
    bucket_name: String,
    file_name: String,
    file_type: String,
}

public struct SystemWithdraw has copy, drop, store{
    operator: address,
    system: ID,
    amount: u64
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
    size: u64,
     encoded_size: u64,
    current_epoch: u32,
    epoch_set: u32,
    cycle_end: u64,
) {
    event::emit(WarlotFileStore { owner, blob_obj_id,  size,  encoded_size, current_epoch, epoch_set, cycle_end });
}

public(package) fun emit_renew_digest(
    user: address,
    blob_obj_id: ID,
    epoch: u32,
    amount: u64,
    size: u64,
) {
    event::emit(RenewDigest { user, blob_obj_id, epoch, amount, size });
}

public(package) fun emit_managed_blobs(
    owner: address,
    blob_obj_id: ID,
    size: u64,
    encoded_size: u64,
    current_epoch: u32,
    epoch_set: u32,
    cycle_end: u64,
) {
    event::emit(ManagedBlobs { owner, blob_obj_id,  current_epoch, size,  encoded_size, epoch_set, cycle_end });
}

public(package) fun emit_withdraw_blob(owner: address, blob_obj_id: ID) {
    event::emit(WithdrawBlob { owner, blob_obj_id });
}

public(package) fun emit_update_blob(owner: address, blob_obj_id: ID, current_epoch: u32){
    event::emit(BlobUpdate{owner, blob_obj_id, current_epoch})
}

public(package) fun emit_warlot_attribute(owner: address, blob_obj_id: ID, project_name: String, bucket_name: String, file_name: String, file_type: String){
    event::emit(BlobWarlotAttribut{owner, blob_obj_id, project_name, bucket_name, file_name, file_type})
}

public(package) fun emit_system_withdraw(operator: address, system: ID, amount: u64){
    event::emit(SystemWithdraw{operator, system, amount})
}