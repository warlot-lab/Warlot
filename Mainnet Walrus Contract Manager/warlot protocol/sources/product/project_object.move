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
///
/// Nothing here decides whether a caller is allowed to act. The holder's `admin`
/// is checked against an address the caller supplies, and establishing that the
/// address is the one whose permission was tested is the entry layer's job ,
/// this module cannot reach `identity` without importing upward. Every
/// `public(package)` function below therefore names the account it is acting
/// for, and every call site must already have checked it.
module warlot::project_object;

// === Imports ===

use sui::dynamic_field as dfield;
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
///
/// Shared, not owned. One transaction cannot take two different addresses' owned
/// objects, so an owned holder could only ever enter a transaction its own admin
/// signed ,  which would make every delegate and operator path impossible. This
/// is the bug `entry_upload::foreign_blob_add` records about the `&Registry`
/// argument it had to remove. `admin` is the gate here, not Sui ownership.
public struct ProjectHolder has key, store {
    id: UID,
    /// The address that may create projects here and edit the ones it holds.
    admin: address,
}

/// One project: the inner file acting as its database, and its commitment.
///
/// A plain `store` value in a `dynamic_field`, not an object in a
/// `dynamic_object_field`. A project is never transferred, never shared and
/// never fetched by its own id ,  it is only ever reached through its holder ,
/// so it does not need to be an object. As a field entry it costs one entry
/// rather than an object plus an entry, and one node fetch rather than two.
/// `permission.move` already applies this rule to the operator role; this module
/// simply had not.
public struct Project has store {
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

// === View functions ===

/// The address that owns this holder.
public fun project_admin(project_holder: &ProjectHolder): address {
    project_holder.admin
}

/// Whether this holder holds a project with that id.
public fun has_project(project_holder: &ProjectHolder, project_id: ID): bool {
    dfield::exists_with_type<ID, Project>(&project_holder.id, project_id)
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

/// Build an empty project holder whose admin is `owner`.
///
/// The holder is minted for the account rather than for the sender, so the
/// caller has to have established that the two belong together. It is returned
/// rather than shared here so the caller can record its id against the account
/// before it becomes reachable.
public(package) fun create_project_holder(owner: address, ctx: &mut TxContext): ProjectHolder {
    let project_holder = ProjectHolder {
        id: object::new(ctx),
        admin: owner,
    };

    product_events::emit_project_holder_created(object::id(&project_holder), project_holder.admin);

    project_holder
}

/// Publish the holder, after which anybody may name it as a transaction input
/// and `admin` is what decides who may act on it.
///
/// Shared rather than owned, and not by preference: an owned object can only
/// enter a transaction its owner signed, and one transaction cannot take two
/// different addresses' owned objects. An owned holder could therefore never
/// appear in a delegate's or an operator's transaction at all, which is the whole
/// surface below it. `admin` is the gate, not Sui ownership.
///
/// Both lints on this line say the same thing back: the share is deliberate, and
/// it is `share_object` rather than the public variant because nothing outside
/// this module may publish a holder.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(project_holder: ProjectHolder) {
    transfer::share_object(project_holder);
}

/// Mint a project under `owner`'s holder and return its id.
///
/// The id is the project's identity from here on, and it is announced rather
/// than derivable: a project carries no name, so nothing off chain can compute
/// it. It opens committed to the empty file set.
///
/// With no `UID` of its own the id comes from `ctx.fresh_object_address()`,
/// which the framework documents as a globally unique object id that can never
/// collide with a user address.
public(package) fun create_project(
    project_holder: &mut ProjectHolder,
    owner: address,
    ctx: &mut TxContext,
): ID {
    assert!(project_holder.admin == owner, INVALIDACCESS);

    let project_id = object::id_from_address(ctx.fresh_object_address());
    let project = Project {
        db_inner_file: option::none(),
        file_set_root: file_set::empty_root(),
    };
    let file_set_root = project.file_set_root;

    dfield::add<ID, Project>(&mut project_holder.id, project_id, project);

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
/// value is a well-formed root, that the holder belongs to the account the
/// caller checked, and that every move is announced.
public(package) fun set_file_set_root(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    file_set_root: vector<u8>,
    owner: address,
    ctx: &TxContext,
) {
    assert!(project_holder.admin == owner, INVALIDACCESS);
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

    dfield::borrow<ID, Project>(&project_holder.id, project_id)
}

/// Mutable access to the project `project_id`, or an abort naming the miss.
fun borrow_project_mut(project_holder: &mut ProjectHolder, project_id: ID): &mut Project {
    assert!(has_project(project_holder, project_id), ENoSuchProject);

    dfield::borrow_mut<ID, Project>(&mut project_holder.id, project_id)
}
