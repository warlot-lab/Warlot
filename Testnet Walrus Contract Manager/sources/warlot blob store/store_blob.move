module warlot::store;
use walrus::{blob::{Self, Blob}};
use warlot::{
    warlot_system::{Self, SystemConfig},
    registry::Registry,
    constants::{Self},
    event::Self,
    foreign_meta::{Self, ForeignMeta},
};

use sui::clock::Clock;



// only an admin can use this funtion to store blobs
public(package) fun store_blob_internal(
    system_cfg: &mut SystemConfig,
    raw_blob: Blob,
    epoch_set: u32,
    cycle_end: u64,
    fileMeta_id: Option<ID>, 
    user: address,
    clock: &Clock,
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

    warlot_system::raw_store_blob(
        system_cfg,
        raw_blob,
        set,
        cycle_end,
        fileMeta_id,
        user,
        clock,
        ctx
    )
}



// add external blobs to system to renew
public fun foreign_blob_add(
    registry: &Registry,
    system_cfg: &mut SystemConfig,
    user_foreign_meta: &mut ForeignMeta,
    cycle_end: u64,
    epoch_set: u32,
    blobs:  vector<Blob>,
    clock: &Clock, 
    ctx: &mut TxContext,
){
    let set = get_set(epoch_set);

    let mut temp_list = vector::empty<Blob>();
    temp_list.append(blobs);

    let mut meta_peak = foreign_meta::verify_peak(user_foreign_meta);
    let avg_len = foreign_meta::avg_len();

    let mut config_list: vector<ID> = vector::empty<ID>();

    


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

        vector::push_back(
            &mut config_list,

            warlot_system::raw_store_blob(
                system_cfg,
                raw_blob,
                set,
                cycle_end,
                option::none(), 
                registry.get_user(),
                clock,
                ctx
            )
        );

        meta_peak = meta_peak + 1;

        if (meta_peak == avg_len){
            foreign_meta::add_foreign_blob(user_foreign_meta, config_list);
            config_list = vector::empty<ID>();
            meta_peak = 0;
        }

    };
    foreign_meta::add_foreign_blob(user_foreign_meta, config_list);

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
    clock: &Clock,
    ctx: &mut TxContext){

    
    transfer::public_transfer(
         warlot_system::withdraw_blob(system_cfg, old_blob_id, user),
          user);

    store_blob_internal(
    system_cfg,
    blob,
    epoch_set,
    cycle_end,
    option::none(),
    user,
    clock,
    ctx, 
    );  
}
