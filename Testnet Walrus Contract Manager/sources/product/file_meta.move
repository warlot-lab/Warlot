/// Holds `FileMeta`, the on-chain attributes attached to a stored file.
module warlot::file_meta;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{store, system_config::SystemConfig};

// === Structs ===

/// The on-chain attributes of a stored file.
public struct FileMeta<T: store> has key, store {
    id: UID,
    name: String,
    description: String,
    /// The file extension, for example `.txt`, `.pdf`, `.mp4`.
    file_type: String,
    size: u64,
    uploader: address,
    /// The blob config holding this file's content.
    config_obj_id: ID,
    /// Product-specific attributes.
    type_meta: Option<T>,
    time_created: u64,
}

// === Public functions ===

/// Store `raw_blobs` and wrap them in a file record.
public fun create<T: store>(
    system_cfg: &mut SystemConfig,
    file_name: String,
    description: String,
    file_type: String,
    raw_blobs: vector<Blob>,
    clock: &Clock,
    type_meta: Option<T>,
    epoch_set: u32,
    cycle_end: u64,
    user: address,
    ctx: &mut TxContext,
): (FileMeta<T>, u64) {
    let file_meta_UID = object::new(ctx);
    let (config_obj_id, file_size) = store::store_blob_internal(
        system_cfg,
        raw_blobs,
        epoch_set,
        cycle_end,
        option::some(object::uid_to_inner(&file_meta_UID)),
        user,
        clock,
        ctx,
    );

    (
        FileMeta<T> {
            id: file_meta_UID,
            name: file_name,
            description,
            file_type,
            size: file_size,
            uploader: ctx.sender(),
            config_obj_id,
            type_meta,
            time_created: clock.timestamp_ms(),
        },
        file_size,
    )
}

/// Destroy a file record, returning its product-specific attributes.
public fun destroy<T: store>(file_meta: FileMeta<T>): Option<T> {
    let FileMeta<T> {
        id,
        name: _,
        description: _,
        file_type: _,
        size: _,
        uploader: _,
        config_obj_id: _,
        type_meta,
        time_created: _,
    } = file_meta;
    id.delete();
    type_meta
}

// === View functions ===

/// The file's name.
public fun get_name<T: store>(file: &FileMeta<T>): String {
    file.name
}

/// The file record's object id.
public(package) fun id<T: store>(file_meta: &FileMeta<T>): ID {
    object::id(file_meta)
}

/// The file's unencoded size.
public(package) fun size<T: store>(file_meta: &FileMeta<T>): u64 {
    file_meta.size
}
