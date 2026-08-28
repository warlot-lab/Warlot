/// Declares the events the project layer raises: a holder minted, a project
/// minted, its database named, and its commitment moved.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::product_events;

// === Imports ===

use sui::event;

// === Events ===

/// A project holder was minted for an address.
public struct ProjectHolderCreated has copy, drop, store {
    holder_id: ID,
    /// The address that may create and edit projects under this holder.
    admin: address,
}

/// A project was minted under a holder.
///
/// A project is addressed by a minted id and carries no name, so this event is
/// the only announcement of the id ever existing. Without it a reader holding
/// only the label a user typed has nothing to resolve it to.
public struct ProjectCreated has copy, drop, store {
    holder_id: ID,
    project_id: ID,
    created_by: address,
    /// The commitment the project opens with, which is the root of the empty set.
    file_set_root: vector<u8>,
}

/// An inner file was named as a project's database.
public struct ProjectDatabaseInitialised has copy, drop, store {
    holder_id: ID,
    project_id: ID,
    inner_file_id: ID,
    initialised_by: address,
}

/// A project's commitment to its path to content mapping was replaced.
///
/// The root is the whole of what the chain attests about a naming layer that
/// otherwise lives off chain, so every move of it is announced. A reader that
/// missed one would verify a database against a commitment it no longer matches.
public struct ProjectFileSetRootChanged has copy, drop, store {
    holder_id: ID,
    project_id: ID,
    file_set_root: vector<u8>,
    previous_root: vector<u8>,
    changed_by: address,
}

// === Package functions ===

/// Announce a minted project holder.
public(package) fun emit_project_holder_created(holder_id: ID, admin: address) {
    event::emit(ProjectHolderCreated { holder_id, admin })
}

/// Announce a minted project.
public(package) fun emit_project_created(
    holder_id: ID,
    project_id: ID,
    created_by: address,
    file_set_root: vector<u8>,
) {
    event::emit(ProjectCreated { holder_id, project_id, created_by, file_set_root })
}

/// Announce a project's database.
public(package) fun emit_project_database_initialised(
    holder_id: ID,
    project_id: ID,
    inner_file_id: ID,
    initialised_by: address,
) {
    event::emit(ProjectDatabaseInitialised {
        holder_id,
        project_id,
        inner_file_id,
        initialised_by,
    })
}

/// Announce a project's commitment moving.
public(package) fun emit_project_file_set_root_changed(
    holder_id: ID,
    project_id: ID,
    file_set_root: vector<u8>,
    previous_root: vector<u8>,
    changed_by: address,
) {
    event::emit(ProjectFileSetRootChanged {
        holder_id,
        project_id,
        file_set_root,
        previous_root,
        changed_by,
    })
}

// === Test-only helpers ===

#[test_only]
/// Every field of `ProjectHolderCreated`, in declaration order.
public fun read_project_holder_created(e: &ProjectHolderCreated): (ID, address) {
    let ProjectHolderCreated { holder_id: _holder_id, admin: _admin } = e;

    (*_holder_id, *_admin)
}

#[test_only]
/// Every field of `ProjectCreated`, in declaration order.
public fun read_project_created(e: &ProjectCreated): (ID, ID, address, vector<u8>) {
    let ProjectCreated {
        holder_id: _holder_id,
        project_id: _project_id,
        created_by: _created_by,
        file_set_root: _file_set_root,
    } = e;

    (*_holder_id, *_project_id, *_created_by, *_file_set_root)
}

#[test_only]
/// Every field of `ProjectDatabaseInitialised`, in declaration order.
public fun read_project_database_initialised(e: &ProjectDatabaseInitialised): (ID, ID, ID, address) {
    let ProjectDatabaseInitialised {
        holder_id: _holder_id,
        project_id: _project_id,
        inner_file_id: _inner_file_id,
        initialised_by: _initialised_by,
    } = e;

    (*_holder_id, *_project_id, *_inner_file_id, *_initialised_by)
}

#[test_only]
/// Every field of `ProjectFileSetRootChanged`, in declaration order.
public fun read_project_file_set_root_changed(
    e: &ProjectFileSetRootChanged,
): (ID, ID, vector<u8>, vector<u8>, address) {
    let ProjectFileSetRootChanged {
        holder_id: _holder_id,
        project_id: _project_id,
        file_set_root: _file_set_root,
        previous_root: _previous_root,
        changed_by: _changed_by,
    } = e;

    (*_holder_id, *_project_id, *_file_set_root, *_previous_root, *_changed_by)
}
