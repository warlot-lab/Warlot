module warlot::store;
use walrus::{blob::{Self, Blob}};
use warlot::{
    warlotsystem::{Self, SystemConfig},
    registry::Registry,
    constants::{Self},
    event::Self,
};



// only an admin can use this funtion to store blobs
public fun store_blob_internal(
    system_cfg: &mut SystemConfig,
    raw_blob: Blob,
    epoch_set: u32,
    cycle_end: u64,
    user: address,
    ctx: &mut TxContext,
): ID{
   
    let set = get_set(epoch_set);

    event::emit_warlot_file_store(
        user, 
        blob::object_id(&raw_blob), 
        blob::size(&raw_blob), 
        blob::storage(&raw_blob).size(),
        blob::end_epoch(&raw_blob), 
        set, 
        cycle_end
    );

    warlotsystem::raw_store_blob(
        system_cfg,
        raw_blob,
        set,
        cycle_end,
        user,
        ctx
    )
}



// add external blobs to system to renew
public fun foreign_blob_add(
    registry: &mut Registry,
    system_cfg: &mut SystemConfig,
    cycle_end: u64,
    epoch_set: u32,
    blobs:  vector<Blob>,
    ctx: &mut TxContext,
){
    let set = get_set(epoch_set);

    let mut temp_list = vector::empty<Blob>();
    temp_list.append(blobs);

    while(!temp_list.is_empty()){
        let raw_blob = temp_list.pop_back();


        event::emit_managed_blobs(
            registry.get_user(), 
            blob::object_id(&raw_blob), 
            blob::size(&raw_blob), 
            blob::storage(&raw_blob).size(),
            blob::end_epoch(&raw_blob), 
            set, 
            cycle_end);

        warlotsystem::raw_store_blob(
            system_cfg,
            raw_blob,
            set,
            cycle_end,
            registry.get_user(),
            ctx
        );

         

        
    };

    temp_list.destroy_empty()
}



fun get_set(epoch_set: u32): u32{
     let set = if (epoch_set > constants::half_set()) {
        constants::max()
    } else if (epoch_set > constants::first_set()) {
        constants::half_set()
    } else {
        constants::first_set()
    };

    set
}


public fun replace(
    system_cfg: &mut SystemConfig,
    old_blob_id: address,
    blob: Blob,
    epoch_set: u32,
    cycle_end: u64,
    user: address,
    ctx: &mut TxContext){

    
    transfer::public_transfer(
         warlotsystem::withdraw_blob(system_cfg, old_blob_id, user),
          user);

    store_blob_internal(
    system_cfg,
    blob,
    epoch_set,
    cycle_end,
    user,
    ctx, 
    );  
}
