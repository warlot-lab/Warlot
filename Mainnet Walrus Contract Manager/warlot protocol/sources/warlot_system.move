module warlot::warlot_system;

// =========== imports ============= //
use wal::wal::{WAL};
use walrus::blob::Blob;
use sui::{
    coin::{Self, Coin},
    clock::Clock, 
    dynamic_object_field as ofields, 
    dynamic_field as dfield,
    table_vec::{Self, TableVec},
    table::{Self, Table},
    };

use warlot::{
    user_state::{Self, User},
    config::{Self, BlobConfig}, 
    event::Self,
    registry::Registry,
    version::{Self},
    vault::{Self, Vault},
};



//===========constants =============//
// decalrs the original of the admin key
const STATE_ORIGINAL: u8 = 0;
// duplicate of the admin_key
const STATE_DUPLICATE: u8 = 1;

const VERSION: u64 = 1;


//======== Error ======= //
#[error]
const EUserExist: vector<u8> = b"user already exists";


//========== Dynamic field keys ================//
const USERINDEX: vector<u8> = b"user indexer";
const USER_INDEX_MAP: vector<u8> = b"user_index_map"; // Maps address -> index (u64)
const SYSTEM_VAULT: vector<u8> = b"system_vault";    // Key for the Vault


/// System configuration on-chain
/// this holds the warlot system config and data
public struct SystemConfig has key, store {
    id: UID,
    warlot_allowed_address: address, 
    users: u64,
    managed_blobs: u64,
    version: u64,
    mint_cap: SystemMintCap,
    user_modification_cfg: UserMdCfg,
}



// this is a key to make sure that system are minted linearly 
public struct SystemMintCap has store{
        previous_system: ID,
        next_system: Option<ID>
}

/// Admin capability, carrying along a “state tag”
public struct AdminCap has key, store {
    id: UID,
    system_config_id: ID,
    state: u8,
    total_system: u8,
}


/*
 this struct holds bound for modifing your user registry
 todo
 to be used to show when you can leave the system
 to show when you can migrate to another system storage 
 to modify the system state 
 to became a validator on the next system mint 
*/
public struct UserMdCfg has store {
    cost_change_apikey_forms : u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
}

///  ============ view functions ============= ///
public fun cost_change_apikey_forms(system_cfg: &SystemConfig): u64{
     system_cfg
        .user_modification_cfg
        .cost_change_apikey_forms
}



public fun cost_to_update_name(system_cfg: &SystemConfig): u64{
    system_cfg
        .user_modification_cfg
        .cost_to_update_name
}

public(package) fun get_warlot_address(system_cfg: &SystemConfig): address{
    system_cfg.
        warlot_allowed_address

}

public fun get_system_version(system_cfg: &SystemConfig): u64{
    system_cfg.version
}

public(package) fun get_indexer(system_cfg: &SystemConfig): &TableVec<address> {
    dfield::borrow<vector<u8>, TableVec<address>>(&system_cfg.id, USERINDEX)
}

// Check balance of a specific coin type in the system vault
public fun get_system_balance<T>(system_cfg: &SystemConfig): u64 {
    let vault = ofields::borrow<vector<u8>, Vault>(&system_cfg.id, SYSTEM_VAULT);
    vault::balance_of<T>(vault)
}



// =================================== mut functions =============
// increase user count
public(package) fun increase_user_count( system_cfg: &mut SystemConfig,){
    let old_user_count = system_cfg.users;
    system_cfg.users = old_user_count + 1;
}



public(package) fun get_vault_mut(system_cfg: &mut SystemConfig): &mut Vault {
    ofields::borrow_mut<vector<u8>, Vault>(&mut system_cfg.id, SYSTEM_VAULT)
}




/// Initialize the system and mint the first AdminCap in the ORIGINAL state
fun init(ctx: &mut TxContext){
    let mut system_cfg = SystemConfig {
        id: object::new(ctx),
        warlot_allowed_address: ctx.sender(),
        users: 0,
        managed_blobs: 0,
        version: VERSION,
        mint_cap: SystemMintCap{
            previous_system: object::id_from_address(@0x0),
            next_system: option::none(),
        },
        user_modification_cfg: UserMdCfg{
            cost_change_apikey_forms : 100,
            cost_to_migrate_system: 100,
               cost_to_update_name: 100,
            cost_to_delete: 100,
        },
    };

    // Create Vault
    let mut vault = vault::create_vault(ctx);
    // Add WAL as default accepted token
    vault::add_supported_coin<WAL>(&mut vault);
    // Attach Vault to System
    ofields::add(&mut system_cfg.id, SYSTEM_VAULT, vault);
    

    let admin_cap = AdminCap {
        id:        object::new(ctx),
        system_config_id: object::id(&system_cfg),
        state:     STATE_ORIGINAL,
        total_system: 0,
    };

    // add the onchain indexer to the system object 
    dfield::add<vector<u8>, TableVec<address>>(&mut system_cfg.id, USERINDEX, table_vec::empty<address>(ctx));

   
    //  map for O(1) lookups
    dfield::add<vector<u8>, Table<address, u64>>(&mut system_cfg.id, USER_INDEX_MAP, table::new<address, u64>(ctx));

    // share the system config so others can reference it
    transfer::public_share_object(system_cfg);
    transfer::transfer(admin_cap, ctx.sender());
}


 

/// =========== migrate system ============= ///
public fun migrate_system(
    registry: &mut Registry,
    current_system: &mut SystemConfig,
    next_system: &mut SystemConfig,
    coin: &mut Coin<WAL>,
    clock: &Clock,
    ctx: &mut TxContext
){
    let user_address = registry.get_user();

    let cost = next_system.user_modification_cfg.cost_to_migrate_system;

    // make sure that the registry is from the current system
    assert!(object::id(current_system) == registry.get_system(), 1);

    // make sure that the use have sufficent coin
    // cost to migrate to the next system is the cost needed
    assert!(coin.value() >= cost, 2);

    // check if the user has a registry in the current system
    assert!(check_user(current_system, registry.get_user()), 3);

    // in this current version, only allow migration to the next system if the user does not have an identity in the next system
    assert!(!check_user(next_system, registry.get_user()), 4);


    let payment = coin::split(coin, cost, ctx);
    
    // Deposit into New System's Vault
    let next_vault = get_vault_mut(next_system);
    vault::deposit(next_vault, payment);
  

    // take data from current system 
    let user_data =  remove_user(current_system, user_address);


    // add user to the next system
    add_user(next_system, user_data, ctx);

  
    // update the registry to point to the new system
    registry.migrate_system(object::id(next_system), clock);
}







public(package) fun update_version(system_cfg: &mut SystemConfig){
    // confirm that the version is lower than the current version 
    assert!(system_cfg.version < version::get_version(), 1);

    //force version to current version
    system_cfg.version = version::get_version();
}



// ============ Vault / Financial Management ============= //

// Withdraw WAL from the system vault
#[allow(lint(self_transfer))]
public fun withdraw_system_wal(
    system_cfg: &mut SystemConfig, 
    admin_cap: &mut AdminCap, 
    amount: u64, 
    ctx: &mut TxContext
) {
    assert!(admin_cap.state == STATE_ORIGINAL, 1);
    
    let vault = get_vault_mut(system_cfg);
    let withdrawn_coin = vault::withdraw<WAL>(vault, amount, ctx);
    
    transfer::public_transfer(withdrawn_coin, ctx.sender());
}

// Allow admin to add support for other coins (e.g., USDC)
public fun add_coin_type<T>(
    _admin_cap: &mut AdminCap, // Require admin cap
    system_cfg: &mut SystemConfig
) {
    let vault = get_vault_mut(system_cfg);
    vault::add_supported_coin<T>(vault);
}


/// Admin can remove support for a coin type <T>.
/// Note: This prevents NEW deposits, but existing balances remain withdrawable.
public fun remove_supported_coin<T>(
    admin_cap: &mut AdminCap, 
    system_cfg: &mut SystemConfig
) {
    // Security: Only original admin can remove tokens
    assert!(admin_cap.state == STATE_ORIGINAL, 1);

    let vault = get_vault_mut(system_cfg);
    vault::remove_supported_coin<T>(vault);
}


// Generic withdrawal: Allows admin to withdraw ANY coin type <T> from the vault
#[allow(lint(self_transfer))]
public fun withdraw_system_coin<T>(
    system_cfg: &mut SystemConfig, 
    admin_cap: &mut AdminCap, 
    amount: u64, 
    ctx: &mut TxContext
)  {
    // Security Check: Only the original admin can withdraw
    assert!(admin_cap.state == STATE_ORIGINAL, 1);
    
    // Get mutable reference to the Vault
    let vault = get_vault_mut(system_cfg);

    // Perform the generic withdrawal using the Vault module
    // This will fail with ENoBalanceFound if the token isn't there
    let withdrawn_coin = vault::withdraw<T>(vault, amount, ctx);
    
    // Send the coin to the admin
    transfer::public_transfer(withdrawn_coin, ctx.sender());
}


// ===========    system management ============= //


// create a new system
public fun mint_system(
    admin_cap: &mut AdminCap,
    old_system: &mut SystemConfig,
    cost_change_apikey_forms : u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    ctx: &mut TxContext
){
    //makes sure the minting of system is linear 
    assert!(option::is_none(&old_system.mint_cap.next_system), 0);

    // makes sure that only the original admin can create a new system
    assert!(admin_cap.state == STATE_ORIGINAL, 3);

    let mut new_system = SystemConfig {
        id: object::new(ctx),
        warlot_allowed_address: ctx.sender(),
        users: 0,
        managed_blobs: 0,
        version: 1 + old_system.version,
        mint_cap: SystemMintCap{
            previous_system: object::id(old_system),
            next_system: option::none(),
        },
        user_modification_cfg: UserMdCfg{
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
        }
    };

    
    // Create Vault for new system
    let mut vault = vault::create_vault(ctx);
    // Add WAL support by default
    vault::add_supported_coin<WAL>(&mut vault);
    // Attach
    ofields::add(&mut new_system.id, SYSTEM_VAULT, vault);

    // Initialize User Indexers
    dfield::add(&mut new_system.id, USERINDEX, table_vec::empty<address>(ctx));
    dfield::add(&mut new_system.id, USER_INDEX_MAP, table::new<address, u64>(ctx));

    let new_system_id = object::id(&new_system);
    event::emit_system_mint(new_system_id, object::id(old_system), ctx.sender());

    // admin_cap.total_system logic is debatable, but kept as per your original
    let old_count = admin_cap.total_system;
    admin_cap.total_system = old_count + 1;
    option::fill(&mut old_system.mint_cap.next_system, new_system_id);

    transfer::public_share_object(new_system);
}




// update the cost of the system
public fun update_cost(
    admin_cap: &mut AdminCap,
    system: &mut SystemConfig,
    cost_change_apikey_forms : u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,){
    assert!(admin_cap.state == STATE_ORIGINAL, 3);
    system.user_modification_cfg.cost_change_apikey_forms = cost_change_apikey_forms;
    system.user_modification_cfg.cost_to_migrate_system = cost_to_migrate_system;
    system.user_modification_cfg.cost_to_update_name = cost_to_update_name;
}


// ============= admin ======================


/// Mint a new admin cap only if the caller holds an ORIGINAL one
public fun mint_admin(
    system_cfg: &SystemConfig,
    receiver: address,
    admin_cap: &AdminCap,
    ctx: &mut TxContext,
) {
    // only allow one, from the “original” cap
    assert!(admin_cap.state == STATE_ORIGINAL, 1);

    // create a duplicate cap and send it to the receiver
    let new_cap = AdminCap {
        id:        object::new(ctx),
        system_config_id: object::id(system_cfg), //mint to a new system
        state:     STATE_DUPLICATE,
        total_system: 0,
    };

    event::emit_admin_mint(object::id(&new_cap), ctx.sender());
    transfer::transfer(new_cap, receiver);
}




// this is used to store the blob in the contract
public(package) fun raw_store_blob(
    system_cfg: &mut SystemConfig,
    blobs: vector<Blob>,
    file_size: u64,
    epoch_set: u32,
    cycle_limit: u64,
    fileMeta_id: Option<ID>, 
    user: address,
    clock: &Clock,
    ctx: &mut TxContext,

): ID{
    

    let set = epoch_set;

   


    let blob_setting: BlobConfig = config::new_config_blob(blobs, set, option::some(cycle_limit),  fileMeta_id, clock, ctx);


    let user = get_user_mut(system_cfg, user);

    let config_obj_id  = user_state::add_blob(user, blob_setting, set, ctx);
    user_state::update_dash_data(user, 1, file_size as u128);
    let old_m_blob = system_cfg.managed_blobs;
    system_cfg.managed_blobs = old_m_blob + 1;

    config_obj_id

}






// withdraw_blob for the internal system
public(package) fun withdraw_blob(
    system_cfg: &mut SystemConfig,
    blob_obj_id: address,
    user: address,
): vector<Blob>{
    let user_ref = get_user_mut(system_cfg, user);
    let raw_blob = user_ref.
        remove_blob_cfg_from_user(object::id_from_address(blob_obj_id))
            .withdraw_and_burn();

    let old_m_blob = system_cfg.managed_blobs;
    system_cfg.managed_blobs = old_m_blob - 1;
    event::emit_withdraw_blob(
        user,
        object::id_from_address(blob_obj_id)
    );

    raw_blob

   
}

public fun self_withdraw_blob(
    registry: &mut Registry,
    system_cfg: &mut SystemConfig,
    blob_obj_id: address,
    ctx: &TxContext
){
    let user: address = registry.get_user();
    assert!(ctx.sender() == user, 3);
   

    withdraw_blob(system_cfg, blob_obj_id, user).do!(
        |blob| {
            transfer::public_transfer(
                blob,
                user
            );
        }
    )

    
}


// ============== user ======================== //


public(package) fun add_user(system_cfg: &mut SystemConfig, user: User, ctx: &TxContext) {
    let new_user = ctx.sender();
    assert!(!ofields::exists_(&system_cfg.id, new_user), EUserExist);

    // Get the Indexer
    let indexer = dfield::borrow_mut<vector<u8>, TableVec<address>>(&mut system_cfg.id, USERINDEX);
    
    // Push back and get the new index
    table_vec::push_back(indexer, new_user);
    let new_index = table_vec::length(indexer) - 1;

    // Store the map: Address -> Index (O(1) lookup later)
    let index_map = dfield::borrow_mut<vector<u8>, Table<address, u64>>(&mut system_cfg.id, USER_INDEX_MAP);
    table::add(index_map, new_user, new_index);

    // Add the User Object
    ofields::add<address, User>(&mut system_cfg.id, new_user, user);

    // Update the counter
    system_cfg.users = system_cfg.users + 1;
}

public(package) fun remove_user(system_cfg: &mut SystemConfig, user: address): User {
    // Remove user from the Map first 
    //  get the index, then drop the map reference immediately.
    let user_index = {
        let index_map = dfield::borrow_mut<vector<u8>, Table<address, u64>>(&mut system_cfg.id, USER_INDEX_MAP);
        table::remove(index_map, user)
    };

    //  Manipulate the Indexer (Scope 2)
    //  perform the swap/pop logic .
    // If a swap happens, and capture the address of the user who was moved.
    //  return an Option<address> and  update the map AFTER this block ends.
    let swapped_user_option = {
        let indexer = dfield::borrow_mut<vector<u8>, TableVec<address>>(&mut system_cfg.id, USERINDEX);
        let last_index = table_vec::length(indexer) - 1;

        if (user_index != last_index) {
            // Swap the user to remove with the last element
            table_vec::swap(indexer, user_index, last_index);
            
            // Capture the user who just moved into 'user_index'
            let swapped_addr = *table_vec::borrow(indexer, user_index);
            
            // Remove the target user (now at the end)
            table_vec::pop_back(indexer);
            
            option::some(swapped_addr)
        } else {
            // User is already at the end, just pop
            table_vec::pop_back(indexer);
            option::none()
        }
    }; 

    // Update Map for the swapped user (Scope 3)
    // Now it is safe to borrow the map again.
    if (option::is_some(&swapped_user_option)) {
        let swapped_addr = *option::borrow(&swapped_user_option);
        let index_map = dfield::borrow_mut<vector<u8>, Table<address, u64>>(&mut system_cfg.id, USER_INDEX_MAP);
        
        // Update the moved user's index to their new location
        *table::borrow_mut(index_map, swapped_addr) = user_index;
    };

    // Update count and return object
    system_cfg.users = system_cfg.users - 1;
    dfield::remove<address, User>(&mut system_cfg.id, user)
}


public(package) fun get_user_mut(system_cfg: &mut SystemConfig, user: address): &mut User{
    ofields::borrow_mut<address, User>(&mut system_cfg.id, user)
}


public fun get_user(system_cfg: &SystemConfig,  user: address): &User{
    assert!(check_user(system_cfg, user), 1);

    ofields::borrow<address, User>(&system_cfg.id, user)

}


public fun check_user(system_cfg: &SystemConfig, user: address): bool{
    ofields::exists_(&system_cfg.id, user)
}




