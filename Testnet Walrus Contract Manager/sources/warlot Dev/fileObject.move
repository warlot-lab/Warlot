module warlot::filemain;
use sui::clock::Clock;
use walrus::{blob::Blob};
use std::string::{String};
use warlot::{
    warlotsystem::SystemConfig,
    store::Self,
};




// this is an object that contains onchain atribut of blobs 
public struct FileMeta has key, store {
    id: UID, //using the indexer you can get the file by id fast
    name: String,
    description: String,
    file_type: String, // e.g .txt, .pdf, .mp4 e.t.c
    uploader: address,
    config_obj_id: ID,
    bucket: String, 
    time_created: u64,
}

// create a fileMeta
public fun create(
    system_cfg: &mut SystemConfig,
    name: String,
    description: String,
    file_type: String,
    raw_blob: Blob,
    bucket: String,
    clock: &Clock,
    epoch_set: u32,
    cycle_end: u64,
    user: address,
    ctx: &mut TxContext
): FileMeta{


    let config_obj_id =     store::store_blob_internal(system_cfg, raw_blob, epoch_set, cycle_end, user, ctx);
    let file = FileMeta{
        id : object::new(ctx),
        name,
        description,
        file_type,
        uploader: ctx.sender(),
        config_obj_id,
        bucket,
        time_created: clock.timestamp_ms(),

    };


    file 
    // let bucket_object_x = project.get_bucket(bucket);

    // bucket_object_x.add_file(file)

}

// safe get file name
public fun get_name(file: &FileMeta): String{
    file.name
}











