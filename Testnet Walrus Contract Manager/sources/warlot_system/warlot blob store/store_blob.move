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


/*
 currently, defines the set we would be working with for the mean time
*/
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



// only an admin can use this funtion to store blobs
public(package) fun store_blob_internal(
    system_cfg: &mut SystemConfig,
    raw_blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    fileMeta_id: Option<ID>, 
    user: address,
    clock: &Clock,
    ctx: &mut TxContext,
): (ID, u64){
   
    let set = get_set(epoch_set);

    let mut size  = 0;
    let mut storage_size = 0;
    let mut end_epoch = blob::end_epoch(&raw_blobs[0]);

    let mut  raw_blobs_id = vector::empty<ID>();

    raw_blobs.do_ref!(|blob_x| {
        size = size +  blob::size(blob_x);
        storage_size = storage_size +  blob::storage(blob_x).size();
        raw_blobs_id.push_back(blob::object_id(blob_x));
        if (end_epoch  > blob::end_epoch(blob_x)) {
            end_epoch  = blob::end_epoch(blob_x)
        };


        });
    

    event::emit_warlot_file_store(
        user, 
        raw_blobs_id,
        size,
        storage_size,
        end_epoch,
        set, 
        cycle_end
    );

    let config_id = warlot_system::raw_store_blob(
        system_cfg,
        raw_blobs,
        size,
        set,
        cycle_end,
        fileMeta_id,
        user,
        clock,
        ctx
    );

    (config_id, size)
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

        let blob_size = raw_blob.size();
        vector::push_back(
            &mut config_list,

            warlot_system::raw_store_blob(
                system_cfg,
                vector::singleton(raw_blob),
                blob_size,
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



// public fun replace(
//     system_cfg: &mut SystemConfig,
//     old_blob_id: address,
//     blob: Blob,
//     epoch_set: u32,
//     cycle_end: u64,
//     user: address,
//     clock: &Clock,
//     ctx: &mut TxContext){

    
//     transfer::public_transfer(
//          warlot_system::withdraw_blob(system_cfg, old_blob_id, user),
//           user);

//     store_blob_internal(
//     system_cfg,
//     blob,
//     epoch_set,
//     cycle_end,
//     option::none(),
//     user,
//     clock,
//     ctx, 
//     );  
// }
