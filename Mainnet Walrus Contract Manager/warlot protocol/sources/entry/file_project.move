/// Creates an inner file and names it as a project's database in one call.
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
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
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
        operators_allowed,
        operators_may_bypass_draft,
        option::some(auth),
        false,
        0,
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);
    user::check_permission_can_init_db(owners_obj, option::some(auth), ctx);

    project_object::init_db(project_holder, project_id, new_inner_file_id, owner);
}
