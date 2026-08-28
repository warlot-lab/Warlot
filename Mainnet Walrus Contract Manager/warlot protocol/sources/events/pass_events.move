/// Declares the events delegated write authority raises: a pass minted or
/// destroyed, and the two revocations a file owner holds.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::pass_events;

// === Imports ===

use sui::event;

// === Events ===

/// A writer pass reached an account.
public struct WriterPassMinted has copy, drop, store {
    system_id: ID,
    file_id: ID,
    pass_id: ID,
    holder: address,
    duration: u64,
    admin_privilege: bool,
    minted_by: address,
}

/// A writer pass was destroyed by whoever held it.
///
/// The one event with no `system_id`. A pass names a file rather than a system,
/// it is an owned object its holder destroys on their own, and there is no
/// `SystemConfig` anywhere on that call path ,  requiring one would put a shared
/// object into a transaction that otherwise touches none.
public struct WriterPassDestroyed has copy, drop, store {
    file_id: ID,
    pass_id: ID,
    destroyed_by: address,
}

/// A file owner refused one pass, permanently.
public struct WriterPassRevoked has copy, drop, store {
    system_id: ID,
    file_id: ID,
    pass_id: ID,
    revoked_by: address,
}

/// A file owner refused an address, until `until_ms` or indefinitely when zero.
public struct WriterDenied has copy, drop, store {
    system_id: ID,
    file_id: ID,
    writer: address,
    until_ms: u64,
    denied_by: address,
}

/// A file owner lifted an address's denial.
public struct WriterUndenied has copy, drop, store {
    system_id: ID,
    file_id: ID,
    writer: address,
    undenied_by: address,
}

// === Package functions ===

/// Announce a writer pass reaching an account.
public(package) fun emit_writer_pass_minted(
    system_id: ID,
    file_id: ID,
    pass_id: ID,
    holder: address,
    duration: u64,
    admin_privilege: bool,
    minted_by: address,
) {
    event::emit(WriterPassMinted {
        system_id,
        file_id,
        pass_id,
        holder,
        duration,
        admin_privilege,
        minted_by,
    })
}

/// Announce a writer pass destroyed by its holder.
public(package) fun emit_writer_pass_destroyed(file_id: ID, pass_id: ID, destroyed_by: address) {
    event::emit(WriterPassDestroyed { file_id, pass_id, destroyed_by })
}

/// Announce a revoked writer pass.
public(package) fun emit_writer_pass_revoked(
    system_id: ID,
    file_id: ID,
    pass_id: ID,
    revoked_by: address,
) {
    event::emit(WriterPassRevoked { system_id, file_id, pass_id, revoked_by })
}

/// Announce a denied writer.
public(package) fun emit_writer_denied(
    system_id: ID,
    file_id: ID,
    writer: address,
    until_ms: u64,
    denied_by: address,
) {
    event::emit(WriterDenied { system_id, file_id, writer, until_ms, denied_by })
}

/// Announce a lifted denial.
public(package) fun emit_writer_undenied(
    system_id: ID,
    file_id: ID,
    writer: address,
    undenied_by: address,
) {
    event::emit(WriterUndenied { system_id, file_id, writer, undenied_by })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `WriterPassMinted`, in declaration order.
public fun read_writer_pass_minted(e: &WriterPassMinted): (
    ID,
    ID,
    ID,
    address,
    u64,
    bool,
    address,
) {
    let WriterPassMinted {
        system_id: _system_id,
        file_id: _file_id,
        pass_id: _pass_id,
        holder: _holder,
        duration: _duration,
        admin_privilege: _admin_privilege,
        minted_by: _minted_by,
    } = e;

    (*_system_id, *_file_id, *_pass_id, *_holder, *_duration, *_admin_privilege, *_minted_by)
}

#[test_only]
/// Every field of `WriterPassDestroyed`, in declaration order.
public fun read_writer_pass_destroyed(e: &WriterPassDestroyed): (ID, ID, address) {
    let WriterPassDestroyed {
        file_id: _file_id,
        pass_id: _pass_id,
        destroyed_by: _destroyed_by,
    } = e;

    (*_file_id, *_pass_id, *_destroyed_by)
}

#[test_only]
/// Every field of `WriterPassRevoked`, in declaration order.
public fun read_writer_pass_revoked(e: &WriterPassRevoked): (ID, ID, ID, address) {
    let WriterPassRevoked {
        system_id: _system_id,
        file_id: _file_id,
        pass_id: _pass_id,
        revoked_by: _revoked_by,
    } = e;

    (*_system_id, *_file_id, *_pass_id, *_revoked_by)
}

#[test_only]
/// Every field of `WriterDenied`, in declaration order.
public fun read_writer_denied(e: &WriterDenied): (ID, ID, address, u64, address) {
    let WriterDenied {
        system_id: _system_id,
        file_id: _file_id,
        writer: _writer,
        until_ms: _until_ms,
        denied_by: _denied_by,
    } = e;

    (*_system_id, *_file_id, *_writer, *_until_ms, *_denied_by)
}

#[test_only]
/// Every field of `WriterUndenied`, in declaration order.
public fun read_writer_undenied(e: &WriterUndenied): (ID, ID, address, address) {
    let WriterUndenied {
        system_id: _system_id,
        file_id: _file_id,
        writer: _writer,
        undenied_by: _undenied_by,
    } = e;

    (*_system_id, *_file_id, *_writer, *_undenied_by)
}
