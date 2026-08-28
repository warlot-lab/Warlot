/// Holds `ProjectHolder`, the authority root over a user's projects, and
/// `Project`, the id-keyed record carrying a project's database and its
/// commitment to the paths it resolves.
///
/// A project used to be keyed by its name and to carry that name, a description,
/// two timestamps and two counters. None of it was read by any contract
/// function, and keying by name made a rename an object removed and re-added.
/// What is left is the two things a contract does read ,  the address allowed to
/// act on the holder, and the one inner file the project may name as its
/// database ,  plus the 32-byte root that binds the names now living off chain
/// to the content they resolve to.
module warlot::project_object;

// === Imports ===

use sui::dynamic_object_field as ofields;
use warlot::{file_set, product_events};

// === Errors ===

#[error]
const INVALIDACCESS: vector<u8> = b"INVALID PROJECT HOLDER";
#[error]
const ENoSuchProject: vector<u8> = b"THIS HOLDER HOLDS NO PROJECT WITH THAT ID";
#[error]
const DBEXIST: vector<u8> = b"db has been initialized";

// === Structs ===

/// A user's projects, indexed by the id each was minted with.
public struct ProjectHolder has key, store {
    id: UID,
    /// The address that may create projects here and edit the ones it holds.
    admin: address,
}

/// One project: the inner file acting as its database, and its commitment.
public struct Project has key, store {
    id: UID,
    /// The inner file this project uses as its database. A project has one, and
    /// naming it is the one irreversible thing a project record does.
    db_inner_file: Option<ID>,
    /// The 32-byte Merkle root over this project's `(path, content_hash)` pairs.
    ///
    /// The names themselves are off chain. This is what stops whoever holds that
    /// database from deciding which content answers to which path: a user
    /// recomputes the root from what they believe they stored and holds it
    /// against this field.
    file_set_root: vector<u8>,
}

// === Public functions ===

/// Mint a project under the caller's holder and return its id.
///
/// The id is the project's identity from here on, and it is announced rather
/// than derivable: a project carries no name, so nothing off chain can compute
/// it. It opens committed to the empty file set.
public fun create_project(project_holder: &mut ProjectHolder, ctx: &mut TxContext): ID {
    assert!(ctx.sender() == project_holder.admin, INVALIDACCESS);

    let project = Project {
        id: object::new(ctx),
        db_inner_file: option::none(),
        file_set_root: file_set::empty_root(),
    };

    let project_id = object::id(&project);
    let file_set_root = project.file_set_root;

    ofields::add<ID, Project>(&mut project_holder.id, project_id, project);

    product_events::emit_project_created(
        object::id(project_holder),
        project_id,
        ctx.sender(),
        file_set_root,
    );

    project_id
}

/// Replace a project's commitment to the paths it resolves.
///
/// A rename, an upload and a deletion all land here as one 32-byte write, where
/// under the previous shape a rename removed and re-added a whole object. The
/// root is not recomputed on chain ,  the set it commits to lives off chain and
/// can be far larger than a transaction ,  so what the chain enforces is that the
/// value is a well-formed root, that only the holder's admin may move it, and
/// that every move is announced.
public fun set_file_set_root(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    file_set_root: vector<u8>,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == project_holder.admin, INVALIDACCESS);
    file_set::assert_valid_root(&file_set_root);

    let holder_id = object::id(project_holder);
    let project = borrow_project_mut(project_holder, project_id);
    let previous_root = project.file_set_root;

    project.file_set_root = file_set_root;

    product_events::emit_project_file_set_root_changed(
        holder_id,
        project_id,
        file_set_root,
        previous_root,
        ctx.sender(),
    );
}

// === View functions ===

/// The address that owns this holder.
public fun project_admin(project_holder: &ProjectHolder): address {
    project_holder.admin
}

/// Whether this holder holds a project with that id.
public fun has_project(project_holder: &ProjectHolder, project_id: ID): bool {
    ofields::exists_<ID>(&project_holder.id, project_id)
}

/// The inner file a project names as its database, if it has named one.
public fun db_inner_file(project_holder: &ProjectHolder, project_id: ID): Option<ID> {
    borrow_project(project_holder, project_id).db_inner_file
}

/// A project's commitment to the paths it resolves.
public fun file_set_root(project_holder: &ProjectHolder, project_id: ID): vector<u8> {
    borrow_project(project_holder, project_id).file_set_root
}

// === Package functions ===

/// Build an empty project holder for the sender.
public(package) fun create_project_holder(ctx: &mut TxContext): ProjectHolder {
    let project_holder = ProjectHolder {
        id: object::new(ctx),
        admin: ctx.sender(),
    };

    product_events::emit_project_holder_created(object::id(&project_holder), project_holder.admin);

    project_holder
}

/// Name `inner_file_id` as the project's database. A project has one.
public(package) fun init_db(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    inner_file_id: ID,
    user: address,
) {
    assert!(project_holder.admin == user, INVALIDACCESS);

    let holder_id = object::id(project_holder);
    let project = borrow_project_mut(project_holder, project_id);
    assert!(project.db_inner_file.is_none(), DBEXIST);

    project.db_inner_file.fill(inner_file_id);

    product_events::emit_project_database_initialised(
        holder_id,
        project_id,
        inner_file_id,
        user,
    );
}

// === Private functions ===

/// The project `project_id`, or an abort naming the miss.
fun borrow_project(project_holder: &ProjectHolder, project_id: ID): &Project {
    assert!(has_project(project_holder, project_id), ENoSuchProject);

    ofields::borrow<ID, Project>(&project_holder.id, project_id)
}

/// Mutable access to the project `project_id`, or an abort naming the miss.
fun borrow_project_mut(project_holder: &mut ProjectHolder, project_id: ID): &mut Project {
    assert!(has_project(project_holder, project_id), ENoSuchProject);

    ofields::borrow_mut<ID, Project>(&mut project_holder.id, project_id)
}
