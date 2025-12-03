module warlot::bucket_main;
use sui::clock::Clock;
use sui::dynamic_object_field as ofields;
use warlot::{file_main::{Self, FileMeta}, project_main::{ProjectHolder, Self},   warlot_system::SystemConfig};
use std::string::{String};
use walrus::{blob::Blob};



// this is an object that is responsible for the holding a collective of files i.e blobid with arttributes
public struct Bucket has key, store{
    id: UID,
    name: String,
    description: String,
    storage_size: u64,
    time_created: u64,
    last_modified: u64,
}

// file meta type for the dev object
public struct Dev has store{
    project_name: String,
    bucket_name: String, 
}



//======errors ======//
#[error]
const InvalidName: vector<u8> = b"name has been created, enter another name";

#[error]
const INVALIDACCESS: vector<u8> = b"PERMISSION DENIED";

// public function to create a bucket
// onces created the name of the bucket becomes unique
public fun create(
    project_holder: &mut ProjectHolder,
    project_name: String,
    bucket_name: String, 
    description: String, 
    clock: &Clock, 
    ctx: &mut TxContext){
    // check if admin
    assert!(ctx.sender() == project_holder.project_admin(), INVALIDACCESS);


    let bucket =  Bucket{
        id: object::new(ctx),
        name: bucket_name,
        description,
        storage_size: 0,
       time_created: clock.timestamp_ms(),
       last_modified: clock.timestamp_ms(),
    };

    // add bucket  to the bucket holder
    ofields::add<String, Bucket>(
        project_main::bucket_holder(
            project_holder, project_name), 
            bucket_name, 
            bucket);         

    project_holder.update_bucket_count(project_name);   
}






public fun upload_file(
    system_cfg: &mut SystemConfig,
    project_holder: &mut ProjectHolder,
    project_name: String,
    bucket_name: String,
    file_name: String,
    description: String,
    file_type: String,
    blobs: vector<Blob>,
    clock: &Clock,
    epoch_set: u32,
    cycle_end: u64,
    user: address,
    ctx: &mut TxContext
){

   
    let (file_meta, file_size) = file_main::create<Dev>(
        system_cfg,
        file_name,
        description,
        file_type,
        blobs,
        clock,
        option::some(Dev{project_name, bucket_name}),
        epoch_set,
        cycle_end,
        user,
        ctx,
    );

    let ref_bucket: &mut Bucket = ofields::borrow_mut<String, Bucket>(
        project_main::bucket_holder(
            project_holder, project_name), 
            bucket_name);  

 
    ref_bucket.add_file(file_meta);
    ref_bucket.storage_size = ref_bucket.storage_size + file_size;
    project_holder.update_storage_count(project_name, file_size);
    // file name + file type
    // event::emit_warlot_attribute(ctx.sender(), object::id_from_address(blob_object_id), project.name, bucket_name, file_name, file_type)
}




// get name of the bucket
public fun get_name(bucket: &Bucket): String{
    bucket.name
}


// add file type to your bucket collection
fun add_file(bucket: &mut Bucket, file: FileMeta<Dev>){
    let file_id = file.id();
    assert!(!check_file_name_created(bucket, file_id), InvalidName);
    ofields::add<ID, FileMeta<Dev>>(&mut bucket.id, file_id, file)

}

// chek if the bucket with the name has been created 
public fun check_file_name_created(bucket: &Bucket, file_id: ID): bool{
    ofields::exists_(&bucket.id, file_id)
}



//get bucket mut 
public fun get_bucket(project_holder: &mut ProjectHolder, project_name: String, bucket_name: String): &mut Bucket{
    ofields::borrow_mut<String, Bucket>( project_main::bucket_holder(project_holder, project_name), bucket_name)
}