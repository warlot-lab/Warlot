module warlot::bucketmain;
use sui::clock::Clock;
use sui::dynamic_object_field as ofields;
use warlot::{filemain::FileMeta, projectmain::{ProjectHolder, Self}};
use std::string::{String};



// this is an object that is responsible for the holding a collective of files i.e blobid with arttributes
public struct Bucket has key, store{
    id: UID,
    name: String,
    description: String,
    time_created: u64,
    last_modified: u64,
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
       time_created: clock.timestamp_ms(),
       last_modified: clock.timestamp_ms(),
    };

    // add bucket  to the bucket holder
    ofields::add<String, Bucket>(
        projectmain::bucket_holder(
            project_holder, project_name), 
            bucket_name, 
            bucket);


}



// get name of the bucket
public fun get_name(bucket: &Bucket): String{
    bucket.name
}

// add file type to your bucket collection
public fun add_file(bucket: &mut Bucket, file: FileMeta){
    let name = file.get_name();
    assert!(!check_file_name_created(bucket, name), InvalidName);
    ofields::add<String, FileMeta>(&mut bucket.id, name, file)

}

// chek if the bucket with the name has been created 
public fun check_file_name_created(bucket: &Bucket, file_name: String): bool{
    ofields::exists_(&bucket.id, file_name)
}


