/// Mints and inspects `WriterPass`, the delegated authority to write to an inner file.
module warlot::writer_pass;

// === Imports ===

use warlot::pass_events;

// === Constants ===

/// A pass whose duration is zero is treated as one the system does not decay.
const ImmortalPASS: u64 = 0;

// === Structs ===

/// Authority to write to one inner file.
public struct WriterPass has key {
    id: UID,
    /// The file this pass authorises.
    file_id: ID,
    /// The timestamp in ms past which the pass has decayed.
    duration: u64,
    /// Present when the pass may bypass the draft queue.
    admin_privilege: Option<AdminPass>,
}

/// Carried by a pass that may push changes straight into the file's history
/// rather than into the draft queue. Given to services that write on a user's
/// behalf when the content is too large for the user's own machine.
public struct AdminPass has store, drop {
    admin: address,
}

// === Public functions ===

/// Destroy a pass.
///
/// A pass lives in its holder's account and only they can destroy it, so this is
/// the one announcement of authority ending by the holder's own hand rather than
/// by the file owner's revocation.
public fun destroy_writer_pass(pass: WriterPass, ctx: &TxContext) {
    let pass_id = object::id(&pass);
    let WriterPass { id, file_id, duration: _, admin_privilege: _ } = pass;
    id.delete();

    pass_events::emit_writer_pass_destroyed(file_id, pass_id, ctx.sender());
}

// === View functions ===

/// The file this pass authorises.
public fun file_id(pass: &WriterPass): ID {
    pass.file_id
}

/// The timestamp in ms past which the pass has decayed.
public fun duration(pass: &WriterPass): u64 {
    pass.duration
}

/// Whether the pass may bypass the draft queue.
public fun has_admin_privilege(pass: &WriterPass): bool {
    option::is_some(&pass.admin_privilege)
}

/// Whether the pass is one the system does not decay.
public fun is_immortal(pass: &WriterPass): bool {
    pass.duration == ImmortalPASS
}

/// The duration value that marks a pass as non-decaying.
public fun immortal_duration(): u64 {
    ImmortalPASS
}

// === Package functions ===

/// Mint a pass for `file_id`.
public(package) fun new(
    file_id: ID,
    duration: u64,
    admin_privilege: Option<AdminPass>,
    ctx: &mut TxContext,
): WriterPass {
    WriterPass {
        id: object::new(ctx),
        file_id,
        duration,
        admin_privilege,
    }
}

/// Hand a pass to `writer`. The pass cannot be transferred from outside this
/// module, so custody changes route through here.
///
/// Announced here rather than at the mint, for the same reason the admin
/// capability is: the holder is half of what a delegation of authority means.
public(package) fun transfer_to(
    pass: WriterPass,
    writer: address,
    system_id: ID,
    ctx: &TxContext,
) {
    pass_events::emit_writer_pass_minted(
        system_id,
        pass.file_id,
        object::id(&pass),
        writer,
        pass.duration,
        option::is_some(&pass.admin_privilege),
        ctx.sender(),
    );

    transfer::transfer(pass, writer);
}

/// Build the admin privilege carried by a bypassing pass.
public(package) fun new_admin_pass(admin: address): AdminPass {
    AdminPass { admin }
}
