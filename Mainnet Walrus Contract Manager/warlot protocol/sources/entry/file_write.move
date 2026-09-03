/// Writes to an inner file: straight into its history, or into its draft queue.
module warlot::entry_file_write;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{
    admin_cap::AdminCap,
    blob_config::BlobConfig,
    credential::{Self, Credential},
    draft,
    eviction,
    file_data::FileData,
    inner_file::InnerFile,
    operator::OperatorAuth,
    revision,
    system_config::SystemConfig,
    user,
    writer_pass::WriterPass,
};

// === Errors ===

#[error]
const ACCESSDENIED: vector<u8> = b"invalid writer pass";
#[error]
const INVALIDACCESS: vector<u8> = b"Invalid access";
#[error]
const ENoAddBlobGrant: vector<u8> =
    b"THIS FILE'S OWNER HAS NOT GRANTED ADD_BLOB_TO_ADDRESS TO THIS OPERATOR";

// === Public functions ===

/// Write straight into the file's history, bypassing the draft queue.
///
/// Changes made this way cannot be reversed except through the rollback window.
///
/// `evicted` carries the config named by the revision this write pushes out of
/// the window, and is empty when the window still has room. See
/// `eviction::advance_history` for when each is required.
///
/// Owner-only, so it has no operator sibling: the owner check is strictly
/// stronger than any credential could be, and an operator that could satisfy it
/// would be the file's owner.
public fun force_write_innerfile(
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);

    let file_data: FileData = revision::store_revision(
        system_cfg,
        blobs,
        inner_file.epoch_set(),
        inner_file.cycle_end(),
        inner_file.owner(),
        commit,
        ctx.sender(),
        option::none(),
        clock,
        ctx,
    );

    eviction::advance_history(inner_file, file_data, evicted, clock, object::id(system_cfg));
}

/// Write to the file, either as a draft awaiting the owner's merge or, with an
/// admin pass, straight into the file's history.
///
/// `issue` is an opaque reference to whatever the draft resolves, recorded in
/// the audit trail because it is part of what the owner agreed to when merging.
/// Nothing on chain interprets it: the tracker it used to name was three objects
/// per file that no reachable function ever wrote to.
public fun write_(
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    to_draft: bool,
    issue: Option<ID>,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    write_core(
        inner_file,
        credential::from_pass(writer_pass),
        writer_pass.has_admin_privilege(),
        to_draft,
        issue,
        clock,
        system_cfg,
        blobs,
        commit,
        evicted,
        option::none(),
        ctx,
    )
}

/// The same write, made on the strength of an operator credential rather than a
/// pass minted on this file.
///
/// The only one of the seven pass-taking calls that gains a sibling. The other
/// six assert that the sender is the file's owner, so a credential adds nothing
/// to them: an operator that could satisfy that assert would be the owner.
///
/// `to_draft` is a request rather than an instruction here. An operator asking to
/// skip the queue is routed into it anyway unless its own slot **and** this file
/// both carry the bypass ,  the owner's refusal is not something an admin can
/// grant its way past. A pass without the privilege is refused outright instead,
/// which is the behaviour that path has always had and keeps.
///
/// A write that ends in the queue is custodied by whoever pushed it, exactly as a
/// pass holder's draft is, so the routing carries the storage cost away from the
/// owner along with the content. That means a signing key whose writes can be
/// queued must itself be a registered user. A key that always bypasses never
/// stores under its own address and needs no registration at all.
public fun write_as_operator(
    inner_file: &mut InnerFile,
    admin_cap: &AdminCap,
    to_draft: bool,
    issue: Option<ID>,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());
    inner_file.verify_operator(ctx.sender(), &auth, clock);

    let may_bypass = auth.auth_may_bypass_draft() && inner_file.operators_may_bypass_draft();

    // Only a write that reaches history stores under the file's owner, and that
    // store asks the owner for `add_blob_to_address` three frames down in
    // `store::raw_store_blob`. A queued write is custodied by the sender and
    // asks the owner for nothing, so the grant is required in exactly the case
    // the routing below sends to history.
    //
    // The refusal is the same one `store` would give, moved to where the caller
    // can act on it and given a name. `store`'s denial is shared by every
    // delegated path and cannot say which grant was missing.
    if (!to_draft && may_bypass) {
        assert!(
            user::may_add_blob(
                user::get_user(system_cfg, inner_file.owner()),
                option::some(auth),
                ctx,
            ),
            ENoAddBlobGrant,
        );
    };

    write_core(
        inner_file,
        credential::from_operator(admin_cap),
        may_bypass,
        to_draft,
        issue,
        clock,
        system_cfg,
        blobs,
        commit,
        evicted,
        option::some(auth),
        ctx,
    )
}

// === Private functions ===

/// Take one revision from `credential`, into the file's history or into its draft
/// queue.
///
/// `may_bypass` is whether the credential itself permits skipping the queue: for
/// a pass, its admin privilege; for an operator, its slot's bypass bit **and**
/// the file's own, so an owner who refused the bypass cannot be overridden by an
/// admin who granted it.
///
/// What a refused bypass does differs by kind, deliberately. A pass without the
/// privilege asking to skip the queue is refused, which is what it has always
/// done. An operator without it is routed into the queue instead, because the
/// owner's answer to an operator is *where the write goes*, not whether it
/// happens ,  that routing is the whole content of `operators_may_bypass_draft`.
///
/// A routed write carries the sender's custody rather than the owner's, and
/// retires nothing, so a caller that asked to skip the queue and passed the
/// config for the revision it would have evicted is refused by name.
fun write_core(
    inner_file: &mut InnerFile,
    credential: Credential,
    may_bypass: bool,
    to_draft: bool,
    issue: Option<ID>,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    operator: Option<OperatorAuth>,
    ctx: &mut TxContext,
) {
    let mut queue = to_draft;

    if (!to_draft) {
        if (credential.is_operator()) {
            queue = !may_bypass;
        } else {
            assert!(may_bypass, ACCESSDENIED);
        };
    };

    // A draft's blobs stay with the writer who pushed them; a merge's belong to
    // the file's owner.
    let store_to: address = {
        if (queue) {
            ctx.sender()
        } else {
            inner_file.owner()
        }
    };

    let file_data: FileData = revision::store_revision(
        system_cfg,
        blobs,
        inner_file.epoch_set(),
        inner_file.cycle_end(),
        store_to,
        commit,
        ctx.sender(),
        operator,
        clock,
        ctx,
    );

    let system_id = object::id(system_cfg);

    if (!queue) {
        eviction::advance_history(inner_file, file_data, evicted, clock, system_id);
        return
    };

    // A draft displaces nothing, so it can retire nothing.
    eviction::assert_no_config(evicted);

    let file_draft = draft::create_draft(issue, option::some(file_data), ctx);

    inner_file.pin_draft(file_draft, credential, clock, system_id, ctx);
}
