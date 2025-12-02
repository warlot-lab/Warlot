module warlot::user_state;
use std::string::String;

use sui::{
    clock::Clock, 
    dynamic_object_field as ofields, 
    table::{Self, Table},
    bag::{Self, Bag},
    };


use warlot::{
    wallet::{Self, Wallet}, 
    config::{Self, BlobConfig}, 
    registry::{Self}, 
    constants::{Self},
    project_main::{Self, ProjectHolder},
    foreign_meta::{Self},
    };









public struct User has key, store{
    id: UID,
    owner: address,
    wallet: Wallet,
    meta_data: DashData,

    /*
    holds the  tail of the blob_congig that are associated to this epoch set
    */
    index: Bag,


}


public struct DashData has store {
    files: u128,
    storage_size: u128,
}



public struct SubPermission has store{
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
}


//  =============== errors ====================//
#[error]
const INVALIDACCESS: vector<u8> = b"permission denied";
#[error]
const EInvalidConfigId: vector<u8> = b"INVALID CONFIG ID";



public(package) fun get_wallet(user: &mut User): &mut Wallet{
    &mut user.wallet
}



public(package) fun create_user( 
    public_username: String, 
    system_id: ID, 
    clock: &Clock, 
    add_walot_permission: Option<address>,   
    ctx: &mut TxContext
    ): User{
    let safe_vault: Wallet = wallet::create_wallet(clock, ctx);

   
  
    let mut new_user = User {
         id: object::new(ctx),
         owner: ctx.sender(),
         wallet: safe_vault,
         meta_data : DashData{
            files: 0,
            storage_size: 0,
         },
         index: bag::new(ctx)
         };


    // create project holder
    let project_holder: ProjectHolder = project_main::create_project_holder(ctx);
    

    



    /*
     this will be the state at which the user can deny the warlot system or any other syem the access to modify their data
     THIS COULD INCLUDE 
     project meta,
     bucket meta,
     file meta,
     linked files
     linked bucket,
     graphql services 
     i.e all functionalites on this smart contract will be blocked from the remote server if this is done
     giving the user full control over their data set
    */
   /*
    a genneral ban will be the ban where the user does not have an alienpermission on the system 
    */
    let mut sub_permission: Table<address, SubPermission> =   table::new(ctx);

    if (option::is_some<address>(&add_walot_permission)){
        table::add<address, SubPermission>( &mut sub_permission,
        option::destroy_some<address>(add_walot_permission), 
            SubPermission{
                add_blob_to_address: true,
                create_inner_file: true,
                create_writer_pass: true,
                can_init_db: true,
            })
    } else{ option::destroy_none<address>(add_walot_permission)};

    ofields::add<vector<u8>, Table<address, SubPermission>>(&mut new_user.id, constants::Acceptance_Key(), sub_permission);

    registry::create_registry( public_username, object::id(&new_user), system_id, option::some(object::id(&project_holder)),  clock, ctx);
    
    // create foreign_meta
    /*
    this is just a micro indexer in the warlot system, it is used to keep track of the blob config that is foreign to the system 
    */ 
    foreign_meta::create_meta(ctx);

    // todo to convert to party share 
    transfer::public_share_object(project_holder);
 
    new_user
}



// ==================  permission setting ====================//
fun get_permission_obj(
    user_obj: &User,
    // request_address: address,  
    ctx: &TxContext
): &SubPermission{
    
    let sub_permission = ofields::borrow<vector<u8>, Table<address, SubPermission>>(&user_obj.id, constants::Acceptance_Key());
    
    assert!(sub_permission.contains(ctx.sender()), INVALIDACCESS);

    // check the permission object of the requester
    sub_permission.borrow(ctx.sender())
}



public fun check_permission_add_blob(
    user_obj: &User,
    // request_address: address,  
    ctx: &TxContext){

    assert!(get_permission_obj(user_obj, ctx).add_blob_to_address, INVALIDACCESS);
}


public fun check_permission_inner_file(
    user_obj: &User,
    // request_address: address,  
    ctx: &TxContext){

    assert!(get_permission_obj(user_obj, ctx).create_inner_file, INVALIDACCESS);
}




public fun check_permission_writer_pass(
    user_obj: &User,
    // request_address: address,  
    ctx: &TxContext){

    assert!(get_permission_obj(user_obj, ctx).create_writer_pass, INVALIDACCESS);
}



public fun check_permission_can_init_db(
    user_obj: &User,
    // request_address: address,  
    ctx: &TxContext){
    assert!(get_permission_obj(user_obj, ctx).can_init_db, INVALIDACCESS);
}


public(package) fun create_permission_state(
    user_obj: &mut User,
    privilege_address: address,  
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    can_init_db: bool,
    ){
        let sub_permission = ofields::borrow_mut<vector<u8>, Table<address, SubPermission>>(&mut user_obj.id, constants::Acceptance_Key());
        if (sub_permission.contains(privilege_address)){
            let privilege_permission = sub_permission.borrow_mut<address, SubPermission>(privilege_address);
            privilege_permission.add_blob_to_address = add_blob_to_address;
            privilege_permission.create_inner_file = create_inner_file;
            privilege_permission.create_writer_pass = create_writer_pass;
            privilege_permission.can_init_db = can_init_db;

        }else{
            sub_permission.add(
                privilege_address,
                SubPermission{
                    add_blob_to_address,
                    create_inner_file,
                    create_writer_pass,
                    can_init_db,
                }
            );
        };
}





//   ====================================== blob ========================================//
public(package) fun add_blob(user: &mut User, mut blob_cfg: BlobConfig, epoch: u32, ctx: &TxContext): ID{

    //this confirms that the person making this request has permission to make this request
    if (ctx.sender() != user.owner){
        check_permission_add_blob(user, ctx);
    };
    
    /* 
    done ✅ todo change this so that the system will only get the blob by the blob setting config and not the blob id,
    making sure that we can account for files larger than 13gb and light files that are predded into a single blob 
    */ 
    let blob_cfg_id = config::config_id(&blob_cfg);


    /*
    check if the blob_config have been indexed, or modify existing one
    */


    if (user.index.contains<u32>(epoch)){
      
        let pre_id = *user.index.borrow<u32, ID>(epoch);
        // set the pre in the current config
        config::set_pre(&mut blob_cfg, pre_id);


        // get and set the last head of the blob_cfg to pre the current config
        ofields::borrow_mut<ID, BlobConfig>(&mut user.id, pre_id)
            .set_next(blob_cfg_id);
        

        // modify indexer
        let indexer = user.index.borrow_mut<u32, ID>(epoch);
        *indexer =  blob_cfg_id;

    } else{
        user.index.add<u32, ID>(epoch, blob_cfg_id)

    };
    


    /*
     all blob configs are now existing in the dynamic fields of the user object regardless of the epoch meta
     but when renewal occurs or sync operation occurs; the loop occurs through the linked property of the set 
    */

    ofields::add<ID, BlobConfig>(&mut user.id, blob_cfg_id, blob_cfg);


    blob_cfg_id
}





public(package) fun update_dash_data(user: &mut User, files: u128, storage_size: u128): bool{
    let old_files =  user.meta_data.files;
    let old_storage_size = user.meta_data.storage_size;

    user.meta_data.files = files + old_files;
    user.meta_data.storage_size = storage_size + old_storage_size;
    true
}












// remove blob_cfg from user ofields
public(package) fun remove_blob_cfg_from_user(user: &mut User, blob_cfg_id: ID): BlobConfig{
    assert!(ofields::exists_<ID>(&user.id, blob_cfg_id), EInvalidConfigId);
    let blob_cfg =  ofields::remove<ID, BlobConfig>(&mut user.id, blob_cfg_id);

   // Cache neighbors and context
   let pre = blob_cfg.pre();
   let next = blob_cfg.next();
   let epoch_set : u32 = blob_cfg.epoch_set();

   //  Re-link the list
    if (option::is_some(pre) && option::is_some(next)){
        let pre_id = *option::borrow(pre);
        let next_id = *option::borrow(next);
        ofields::borrow_mut<ID, BlobConfig>(&mut user.id, pre_id)
            .set_next(next_id);
        ofields::borrow_mut<ID, BlobConfig>(&mut user.id, next_id)
            .set_pre(pre_id);
    }else if (option::is_some(pre)){
        let pre_id = *option::borrow(pre);
        // this means what is being removed is the head of the list 
        ofields::borrow_mut<ID, BlobConfig>(&mut user.id, pre_id)
            .set_next_none();
        // set as new head 
        let indexer = user.index.borrow_mut<u32, ID>(epoch_set);
        *indexer =  pre_id;
      
    }else if (option::is_some(next)){
        let next_id = *option::borrow(next);
        // since we are only keeping track of the head
        ofields::borrow_mut<ID, BlobConfig>(&mut user.id, next_id)
            .set_pre_none();
    }else{
        // Case D: Single Node (No Previous, No Next)
        // The list is now empty. Remove the index entry entirely.
        user.index.remove<u32, ID>(epoch_set);
    };

    // reduce the user dash size
    reduce_dash_data(user, config::blob_cfg_size(&blob_cfg) as u128);
   


    // returns the blob_config
    blob_cfg
   
}



fun reduce_dash_data(user: &mut User, storage_size: u128): bool{
    let old_files =  user.meta_data.files;
    let old_storage_size = user.meta_data.storage_size;

    user.meta_data.files = old_files - 1;
    user.meta_data.storage_size =  old_storage_size - storage_size;
    true
}





 
/*
 todo create a acceptance list; so that only those address can create files on thier behalf
 todo create a deny list; so that even  if the address have the permission to create files on their behalf they can not create the writer pass for them self 
 todo permission for the creator to hv a writer pass; and the duration it should exist
 todo create a general ban or deny list that will ban address from all files that belongs to an address 
 todo create the project as a sub of the user <i.e as a dynamic object field of the user object>
*/