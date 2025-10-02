module warlot::drive_meta;
use std::string::String;
use sui::{clock::Clock, dynamic_object_field as ofields};
use warlot::{ file_main::{Self, FileMeta}, warlot_system::SystemConfig};
use walrus::{blob::Blob};

public struct Drive has key, store {
    id: UID,
    owner: address,
    docs: u64,
    images: u64,
    videos: u64,
    audios: u64,
    others: u64,
    storage_size: u64,
    last_modified: u64,
}

public struct DriveMeta has store{
    root: String
}



 /// File categories (decide off-chain or by caller)
const CAT_DOC: u8 = 1;
const CAT_IMAGE: u8 = 2;
const CAT_VIDEO: u8 = 3;
const CAT_AUDIO: u8 = 4;
const CAT_OTHER: u8 = 5;




public(package) fun create(
    clock: &Clock,
    ctx: &mut TxContext
) {
    let drive_meta_UID = object::new(ctx);
    transfer::public_share_object(
        Drive {
            id: drive_meta_UID,
            owner: ctx.sender(),
            docs: 0,
            images: 0,
            videos: 0,
            audios: 0,
            others: 0,
            storage_size: 0,
            last_modified: clock.timestamp_ms(),
    }
    )
}


public fun upload_file(
    system_cfg: &mut SystemConfig,
    drive: &mut Drive,
    file_name: String,
    description: String,
    file_type: vector<u8>,
    blob: Blob,
    clock: &Clock,
    root: String,
    category: u8,          // CAT_DOC | CAT_IMAGE | CAT_VIDEO | CAT_AUDIO | CAT_OTHER
    epoch_set: u32,
    cycle_end: u64,
    user: address,
    ctx: &mut TxContext
){
    let file_size = blob.size();

     
    

    match(category) {
        CAT_DOC => drive.docs = drive.docs + 1,
        CAT_IMAGE => drive.images = drive.images + 1,
        CAT_VIDEO => drive.videos = drive.videos + 1,
        CAT_AUDIO => drive.audios = drive.audios + 1,
        CAT_OTHER => drive.others = drive.others + 1,
        _ => {}
    };



    let file: FileMeta<DriveMeta> = file_main::create<DriveMeta>(
        system_cfg,
        file_name,
        description,
        file_type.to_string(),
        blob,
        clock,
        option::some(DriveMeta{root}),
        epoch_set,
        cycle_end,
        user,
        ctx,);

    // Update bytes & last modified
    drive.storage_size = drive.storage_size + file_size;
    drive.last_modified = clock.timestamp_ms();


    add_file(drive, file);
   
}



fun add_file(drive: &mut Drive, file: FileMeta<DriveMeta>){
    let name = file.get_name();
    ofields::add<String, FileMeta<DriveMeta>>(&mut drive.id, name, file)

}




