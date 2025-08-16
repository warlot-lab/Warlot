module warlot::userstate;
use std::string::String;


use warlot::{
    wallet::{Self, Wallet}, 
    config::{Self, BlobSettings}, 
    registry::{Self}, 
    constants::{Self},
    projectmain::{Self, ProjectHolder},
    blob_config_vec::{Self, BlobConfigVec},
    };


use sui::{
    clock::Clock, 
    dynamic_object_field as ofields, 
    table::{Self, Table},
    };





public struct User has key, store{
    id: UID,
    owner: address,
    wallet: Wallet,
    meta_data: DashData,
}



public struct EpochState has store, drop{
    epoch: u32,
    vector_index: u64,
}


public struct DashData has store {
    files: u128,
    storage_size: u128,
}

public struct SubPermission has store{
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
}


//  =============== errors ====================//
#[error]
const INVALIDACCESS: vector<u8> = b"permission denied";


public(package) fun create_user( 
    public_username: String, 
    system_id: ID, 
    apikey: String, 
    encrypt_key: String, 
    warlot_sign_apikey: String, 
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
         }
         };

    ofields::add<String, Table<ID, EpochState>>(&mut new_user.id, constants::indexer_key(), table::new(ctx));
    // create project holder
    let project_holder: ProjectHolder = projectmain::create_project_holder(ctx);
    

  
    

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
            })
    } else{ option::destroy_none<address>(add_walot_permission)};

    ofields::add<vector<u8>, Table<address, SubPermission>>(&mut new_user.id, constants::Acceptance_Key(), sub_permission);

    registry::create_registry( public_username, object::id(&new_user), system_id, object::id(&project_holder), apikey, encrypt_key, warlot_sign_apikey, clock, ctx);
    
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



public(package) fun create_permission_state(
    user_obj: &mut User,
    privilege_address: address,  
    add_blob_to_address: bool,
    create_inner_file: bool,
    create_writer_pass: bool,
    ){
        let sub_permission = ofields::borrow_mut<vector<u8>, Table<address, SubPermission>>(&mut user_obj.id, constants::Acceptance_Key());
        if (sub_permission.contains(privilege_address)){
            let privilege_permission = sub_permission.borrow_mut<address, SubPermission>(privilege_address);
            privilege_permission.add_blob_to_address = add_blob_to_address;
            privilege_permission.create_inner_file = create_inner_file;
            privilege_permission.create_writer_pass = create_writer_pass;

        }else{
            sub_permission.add(
                privilege_address,
                SubPermission{
                    add_blob_to_address,
                    create_inner_file,
                    create_writer_pass,
                }
            );
        };
}





//   ====================================== blob ========================================//
public(package) fun add_blob(user: &mut User, blob_cfg: BlobSettings, epoch: u32, ctx: &mut TxContext): ID{
    //this confirms that the person making this request has permission to make this request
    if (ctx.sender() != user.owner){
        check_permission_add_blob(user, ctx);
    };

    let blob_obj_id = config::get_blob_obj_id(&blob_cfg);
    /* 
    todo change this so that the system will only get the blob by the blob setting config and not the blob id,
    making sure that we can account for files larger than 13gb and light files that are predded into a single blob
    
    */ 
    let config_obj_id = config::config_id(&blob_cfg);

    if (ofields::exists_(&user.id, epoch)){
        let blob_cfg_set: &mut BlobConfigVec = get_mut_obj_list_blob_cfg(user, epoch);
        // add the data to the indexer
        // since the lenght of the vector is equal to the index of the new data 
        blob_cfg_set.push_back(blob_cfg);
        let blob_index = blob_cfg_set.length() - 1;
        user.add_to_indexer(
            blob_obj_id,
            epoch,
            blob_index,
            );
            

    } else{

        
        let new_blob_cfg_list : BlobConfigVec  = blob_config_vec::singleton(blob_cfg, ctx);

        user.add_to_indexer(
                blob_obj_id,
                epoch,
                0,
                );

        ofields::add<u32, BlobConfigVec>(&mut user.id, epoch, new_blob_cfg_list);
    };

    config_obj_id
}



public(package) fun get_mut_obj_list_blob_cfg(user: &mut User, epoch: u32): &mut BlobConfigVec{
    assert!(ofields::exists_(&user.id, epoch), 1);
    ofields::borrow_mut<u32, BlobConfigVec>(&mut user.id, epoch)
}


public(package) fun get_wallet(user: &mut User): &mut Wallet{
    &mut user.wallet
}


public(package) fun update_dash_data(user: &mut User, files: u128, storage_size: u128): bool{
    let old_files =  user.meta_data.files;
    let old_storage_size = user.meta_data.storage_size;

    user.meta_data.files = files + old_files;
    user.meta_data.storage_size = storage_size + old_storage_size;
    true
}



public(package) fun reduce_dash_data(user: &mut User, storage_size: u128): bool{
    let old_files =  user.meta_data.files;
    let old_storage_size = user.meta_data.storage_size;

    user.meta_data.files = old_files - 1;
    user.meta_data.storage_size =  old_storage_size - storage_size;
    true
}



public(package) fun add_to_indexer(user: &mut User, blob_obj_id: ID, epoch: u32, vector_index: u64){
    let indexed_table = ofields::borrow_mut<String, Table<ID, EpochState>>(&mut user.id, constants::indexer_key());
    indexed_table.add(blob_obj_id, EpochState{
        epoch,
        vector_index,
    })
}



public(package) fun remove_from_indexer(user: &mut User, blob_obj_id: ID, replace: Option<ID>){
    let indexed_table = ofields::borrow_mut<String, Table<ID, EpochState>>(&mut user.id, constants::indexer_key());
    let deleted_data = indexed_table.remove(blob_obj_id);
    if (option::is_some(&replace)){
        indexed_table.borrow_mut(option::destroy_some(replace)).vector_index = deleted_data.vector_index;
    }else{
        option::destroy_none(replace)
    };

    let _ = deleted_data;
}



// this function is used to delete a blob from the system
public(package) fun remove_blob_from_user(user: &mut User, blob_obj_id: ID): BlobSettings{
    // get ref to the user indexer
    let indexed_table = ofields::borrow<String, Table<ID, EpochState>>(&user.id, constants::indexer_key());
    // get ref to the data tied to the blob_obj_id of that particular blob
    let blob_index_data = indexed_table.borrow(blob_obj_id);
    //get the vector set that the blob exist in 
    let blob_cfg_set: &BlobConfigVec = ofields::borrow<u32, BlobConfigVec>(&user.id, blob_index_data.epoch);
    
    //// we confirm if the blob is deletable or not
    
    // assert!(blob_cfg_set.borrow(blob_index_data.vector_index).is_deletable(), 2);


    // get the deletable blob_obj_id 
    let deletable_blob_obj_id = blob_cfg_set.borrow(blob_index_data.vector_index).get_blob_obj_id();

    // we get the replace blob_obj_id; which is the last item in the vector list
    let replace_id: Option<ID> = {
        if (blob_cfg_set.length() < 1) {
            option::none()
        } else {
            let possible_replacement = blob_cfg_set.borrow(blob_cfg_set.length() - 1).get_blob_obj_id();
            if (possible_replacement != deletable_blob_obj_id) {
                option::some(possible_replacement)
            } else {
                option::none()
            }
        }
    };

    // store the epoch
    let d_epoch = blob_index_data.epoch;

    // store the index
    let d_vector_index = blob_index_data.vector_index;

    // get the mut ref to the vector that holds the blobs for that epoch
    let blob_cfg_set_mut: &mut BlobConfigVec = get_mut_obj_list_blob_cfg(user, d_epoch);

    // remove the blob_config from the system
    let deletable_blob_cfg = blob_cfg_set_mut.swap_remove(d_vector_index);

    // update the user indexer 
    remove_from_indexer(user, deletable_blob_obj_id, replace_id);

    // returns the blob_config
    deletable_blob_cfg
}



 
/*
 todo create a acceptance list; so that only those address can create files on thier behalf
 todo create a deny list; so that even  if the address have the permission to create files on their behalf they can not create the writer pass for them self 
 todo permission for the creator to hv a writer pass; and the duration it should exist
 todo create a general ban or deny list that will ban address from all files that belongs to an address 
 todo create the project as a sub of the user <i.e as a dynamic object field of the user object>
*/