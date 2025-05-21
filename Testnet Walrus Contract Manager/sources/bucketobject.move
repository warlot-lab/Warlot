module warlot::bucketmain;
use sui::clock::Clock;
use sui::dynamic_object_field as ofields;
use warlot::filemain::FileMeta;
use std::string::{String};

public struct Bucket has key, store{
    id: UID,
    name: String,
    description: String,
    time_created: u64
}

//======errors ======//
#[error]
const InvalidName: vector<u8> = b"name has been created, enter another name";



public fun create(
    name: String, 
    description: String, 
    clock: &Clock, 
    ctx: &mut TxContext): Bucket{
    let bucket =  Bucket{
        id: object::new(ctx),
        name,
        description,
       time_created: clock.timestamp_ms(),
    };

   bucket
}

public fun get_name(bucket: &Bucket): String{
    bucket.name
}


public fun add_file(bucket: &mut Bucket, file: FileMeta){
    let name = file.get_name();
    assert!(!check_file_name_created(bucket, name), InvalidName);
    ofields::add<String, FileMeta>(&mut bucket.id, name, file)

}

public fun check_file_name_created(bucket: &Bucket, file_name: String): bool{
    ofields::exists_(&bucket.id, file_name)
}


