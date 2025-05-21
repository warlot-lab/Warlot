module warlot::filemain;
use sui::clock::Clock;
use std::string::{String};


public struct FileMeta has key, store {
    id: UID, //using the indexer you can get the file by id fast
    name: String,
    description: String,
    file_type: String, // e.g .txt, .pdf, .mp4 e.t.c
    uploader: address,
    blod_id: String,
    blob_object_id: address,
    bucket: String, 
    time_created: u64,
 }

public fun create(
    name: String,
    description: String,
    file_type: String,
    blod_id: String,
    blob_object_id: address,
    bucket: String,
    clock: &Clock,
    ctx: &mut TxContext
): FileMeta{
    let file = FileMeta{
        id : object::new(ctx),
        name,
        description,
        file_type,
        uploader: ctx.sender(),
        blod_id,
        blob_object_id,
        bucket,
        time_created: clock.timestamp_ms(),

    };


    file 
    // let bucket_object_x = project.get_bucket(bucket);

    // bucket_object_x.add_file(file)

}


public fun get_name(file: &FileMeta): String{
    file.name
}











