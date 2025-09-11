module warlot::file_main;
use sui::clock::Clock;
use walrus::{blob::Blob};
use std::string::{String};
use warlot::{
    warlot_system::SystemConfig,
    store::Self,
};




// this is an object that contains onchain atribut of blobs 
public struct FileMeta<T:  store>  has key, store {
    id: UID, //using the indexer you can get the file by id fast
    name: String,
    description: String,
    file_type: String, // e.g .txt, .pdf, .mp4 e.t.c
    uploader: address,
    config_obj_id: ID,
    type_meta: Option<T>, // this is a generic type that can be used to store additional information about the file
    time_created: u64,
}





// create a fileMeta
public fun create<T: store>(
    system_cfg: &mut SystemConfig,
    file_name: String,
    description: String,
    file_type: String,
    raw_blob: Blob,
    clock: &Clock,
    type_meta: Option<T>,
    epoch_set: u32,
    cycle_end: u64,
    user: address,
    ctx: &mut TxContext
): FileMeta<T>{

    let file_meta_UID = object::new(ctx);
    let config_obj_id =   store::store_blob_internal(
        system_cfg, 
        raw_blob, 
        epoch_set, 
        cycle_end, 
        option::some(
            object::uid_to_inner(&file_meta_UID)
            ),
        user, 
        clock,
        ctx
        );


    FileMeta<T>{
        id : file_meta_UID,
        name: file_name,
        description,
        file_type,
        uploader: ctx.sender(),
        config_obj_id,
        type_meta,
        time_created: clock.timestamp_ms(),
    }


    // let bucket_object_x = project.get_bucket(bucket);

    // bucket_object_x.add_file(file)

}


// safe get file name
public fun get_name<T: store>(file: &FileMeta<T>): String{
    file.name
}











