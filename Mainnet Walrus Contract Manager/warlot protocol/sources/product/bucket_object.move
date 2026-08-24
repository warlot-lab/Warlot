/// Holds `Bucket`, a named collection of files inside a project.
module warlot::bucket_object;

// === Imports ===

use std::string::String;
use sui::{clock::Clock, dynamic_object_field as ofields};
use walrus::blob::Blob;
use warlot::{
    file_meta::{Self, FileMeta},
    project_object::{Self, ProjectHolder},
    system_config::SystemConfig,
};

// === Errors ===

#[error]
const InvalidName: vector<u8> = b"name has been created, enter another name";
#[error]
const INVALIDACCESS: vector<u8> = b"PERMISSION DENIED";

// === Structs ===

/// A named collection of files within a project.
public struct Bucket has key, store {
    id: UID,
    name: String,
    description: String,
    storage_size: u64,
    time_created: u64,
    last_modified: u64,
}

/// The project and bucket a file belongs to.
public struct Dev has store {
    project_name: String,
    bucket_name: String,
}

// === Public functions ===

/// Create a bucket in `project_name`. Bucket names are unique within a project.
public fun create(
    project_holder: &mut ProjectHolder,
    project_name: String,
    bucket_name: String,
    description: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == project_holder.project_admin(), INVALIDACCESS);

    let bucket = Bucket {
        id: object::new(ctx),
        name: bucket_name,
        description,
        storage_size: 0,
        time_created: clock.timestamp_ms(),
        last_modified: clock.timestamp_ms(),
    };

    ofields::add<String, Bucket>(
        project_object::bucket_holder(project_holder, project_name),
        bucket_name,
        bucket,
    );

    project_holder.update_bucket_count(project_name);
}

/// Store `blobs` and file them under `bucket_name`.
public fun upload_file(
    system_cfg: &SystemConfig,
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
    ctx: &mut TxContext,
) {
    let (file_meta, file_size) = file_meta::create<Dev>(
        system_cfg,
        file_name,
        description,
        file_type,
        blobs,
        clock,
        option::some(Dev { project_name, bucket_name }),
        epoch_set,
        cycle_end,
        user,
        ctx,
    );

    let ref_bucket: &mut Bucket = ofields::borrow_mut<String, Bucket>(
        project_object::bucket_holder(project_holder, project_name),
        bucket_name,
    );

    ref_bucket.add_file(file_meta);
    ref_bucket.storage_size = ref_bucket.storage_size + file_size;
    project_holder.update_storage_count(project_name, file_size);
}

// === View functions ===

/// The bucket's name.
public fun get_name(bucket: &Bucket): String {
    bucket.name
}

/// Whether a file with this id is already in the bucket.
public fun check_file_name_created(bucket: &Bucket, file_id: ID): bool {
    ofields::exists_(&bucket.id, file_id)
}

/// Mutable access to a bucket within a project.
public fun get_bucket(
    project_holder: &mut ProjectHolder,
    project_name: String,
    bucket_name: String,
): &mut Bucket {
    ofields::borrow_mut<String, Bucket>(
        project_object::bucket_holder(project_holder, project_name),
        bucket_name,
    )
}

// === Private functions ===

fun add_file(bucket: &mut Bucket, file: FileMeta<Dev>) {
    let file_id = file.id();
    assert!(!check_file_name_created(bucket, file_id), InvalidName);
    ofields::add<ID, FileMeta<Dev>>(&mut bucket.id, file_id, file)
}
