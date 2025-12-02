module warlot::warlot_system;

// =========== imports ============= //
use wal::wal::WAL;
use walrus::{blob::Blob, system::System};
use sui::{
    coin::{Self, Coin},
    clock::Clock, 
    dynamic_object_field as ofields, 
    dynamic_field as dfield,
    balance::{Self, Balance},
    table_vec::{Self, TableVec}
    };

use warlot::{
    user_state::{Self, User},
    config::{Self, BlobConfig}, 
    event::Self
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
    balance: Balance<WAL>
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

// process renew object
public struct ProcessSync has copy, drop{
    epoch_checkpoint: u32,
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

public(package) fun system_balance(system_cfg: &SystemConfig): u64{
    system_cfg.balance.value()
}

public(package) fun get_mut_system_balance(system_cfg: &mut SystemConfig): &mut Balance<WAL>{
    &mut system_cfg.balance
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



// =================================== mut functions =============
// increase user count
public(package) fun increase_user_count( system_cfg: &mut SystemConfig,){
    let old_user_count = system_cfg.users;
    system_cfg.users = old_user_count + 1;
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
        balance: balance::zero<WAL>()
    };
    

    let admin_cap = AdminCap {
        id:        object::new(ctx),
        system_config_id: object::id(&system_cfg),
        state:     STATE_ORIGINAL,
        total_system: 0,
    };

    // add the onchain indexer to the system object 
    dfield::add<vector<u8>, TableVec<address>>(&mut system_cfg.id, USERINDEX, table_vec::empty<address>(ctx));

    // share the system config so others can reference it
    transfer::public_share_object(system_cfg);
    transfer::transfer(admin_cap, ctx.sender());
}





/// ===========    system management ============= ///

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

#[allow(lint(self_transfer))]
public fun withdraw_system(system_cfg: &mut SystemConfig, admin_cap : &mut AdminCap, amount: u64, ctx: &mut TxContext){
    // only allow once, from the “original” cap
    assert!(admin_cap.state == STATE_ORIGINAL, 1);
    
    
    transfer::public_transfer(
        coin::take<WAL>(
            &mut system_cfg.balance, 
            amount, 
            ctx),

        ctx.sender()
    )

}


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

    let new_system = SystemConfig {
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
        },
        balance: balance::zero<WAL>()
    };

    let new_system_id = object::id(&new_system);

    event::emit_system_mint(new_system_id, object::id(old_system), ctx.sender());
    


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

// public fun self_withdraw_blob(
//     registry: &mut Registry,
//     system_cfg: &mut SystemConfig,
//     blob_obj_id: address,
//     ctx: &TxContext
// ){
//     let user: address = registry.get_user();
//     assert!(ctx.sender() == user, 3);
   
//     transfer::public_transfer(
//          withdraw_blob(system_cfg, blob_obj_id, user),
//           user);
    
// }


public(package) fun add_user(system_cfg: &mut SystemConfig,  user: User, ctx: &TxContext){
    let new_user = ctx.sender();

    assert!(!ofields::exists_(&system_cfg.id, new_user), EUserExist);

    // add user to the indexer

    ofields::add<address, User>(&mut system_cfg.id, new_user, user);
     
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




public(package) fun extend_blob(
    system: &mut System,
    blob: &mut Blob,
    payment: &mut Coin<WAL>,
    new_epoch: u32,
) {
    system.extend_blob(blob, new_epoch, payment);
}
