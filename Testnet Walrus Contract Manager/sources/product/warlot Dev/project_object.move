module warlot::project_main;
use sui::clock::Clock;
use sui::dynamic_object_field as ofields;

// use warlot::event;
use std::string::String;



/*
project is just an indexer for the buckets and the files
also an indexer for the tables and the sql 
*/
public struct ProjectHolder has key, store{
    id: UID,
    admin: address,
    total_projects: u64,
}


/*
holds the set of buckets for a particular project
*/
public struct BucketHolder has key, store{
    id: UID
}

/*
all tables currently exist in a single database. 
the warlot engine helps the user to remotly modify this datbase.
while the innerfile is the contract that holds the user to the warlot engine
*/
public struct DataBase has key, store{
    id: UID
}



public struct Project has key, store{
    id: UID,
    name: String,
    description: vector<u8>,
    time_created: u64,
    last_modified: u64,
    db_inner_file: Option<ID>,
    buckets_created: u64,
    total_storage: u64,
}



public(package) fun create_project_holder(ctx: &mut TxContext): ProjectHolder{
    ProjectHolder{
        id: object::new(ctx),
        admin: ctx.sender(),
        total_projects: 0,
    }

}


public(package) fun update_bucket_count(
    project_holder: &mut ProjectHolder,
    project_name: String
){
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    project.buckets_created = project.buckets_created + 1;

}



public(package) fun update_storage_count(
    project_holder: &mut ProjectHolder,
    project_name: String,
    storage_size: u64,
){
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    project.total_storage = project.total_storage  + storage_size;

}




//======errors ======//
#[error]
const INVALIDACCESS: vector<u8> = b"INVALID PROJECT HOLDER";
#[error]
const NAMEINUSE: vector<u8> = b"ENTER UNUSED NAME";
#[error]
const INVALIDNAME: vector<u8> = b"Enter valid name";
#[error]
const DBEXIST: vector<u8> = b"db has been initialized";


// ============ tree key vales ===========//
const BUCKETHOLDERKEY: vector<u8> = b"bucket";
const DATABASE: vector<u8> = b"database";

//==========helper functions ============//
public fun project_admin(project_holder: &ProjectHolder): address{
    project_holder.admin
}


// releases the bucket holder for other module to add to it
public(package) fun bucket_holder(project_holder: &mut ProjectHolder, project_name: String): &mut UID{
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    let bucket_holder = ofields::borrow_mut<vector<u8>, BucketHolder>(&mut project.id, BUCKETHOLDERKEY);
    &mut bucket_holder.id
}


// create a project
public fun create_project(
    project_holder: &mut ProjectHolder,
    name: String, 
    description: vector<u8>, 
    clock: &Clock, 
    ctx: &mut TxContext){
    // making sure that only the owner of the project holder can create this project 
    assert!(ctx.sender() == project_holder.admin ,INVALIDACCESS);

    project_holder.total_projects = project_holder.total_projects + 1;

    let mut project =  Project{
        id: object::new(ctx),
        name,
        description,
        time_created: clock.timestamp_ms(),
        last_modified: clock.timestamp_ms(),
        db_inner_file: option::none(),
        buckets_created: 0,
        total_storage: 0,
    };


    let bucket = BucketHolder{id: object::new(ctx)};
    let data_base = DataBase{id: object::new(ctx)};

    // add the properties <bucket an database>
    ofields::add<vector<u8>, BucketHolder>(&mut project.id, BUCKETHOLDERKEY, bucket);
    ofields::add<vector<u8>, DataBase>(&mut project.id, DATABASE, data_base);

    ofields::add<String, Project>(&mut project_holder.id, name, project);
}



public fun modify_name(project_holder: &mut ProjectHolder, old_name: String, new_name: String, clock: &Clock, ctx: &mut TxContext){
    // make sure that oly the user can modify the name of the project 
    assert!(project_holder. admin == ctx.sender(), INVALIDACCESS);
    // make sure that the project exist
    assert!(ofields::exists_(&project_holder.id, old_name), INVALIDNAME);
    // make sure that the new name is not in used
    assert!(!ofields::exists_(&project_holder.id, new_name), NAMEINUSE);

    let mut  project: Project = ofields::remove<String, Project>(&mut project_holder.id, old_name);
    project.name = new_name;
    project.last_modified = clock.timestamp_ms();


// add to the dynamic field with the name property
    ofields::add<String, Project>(&mut project_holder.id, new_name, project);
}


/*
    v1 warlot, has single state inner file per project
*/

public(package) fun init_db(
    project_holder: &mut ProjectHolder,
    project_name: String,
    inner_file_id: ID,
    user: address,
    ){
    // make sure that the owner is the only data that is been modified
    assert!(project_holder.admin == user, INVALIDACCESS);
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    assert!(project.db_inner_file.is_none(), DBEXIST);
    
    project.db_inner_file.fill(inner_file_id);
}












