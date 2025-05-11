module setandrenew::setandrenew;

use wal::wal::WAL;
use walrus::{blob::{Self, Blob}, system::System};
use std::string::String;
use sui::{coin::{Self, Coin}, dynamic_object_field as ofields, clock::Clock};
use setandrenew::{
    userstate::{Self, User},
    config::{Self, BlobSettings}, 
    constants::{Self},
    registry::Registry,
    event::Self
    };






//======== Error ======= //
#[error]
const EUserExist: vector<u8> = b"user already exists";

/// System configuration on-chain
public struct SystemConfig has key, store {
    id: UID,
    users: u64,
    managed_blobs: u64,
    version: u8,
    mint_cap: SystemMintCap,
}

public struct SystemMintCap has store{
        previous_system: ID,
        has_minted: bool
}

/// Admin capability, carrying along a “state tag”
public struct AdminCap has key, store {
    id: UID,
    system_config_id: ID,
    state: u8,
    total_system: u8,
}





/// Initialize the system and mint the first AdminCap in the ORIGINAL state
fun init(ctx: &mut TxContext){
    let system_cfg = SystemConfig {
        id: object::new(ctx),
        users: 0,
        managed_blobs: 0,
        version: 1,
        mint_cap: SystemMintCap{
            previous_system: object::id_from_address(@0x0),
            has_minted: false
        }
    };
    

    let admin_cap = AdminCap {
        id:        object::new(ctx),
        system_config_id: object::id(&system_cfg),
        state:     constants::state_original(),
        total_system: 0,
    };

    // share the system config so others can reference it
    transfer::public_share_object(system_cfg);
    transfer::transfer(admin_cap, ctx.sender());
}




/// Mint a new admin cap only if the caller holds an ORIGINAL one
public fun mint_admin(
    receiver: address,
    admin_cap: &AdminCap,
    ctx: &mut TxContext,
) {
    // only allow once, from the “original” cap
    assert!(admin_cap.state == constants::state_original(), 1);

    // create a duplicate cap and send it to the receiver
    let new_cap = AdminCap {
        id:        object::new(ctx),
        system_config_id: admin_cap.system_config_id,
        state:     constants::state_duplicate(),
        total_system: 0,
    };

    event::emit_admin_mint(object::id(&new_cap), ctx.sender());
    transfer::transfer(new_cap, receiver);
}


public fun mint_system(
    admin_cap: &mut AdminCap,
    old_system: &mut SystemConfig,
    ctx: &mut TxContext
){
    //makes sure the minting of system is linear 
    assert!(!old_system.mint_cap.has_minted, 0);

    // makes sure that only the original admin can create a new system
    assert!(admin_cap.state == constants::state_original(), 3);

    let new_system = SystemConfig {
        id: object::new(ctx),
        users: 0,
        managed_blobs: 0,
        version: 1 + old_system.version,
        mint_cap: SystemMintCap{
            previous_system: object::id(old_system),
            has_minted: false
        }
    };

    event::emit_system_mint(object::id(&new_system), object::id(old_system), ctx.sender());
    
    transfer::public_share_object(new_system);

    let old_count = admin_cap.total_system;
    admin_cap.total_system = old_count + 1;
    old_system.mint_cap.has_minted = true;
}


public fun create_user(
    system_cfg: &mut SystemConfig,
    apikey: String,
    encrypt_key: String,
    warlot_sign_apikey: String,
    clock: &Clock,
    ctx: &mut TxContext
    ){
    let new_user = userstate::create_user(apikey, encrypt_key, warlot_sign_apikey, clock, ctx);

    add_user(system_cfg, new_user, ctx);

    let old_user_count = system_cfg.users;
    system_cfg.users = old_user_count + 1;
}



// this is used to store the blob in the contract
public(package) fun raw_store_blob(
    system_cfg: &mut SystemConfig,
    blob: Blob,
    epoch_set: u32,
    cycle_end: u64,
    user: address,

){
    let set = if (epoch_set > constants::half_set()) {
        constants::max()
    } else if (epoch_set > constants::first_set()) {
        constants::half_set()
    } else {
        constants::first_set()
    };

    let file_size: u128 = {
        blob.size() as u128
        };


    let blob_setting: BlobSettings = config::new_config_blob(blob, set, cycle_end);


    let user = get_user_mut(system_cfg, user);
    userstate::add_blob(user, blob_setting, set);
    userstate::update_dash_data(user, 1, file_size);
    let old_m_blob = system_cfg.managed_blobs;
    system_cfg.managed_blobs = old_m_blob + 1;

}


// only an admin can use this funtion to store blobs
public fun store_blob(
    _: &mut AdminCap,
    system_cfg: &mut SystemConfig,
    raw_blob: Blob,
    epoch_set: u32,
    cycle_end: u64,
    user: address
){

    let set = if (epoch_set > constants::half_set()) {
            constants::max()
        } else if (epoch_set > constants::first_set()) {
            constants::half_set()
        } else {
            constants::first_set()
        };

    event::emit_warlot_file_store(
        user, 
        blob::object_id(&raw_blob), 
        blob::size(&raw_blob), 
        blob::end_epoch(&raw_blob), 
        set, 
        cycle_end
        );

        raw_store_blob(
            system_cfg,
            raw_blob,
            epoch_set,
            cycle_end,
            user
        );
}




public fun deposit_coin(
     system_cfg: &mut SystemConfig,
     coin: &mut Coin<WAL>,
     amount: u64,
     ctx: &mut TxContext
): u64 {
    let user = get_user_mut(system_cfg, ctx.sender());
    let wallet_state = user.get_wallet();

    wallet_state.deposit(coin, amount, ctx)

}



// todo
// get work list form bot
// renew worklist
//  confirm work list
//  return unrenewd list


public fun renew(
    _: &mut AdminCap,
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    users: vector<address>,
    epoch_set: u32,
    // estimate: vector<u64>,
    ctx: &mut TxContext
): vector<address> {
    let insufficient = vector::empty<address>();
    let mut i = 0;

    while (i < vector::length(&users)) {
        let user_addr = *vector::borrow(&users, i);
        // let est_amt   = *vector::borrow(&estimate, i);

        // // 1) quick check & skip if not enough
        // {
        //     let user_ref = get_user_mut(system_cfg, user_addr);
        //     let wallet   = user_ref.get_wallet();
        //     if (!wallet.has_estimate(est_amt)) {
        //         vector::push_back(&mut insufficient, user_addr);
        //         i = i + 1;
        //         continue
        //     };
        // };

        // 2) actually pull out the coins you need
        let mut funds = {
            let user_ref = get_user_mut(system_cfg, user_addr);
            let wallet   = user_ref.get_wallet();
            coin::from_balance(wallet.get_balance(), ctx)
        };

       
        // 3) process each blob
        {
            let user_ref2 = get_user_mut(system_cfg, user_addr);

            let blob_list     = user_ref2.get_mut_obj_list_blob_cfg(epoch_set);
            let mut y = 0;
            while (y < vector::length(blob_list)) {

                let  funds_current_balance = funds.value();
                let blob_cfg_ref = vector::borrow_mut(blob_list, y);
                if (blob_cfg_ref.cycle_at() != blob_cfg_ref.cycle_end()) {
                    let sync_epoch: u32 = blob_cfg_ref.get_renew_epoch_count(walrus_system, epoch_set);
                    let blob_obj   = blob_cfg_ref.blob();

                   
                    // setting 0 as place holder for the renewal to be changed in update
                    


                    extend_blob(walrus_system, blob_obj, &mut funds, sync_epoch);
                    blob_cfg_ref.reduce_cycle();
                    event::emit_renew_digest(
                        user_addr, 
                        blob_cfg_ref.get_blob_obj_id(),
                        epoch_set,
                        funds_current_balance - funds.value(),
                        blob_cfg_ref.blob_size()
                    );

                    event::emit_update_blob(user_addr, blob_cfg_ref.get_blob_obj_id(), blob_cfg_ref.blob_current());


                };
                y = y + 1;
            };
        };

        // 4) return any leftover
        {
            let user_ref3 = get_user_mut(system_cfg, user_addr);
            user_ref3.get_wallet().return_balance(funds);
        };

        i = i + 1;
    };

    insufficient
}



public fun foreign_blob_add(
    registry: &mut Registry,
    system_cfg: &mut SystemConfig,
    cycle_end: u64,
    epoch_set: u32,
    blobs:  vector<Blob>,
){
    let set = if (epoch_set > constants::half_set()) {
        constants::max()
    } else if (epoch_set > constants::first_set()) {
        constants::half_set()
    } else {
        constants::first_set()
    };

    let mut temp_list = vector::empty<Blob>();
    temp_list.append(blobs);

    while(!temp_list.is_empty()){
        let raw_blob = temp_list.pop_back();


        event::emit_managed_blobs(
            registry.get_user(), 
            blob::object_id(&raw_blob), 
            blob::size(&raw_blob), 
            blob::end_epoch(&raw_blob), 
            set, 
            cycle_end);

        raw_store_blob(
            system_cfg,
            raw_blob,
            epoch_set,
            cycle_end,
            registry.get_user()
        )

         

        
    };

    temp_list.destroy_empty()
}


public(package) fun withdraw_blob(
    system_cfg: &mut SystemConfig,
    blob_obj_id: address,
    user: address,
){
    let user_ref = get_user_mut(system_cfg, user);
    let raw_blob = user_ref.
        remove_blob_from_user(object::id_from_address(blob_obj_id))
            .withdraw_and_burn();
    let blob_size = blob::size(&raw_blob) as u128;
    user_ref.reduce_dash_data(blob_size);

    let old_m_blob = system_cfg.managed_blobs;
    system_cfg.managed_blobs = old_m_blob - 1;
    event::emit_withdraw_blob(
        user,
        object::id_from_address(blob_obj_id)
    );

    transfer::public_transfer(raw_blob, user);
}

public fun self_withdraw_blob(
    registry: &mut Registry,
    system_cfg: &mut SystemConfig,
    blob_obj_id: address,
    ctx: &TxContext
){
    let user: address = registry.get_user();
    assert!(ctx.sender() == user, 3);
    withdraw_blob(system_cfg, blob_obj_id, user);
    
}


public fun replace(
    admin_cap: &mut AdminCap,
    system_cfg: &mut SystemConfig,
    old_blob_id: address,
    blob: Blob,
    epoch_set: u32,
    cycle_end: u64,
    user: address){

    withdraw_blob(system_cfg, old_blob_id, user);



    store_blob(
    admin_cap,
    system_cfg,
    blob,
    epoch_set,
    cycle_end,
    user,
    )

   
}









fun add_user(system_cfg: &mut SystemConfig,  user: User, ctx: &TxContext){
    let new_user = ctx.sender();

    assert!(!ofields::exists_(&system_cfg.id, new_user), EUserExist);

    ofields::add<address, User>(&mut system_cfg.id, new_user, user);
     
}


fun get_user_mut(system_cfg: &mut SystemConfig, user: address): &mut User{
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
