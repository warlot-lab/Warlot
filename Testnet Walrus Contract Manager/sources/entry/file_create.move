/// Creates an inner file.
module warlot::entry_file_create;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{admin_cap::AdminCap, creation, system_config::SystemConfig};

// === Public functions ===

/// Store `blobs` as a file's first revision, share the file, and hand the owner
/// a non-decaying pass. When `should_include_pass` is set and the caller is not
/// the owner, the caller is given one that expires at `pass_duration`.
///
/// `pass_duration` is a timestamp in ms and is read only on that branch. It must
/// be in the future, which is also what keeps it away from the sentinel that
/// marks a pass non-decaying: a delegate acting on someone else's behalf is
/// given authority with an end date, never authority without one.
///
/// The three operator bits are the owner's terms for system operators on this one
/// file, taken here so a file can be born closed rather than needing a second
/// transaction to shut it. Open is the ordinary answer, because admitting
/// operators at all is a decision the account owner already made when they
/// granted the role; these are the per-file escape hatch from it.
///
/// A file that admits operators and opens neither route is refused, not
/// normalised ,  see `inner_file::set_operator_policy` for the four states the
/// three bits are there to spell.
public fun create_file(
    system_cfg: &SystemConfig,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: Option<u64>,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    operators_may_draft: bool,
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
): ID {
    system_cfg.assert_version();

    creation::new_file(
        system_cfg,
        owner,
        writers_length,
        track_back_length,
        blobs,
        epoch_set,
        cycle_end,
        clock,
        commit,
        draft_epoch_duration,
        operators_allowed,
        operators_may_bypass_draft,
        operators_may_draft,
        option::none(),
        should_include_pass,
        pass_duration,
        ctx,
    )
}

/// The same creation, made on the strength of an operator credential rather than
/// a grant against the sender's address.
///
/// It mints the operator no pass. The owner's own non-decaying pass is minted
/// either way ,  it always was, on both sides of `should_include_pass` ,  and an
/// operator does not need one: the credential is what authorises the write, and a
/// pass minted to a rotating key would have to be re-minted per file per key,
/// which is the cost this whole path exists to remove.
///
/// It names no operator policy either. The file is born admitting its creator on
/// both routes, because `create_inner_file` means "make me a file you will
/// maintain" and one the operator cannot write to is not what that grant asked
/// for. Letting the call carry the three bits would make it the one place a file's
/// terms for operators were chosen by an operator, which is the opposite of what
/// `InnerFile.operators_allowed` says it is for. The owner narrows it afterwards
/// with `entry_file_access::set_operator_policy`.
public fun create_file_as_operator(
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: Option<u64>,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    ctx: &mut TxContext,
): ID {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());

    creation::new_file(
        system_cfg,
        owner,
        writers_length,
        track_back_length,
        blobs,
        epoch_set,
        cycle_end,
        clock,
        commit,
        draft_epoch_duration,
        true,
        true,
        true,
        option::some(auth),
        false,
        0,
        ctx,
    )
}
