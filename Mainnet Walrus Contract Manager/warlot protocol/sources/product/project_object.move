/// Holds `ProjectHolder`, the per-user index over projects, their buckets and their database.
module warlot::project_object;

// === Imports ===

use std::string::String;
use sui::{clock::Clock, dynamic_object_field as ofields};

// === Errors ===

#[error]
const INVALIDACCESS: vector<u8> = b"INVALID PROJECT HOLDER";
#[error]
const NAMEINUSE: vector<u8> = b"ENTER UNUSED NAME";
#[error]
const INVALIDNAME: vector<u8> = b"Enter valid name";
#[error]
const DBEXIST: vector<u8> = b"db has been initialized";

// === Constants ===

/// Dynamic object field key for a project's bucket collection.
const BUCKETHOLDERKEY: vector<u8> = b"bucket";
/// Dynamic object field key for a project's database.
const DATABASE: vector<u8> = b"database";

// === Structs ===

/// A user's projects, indexed by name.
public struct ProjectHolder has key, store {
    id: UID,
    admin: address,
    total_projects: u64,
}

/// A project's buckets, indexed by name.
public struct BucketHolder has key, store {
    id: UID,
}

/// A project's database. The Warlot engine modifies it remotely, while the inner
/// file is what binds the user to that engine.
public struct DataBase has key, store {
    id: UID,
}

/// One project: an index over its buckets, its files and its database.
public struct Project has key, store {
    id: UID,
    name: String,
    description: vector<u8>,
    time_created: u64,
    last_modified: u64,
    db_inner_file: Option<ID>,
    buckets_created: u64,
    total_storage: u64,
}

// === Public functions ===

/// Create a project under the caller's holder.
public fun create_project(
    project_holder: &mut ProjectHolder,
    name: String,
    description: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == project_holder.admin, INVALIDACCESS);

    project_holder.total_projects = project_holder.total_projects + 1;

    let mut project = Project {
        id: object::new(ctx),
        name,
        description,
        time_created: clock.timestamp_ms(),
        last_modified: clock.timestamp_ms(),
        db_inner_file: option::none(),
        buckets_created: 0,
        total_storage: 0,
    };

    let bucket = BucketHolder { id: object::new(ctx) };
    let data_base = DataBase { id: object::new(ctx) };

    ofields::add<vector<u8>, BucketHolder>(&mut project.id, BUCKETHOLDERKEY, bucket);
    ofields::add<vector<u8>, DataBase>(&mut project.id, DATABASE, data_base);

    ofields::add<String, Project>(&mut project_holder.id, name, project);
}

/// Rename a project, keeping the holder's index in step.
public fun modify_name(
    project_holder: &mut ProjectHolder,
    old_name: String,
    new_name: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(project_holder.admin == ctx.sender(), INVALIDACCESS);
    assert!(ofields::exists_(&project_holder.id, old_name), INVALIDNAME);
    assert!(!ofields::exists_(&project_holder.id, new_name), NAMEINUSE);

    let mut project: Project = ofields::remove<String, Project>(&mut project_holder.id, old_name);
    project.name = new_name;
    project.last_modified = clock.timestamp_ms();

    ofields::add<String, Project>(&mut project_holder.id, new_name, project);
}

// === View functions ===

/// The address that owns this holder.
public fun project_admin(project_holder: &ProjectHolder): address {
    project_holder.admin
}

// === Package functions ===

/// Build an empty project holder for the sender.
public(package) fun create_project_holder(ctx: &mut TxContext): ProjectHolder {
    ProjectHolder {
        id: object::new(ctx),
        admin: ctx.sender(),
        total_projects: 0,
    }
}

/// The UID of a project's bucket collection, so buckets can be attached to it.
public(package) fun bucket_holder(
    project_holder: &mut ProjectHolder,
    project_name: String,
): &mut UID {
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    let bucket_holder = ofields::borrow_mut<vector<u8>, BucketHolder>(
        &mut project.id,
        BUCKETHOLDERKEY,
    );
    &mut bucket_holder.id
}

/// Raise a project's bucket count by one.
public(package) fun update_bucket_count(project_holder: &mut ProjectHolder, project_name: String) {
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    project.buckets_created = project.buckets_created + 1;
}

/// Add `storage_size` to a project's byte total.
public(package) fun update_storage_count(
    project_holder: &mut ProjectHolder,
    project_name: String,
    storage_size: u64,
) {
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    project.total_storage = project.total_storage + storage_size;
}

/// Name `inner_file_id` as the project's database. A project has one.
public(package) fun init_db(
    project_holder: &mut ProjectHolder,
    project_name: String,
    inner_file_id: ID,
    user: address,
) {
    assert!(project_holder.admin == user, INVALIDACCESS);
    let project = ofields::borrow_mut<String, Project>(&mut project_holder.id, project_name);
    assert!(project.db_inner_file.is_none(), DBEXIST);

    project.db_inner_file.fill(inner_file_id);
}
