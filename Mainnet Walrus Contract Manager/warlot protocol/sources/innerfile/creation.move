/// Builds an inner file from its first revision.
///
/// One operation, below the entry layer because two entry points need it and
/// neither may import the other: creating a file, and creating one that a project
/// immediately names as its database. Keeping it here is also what stops the
/// creation path from having two implementations that drift ,  the pass minting
/// and the delegation check happen once, wherever the call came from.
module warlot::creation;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{
    inner_file,
    operator::OperatorAuth,
    revision,
    system_config::SystemConfig,
    user,
    writer_pass,
};

// === Errors ===

#[error]
const EInvalidPassDuration: vector<u8> = b"A DELEGATED PASS MUST EXPIRE AT A FUTURE TIMESTAMP";

// === Package functions ===

/// Store `blobs` as a file's first revision, share the file, and hand out the
/// passes the creation mints.
///
/// The owner's non-decaying pass is minted on both branches: it is the file
/// owner's own authority over their own file, and `should_include_pass` decides
/// only whether the *caller* is given one as well. A caller who is the owner is
/// given nothing extra, because they already have it.
public(package) fun new_file(
    system_cfg: &SystemConfig,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    operator: Option<OperatorAuth>,
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
): ID {
    let system_id = object::id(system_cfg);

    let first_revision = revision::store_revision(
        system_cfg,
        blobs,
        epoch_set,
        cycle_end,
        owner,
        commit,
        ctx.sender(),
        operator,
        clock,
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);

    user::check_permission_inner_file(owners_obj, operator, ctx);

    let new_inner_file = inner_file::new(
        owner,
        writers_length,
        track_back_length,
        epoch_set,
        cycle_end,
        operators_allowed,
        operators_may_bypass_draft,
        draft_epoch_duration,
        first_revision,
        clock,
        ctx,
    );

    let new_inner_file_id = object::id(&new_inner_file);

    let immortal_pass = inner_file::new_owner_pass(new_inner_file_id, ctx);

    // A file created on someone else's behalf leaves the creator able to perform
    // restricted operations on it.
    if (should_include_pass && owner != ctx.sender()) {
        user::check_permission_writer_pass(owners_obj, operator, ctx);
        assert!(pass_duration > clock.timestamp_ms(), EInvalidPassDuration);

        let temp_pass = writer_pass::new(new_inner_file_id, pass_duration, true, ctx);

        writer_pass::transfer_to(temp_pass, ctx.sender(), system_id, ctx);
    };

    inner_file::share(new_inner_file, system_id);
    writer_pass::transfer_to(immortal_pass, owner, system_id, ctx);

    new_inner_file_id
}
