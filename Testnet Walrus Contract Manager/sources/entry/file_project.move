/// The project surface: opening a holder, minting a project, moving its file-set
/// root, and creating an inner file that a project names as its database.
///
/// Every permission check in this package lives at this layer, because
/// `project_object` cannot import `identity` without reaching upward through the
/// dependency ladder. So each call below resolves the account the holder belongs
/// to, tests the sender's grant against it, and only then hands the same address
/// down to the mutator, which re-asserts that the holder is that account's.
module warlot::entry_file_project;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{
    admin_cap::AdminCap,
    creation,
    project_object::{Self, ProjectHolder},
    system_config::SystemConfig,
    user,
};

// === Public functions ===

/// Open the sender's project holder and publish it.
///
/// On first use rather than at registration, which is what every other optional
/// container in this package does: an account that only stores blobs never needs
/// one, and the delegation table, deny list, draft queue and wallet bank are all
/// built by the first call that puts something in them.
///
/// The sender's own act, and only theirs. The holder is the authority root for
/// this account's whole project surface, and its `admin` is fixed at creation
/// with no setter, so opening it is the one thing here that cannot be delegated.
/// A second one is refused by name.
public fun open_project_holder(system_cfg: &mut SystemConfig, ctx: &mut TxContext) {
    system_cfg.assert_version();

    let owner = ctx.sender();
    let project_holder = project_object::create_project_holder(owner, ctx);
    let holder_id = object::id(&project_holder);

    user::record_project_holder(user::get_user_mut(system_cfg, owner), holder_id);

    project_object::share(project_holder);
}

/// Open `owner`'s project holder on the strength of an operator credential.
///
/// The sibling the owner-only form did without, so a backend can bootstrap an
/// account's project surface with no user-signed transaction behind it. Gated on
/// `can_init_db`, checked against `owner`'s account rather than the sender's:
/// creating the authority root and creating the projects under it are the same
/// grant, and an operator that may do the second has no reason to be stopped at
/// the first.
///
/// The holder's `admin` is `owner` and never `ctx.sender()`. The credential
/// decides that a holder is created, not who it belongs to ,  `admin` is fixed at
/// creation with no setter, so a holder rooted on a rotating wallet would be an
/// account's whole project surface tied to a key the pool retires. A second
/// holder is refused by the same marker on `User` that refuses one to the owner.
public fun open_project_holder_as_operator(
    system_cfg: &mut SystemConfig,
    admin_cap: &AdminCap,
    owner: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());
    user::check_permission_can_init_db(
        user::get_user(system_cfg, owner),
        option::some(auth),
        ctx,
    );

    let project_holder = project_object::create_project_holder(owner, ctx);
    let holder_id = object::id(&project_holder);

    user::record_project_holder(user::get_user_mut(system_cfg, owner), holder_id);

    project_object::share(project_holder);
}

/// Mint a project under `project_holder` and return its id.
///
/// Gated on `can_init_db`, the same bit as database initialisation: creating a
/// project and naming its database are one act from the account's side, and the
/// two calls stay separate only because initialisation stores a blob and a
/// project may never want one.
public fun create_project(
    project_holder: &mut ProjectHolder,
    system_cfg: &SystemConfig,
    ctx: &mut TxContext,
): ID {
    system_cfg.assert_version();

    let owner = project_object::project_admin(project_holder);
    user::check_permission_can_init_db(user::get_user(system_cfg, owner), option::none(), ctx);

    project_object::create_project(project_holder, owner, ctx)
}

/// The same mint, made on the strength of an operator credential.
public fun create_project_as_operator(
    project_holder: &mut ProjectHolder,
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());
    let owner = project_object::project_admin(project_holder);
    user::check_permission_can_init_db(
        user::get_user(system_cfg, owner),
        option::some(auth),
        ctx,
    );

    project_object::create_project(project_holder, owner, ctx)
}

/// Move a project's commitment to the paths it resolves.
///
/// Gated on `can_set_root` rather than on `can_init_db`. Initialising a database
/// and writing a quilt are additive and destroy nothing; moving a root replaces
/// the previous commitment in place. Withdrawing this bit alone freezes what the
/// account's projects claim while leaving storing, file creation, database
/// initialisation and compaction running.
public fun set_file_set_root(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    file_set_root: vector<u8>,
    system_cfg: &SystemConfig,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let owner = project_object::project_admin(project_holder);
    user::check_permission_can_set_root(user::get_user(system_cfg, owner), option::none(), ctx);

    project_object::set_file_set_root(project_holder, project_id, file_set_root, owner, ctx);
}

/// The same move, made on the strength of an operator credential.
public fun set_file_set_root_as_operator(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    file_set_root: vector<u8>,
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());
    let owner = project_object::project_admin(project_holder);
    user::check_permission_can_set_root(
        user::get_user(system_cfg, owner),
        option::some(auth),
        ctx,
    );

    project_object::set_file_set_root(project_holder, project_id, file_set_root, owner, ctx);
}

/// Create a file and name it as `project_id`'s database.
public fun initialize_project_file(
    project_holder: &mut ProjectHolder,
    project_id: ID,
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
    operators_may_draft: bool,
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let new_inner_file_id = creation::new_file(
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
    );

    let owners_obj = user::get_user(system_cfg, owner);
    user::check_permission_can_init_db(owners_obj, option::none(), ctx);

    project_object::init_db(project_holder, project_id, new_inner_file_id, owner);
}

/// The same initialisation, made on the strength of an operator credential.
///
/// Like `create_file_as_operator`, it names no operator policy: `can_init_db` is a
/// grant to build the account's database, and a database the operator cannot write
/// is not one. The file is born admitting its creator on both routes and the owner
/// narrows it with `entry_file_access::set_operator_policy`.
public fun initialize_project_file_as_operator(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());

    let new_inner_file_id = creation::new_file(
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
    );

    let owners_obj = user::get_user(system_cfg, owner);
    user::check_permission_can_init_db(owners_obj, option::some(auth), ctx);

    project_object::init_db(project_holder, project_id, new_inner_file_id, owner);
}
