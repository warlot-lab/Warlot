/// Records and drops the revision an inner file's owner can fall back to.
///
/// The recovery half of the protocol, and the reason a compromised delegate is
/// survivable: revoking the credential stops the damage, and the fallback is the
/// state the owner returns to afterwards. Neither works without the other, which
/// is why they were fixed together and why this is its own surface rather than
/// two more entry points among the writes.
module warlot::entry_file_fallback;

// === Imports ===

use sui::clock::Clock;
use warlot::{
    blob_config::{Self, BlobConfig},
    eviction,
    file_data::{Self, FileData},
    inner_file::InnerFile,
    system_config::SystemConfig,
    writer_pass::WriterPass,
};

// === Errors ===

#[error]
const INVALIDACCESS: vector<u8> = b"Invalid access";
#[error]
const ENotOwnersConfig: vector<u8> = b"THIS CONFIG IS NOT HELD BY THE OWNER OF THIS FILE";

// === Public functions ===

/// Record a revision as the file's known-good fallback.
///
/// The config is named by the object rather than by its id, so that the fallback
/// cannot be pointed at content the file's owner does not hold. A fallback is the
/// state the owner intends to return to; one that names somebody else's content
/// is a fallback that can be withdrawn out from under them.
public fun set_root_change(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    commit: vector<u8>,
    config: &BlobConfig,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);
    assert!(blob_config::owner(config) == inner_file.owner(), ENotOwnersConfig);

    let file_id = object::id(inner_file);
    let system_id = object::id(system_cfg);
    let file_data: FileData = file_data::create_file_data(
        commit,
        ctx.sender(),
        blob_config::config_id(config),
    );

    let displaced = inner_file.swap_root_change(file_data, system_id);

    if (displaced.is_some()) {
        eviction::discard(displaced.destroy_some(), file_id, system_id);
    } else {
        displaced.destroy_none();
    }
}

/// Drop the file's known-good fallback.
///
/// The content it named is left alone. It is the file owner's already, it is a
/// shared object they can reach by id, and withdrawal is the one call that
/// releases it ,  so the fallback's removal announces the config and stops there
/// rather than deciding on the owner's behalf that the content is finished with.
public fun remove_root_change(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let file_id = object::id(inner_file);
    let system_id = object::id(system_cfg);

    eviction::discard(
        inner_file.extract_root_change(system_id, ctx.sender()),
        file_id,
        system_id,
    );
}
