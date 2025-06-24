module warlot::userstate;
use std::string::String;
use warlot::{wallet::{Self, Wallet}, config::{Self, BlobSettings}, registry::{Self}, constants::{Self}};
use sui::{dynamic_field as dfield, clock::Clock, dynamic_object_field as ofields, table::{Self, Table}, bag::{Self, Bag}};




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


// this will hold the address that are allowed to make changes to the filke
public struct Acceptance has store{
    allowed: Bag<address, bool>
    deny_
}


public(package) fun create_user( public_username: String, system_id: ID, apikey: String, encrypt_key: String, warlot_sign_apikey: String, clock: &Clock, ctx: &mut TxContext): User{
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
    ofields::add<vector<u8>, Acceptance>(&mut new_user.id, constants::Acceptance_Key(), Acceptance{
        allowed: bag::new(ctx)
    } );

    registry::create_registry( public_username, object::id(&new_user), system_id, apikey, encrypt_key, warlot_sign_apikey, clock, ctx);

}


public(package) fun add_blob(user: &mut User, blob_cfg: BlobSettings, epoch: u32){
    let blob_obj_id = config::get_blob_obj_id(&blob_cfg);
    if (dfield::exists_(&user.id, epoch)){
        let blob_cfg_set: &mut vector<BlobSettings> = get_mut_obj_list_blob_cfg(user, epoch);
        // add the data to the indexer
        // since the lenght of the vector is equal to the index of the new data 
        blob_cfg_set.push_back(blob_cfg);
        let blob_index = blob_cfg_set.length() - 1;
        user.add_to_indexer(
            blob_obj_id,
            epoch,
            blob_index,
            );

      
        return
    };

    
    let mut new_blob_cfg_list : vector<BlobSettings>  = vector::empty<BlobSettings>();
    new_blob_cfg_list.push_back(blob_cfg);
    user.add_to_indexer(
            blob_obj_id,
            epoch,
            0,
            );

    dfield::add<u32, vector<BlobSettings>>(&mut user.id, epoch, new_blob_cfg_list)
}

public(package) fun get_mut_obj_list_blob_cfg(user: &mut User, epoch: u32): &mut vector<BlobSettings>{
    assert!(dfield::exists_(&user.id, epoch), 1);
    dfield::borrow_mut<u32, vector<BlobSettings>>(&mut user.id, epoch)
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
    let blob_cfg_set: &vector<BlobSettings> = dfield::borrow<u32, vector<BlobSettings>>(&user.id, blob_index_data.epoch);
    
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
    let blob_cfg_set_mut: &mut vector<BlobSettings> = get_mut_obj_list_blob_cfg(user, d_epoch);

    // remove the blob_config from the system
    let deletable_blob_cfg = blob_cfg_set_mut.swap_remove(d_vector_index);

    // update the user indexer 
    remove_from_indexer(user, deletable_blob_obj_id, replace_id);

    // returns the blob_config
    deletable_blob_cfg
}



 



// todo create a acceptance list; so that only those address can create files on thier behalf
// todo create a deny list; so that even the if the address have the permission to create fiales on their behalf they can not create the writer pass for them self 
// permission for the creator to hv a writer pass; and the duration it should exist
// todo create a general ban or deny list that will ban address from all files that belongs to an address 
