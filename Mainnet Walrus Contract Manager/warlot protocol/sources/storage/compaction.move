/// Assembles a compaction and writes its receipt onto the config it produced.
///
/// A compaction repacks the live files out of many configs into one, and it is
/// not only a cost optimisation: Walrus deletes, extends and shares a quilt whole
/// and never a patch, so repacking the survivors is the *only* way to remove one
/// file. Compaction is therefore the delete primitive as well as the collector.
///
/// **The chain does not verify a compaction and cannot.** A quilt's patch index
/// lives inside the quilt and its patch ids are derived off chain from the whole
/// quilt's composition, so Move has no way to ask whether a file is inside a
/// blob. What the chain does is narrower and is the part that has to be
/// trustworthy: it refuses a compaction whose named predecessors are not all the
/// same owner's under the same renewal terms, it derives both commitments from
/// state it read rather than from an argument, and it writes the receipt once.
/// The rest is a client procedure, and the receipt is what makes that procedure
/// sound after the data it describes is gone.
///
/// There is no accept step and no pending state. Writing the new quilt destroys
/// nothing, so it needs no consent; deleting the old content is already refused
/// to everyone but its owner, so it needs no flag. An "accepted" boolean would be
/// one more thing Warlot could set on the user's behalf, and the absence of it is
/// what makes deletion the only signal that can be produced.
module warlot::compaction;

// === Imports ===

use warlot::{
    blob_config::{Self, BlobConfig},
    file_set::{Self, FileEntry},
    id_set,
    layout,
    storage_events,
};

// === Errors ===

#[error]
const ENotTheTarget: vector<u8> = b"THIS PLAN WAS OPENED AGAINST A DIFFERENT CONFIG";
#[error]
const ECrossUserQuilt: vector<u8> =
    b"A COMPACTION MAY ONLY SUPERSEDE CONFIGS ITS TARGET'S OWNER ALSO OWNS";
#[error]
const EPolicyNotHomogeneous: vector<u8> =
    b"EVERY CONFIG IN A COMPACTION MUST SHARE ONE STORAGE TERM AND ONE RENEWAL MANDATE";
#[error]
const ESupersedesItself: vector<u8> = b"A COMPACTION CANNOT SUPERSEDE ITS OWN TARGET";
#[error]
const ESupersededNotAscending: vector<u8> =
    b"A COMPACTION'S PREDECESSORS MUST BE NAMED IN ASCENDING ID ORDER, WITH NO REPEAT";
#[error]
const ETooManySuperseded: vector<u8> = b"A COMPACTION MAY SUPERSEDE AT MOST 666 CONFIGS";
#[error]
const EGenerationNotAdvanced: vector<u8> =
    b"A COMPACTION'S GENERATION MUST EXCEED EVERY GENERATION IT SUPERSEDES";
#[error]
const ENothingSuperseded: vector<u8> = b"A COMPACTION MUST SUPERSEDE AT LEAST ONE CONFIG";
#[error]
const EQuiltIsOneBlob: vector<u8> = b"A QUILT IS A SINGLE WALRUS BLOB";
#[error]
const EMismatchedEntries: vector<u8> =
    b"EVERY PATH IN A LAYOUT MUST HAVE EXACTLY ONE CONTENT HASH";
#[error]
const EOwnerMoved: vector<u8> = b"THIS CONFIG CHANGED HANDS WHILE THE COMPACTION WAS BEING BUILT";

// === Structs ===

/// A compaction being assembled, alive for exactly one transaction.
///
/// It has no abilities at all: it cannot be stored, copied or dropped, so the
/// only way a transaction can finish holding one is not to finish. That is what
/// lets a compaction name many predecessors without inventing any state. Move has
/// no vector of references, and the two alternative shapes are both refused here
/// on purpose ,  accumulating predecessors across transactions would be the
/// pending state that has to be forgeable to be useful, and taking the
/// predecessors by value would let a compaction retire content whose owner never
/// released it.
///
/// Every field is settled by `plan` from the target config and then only
/// narrowed. A caller cannot assert the owner or the storage terms; they are read.
public struct CompactionPlan {
    /// The config the finished layout will be written onto.
    target: ID,
    /// The address every config in this compaction must belong to.
    owner: address,
    /// The storage term every config in this compaction must share.
    epoch_set: u32,
    /// The renewal mandate every config in this compaction must share.
    cycle_limit: Option<u64>,
    /// The highest generation named so far. The new layout must exceed it.
    generation_floor: u32,
    /// Every config this compaction replaces.
    superseded: vector<ID>,
}

// === View functions ===

/// The config this plan's layout will be written onto.
public fun plan_target(plan: &CompactionPlan): ID { plan.target }

/// The address every config in this compaction belongs to.
public fun plan_owner(plan: &CompactionPlan): address { plan.owner }

/// How many configs this compaction supersedes so far.
public fun plan_superseded_count(plan: &CompactionPlan): u64 { plan.superseded.length() }

/// The generation this compaction must exceed.
public fun plan_generation_floor(plan: &CompactionPlan): u32 { plan.generation_floor }

// === Package functions ===

/// Open a compaction against `target`, taking its owner and its storage terms as
/// the terms every predecessor must match.
///
/// The target is the config the new quilt was stored under, built by the ordinary
/// upload path, so its owner is already whoever the store was authorised for.
/// Reading the terms off it rather than accepting them as arguments is what makes
/// the homogeneity check mean something: the caller chooses which configs to
/// name, never what counts as matching.
public(package) fun plan(target: &BlobConfig): CompactionPlan {
    CompactionPlan {
        target: blob_config::config_id(target),
        owner: blob_config::owner(target),
        epoch_set: blob_config::epoch_set(target),
        cycle_limit: blob_config::cycle_limit(target),
        generation_floor: blob_config::generation(target),
        superseded: vector<ID>[],
    }
}

/// Name `config` as one of the configs this compaction replaces.
///
/// The two refusals are the whole of what the chain can enforce about a quilt's
/// contents, and they are enforced here because this is the one place a
/// predecessor is in scope as an object rather than as an id.
///
/// A **cross-user** compaction is refused because deletion is whole-quilt: in a
/// quilt holding two users' files, neither can delete without destroying the
/// other's, so "only the user can delete" is not awkward across users, it is
/// impossible. A **mixed-policy** compaction is refused because renewal is
/// whole-quilt too, so one `epoch_set` and one mandate have to serve every file
/// in the quilt permanently.
///
/// Predecessors must be named in ascending id order. That is what keeps the check
/// for a repeat to one comparison instead of a scan of everything named so far,
/// and it is what leaves the root's own sort with nothing to do ,  measured, the
/// difference between a set of 666 that folds and one that does not.
public(package) fun supersede(plan: &mut CompactionPlan, config: &BlobConfig) {
    let config_id = blob_config::config_id(config);

    assert!(config_id != plan.target, ESupersedesItself);
    assert!(plan.superseded.length() < id_set::max_id_set(), ETooManySuperseded);

    if (!plan.superseded.is_empty()) {
        let last = &plan.superseded[plan.superseded.length() - 1];
        assert!(id_set::is_before(last, &config_id), ESupersededNotAscending);
    };

    assert!(blob_config::owner(config) == plan.owner, ECrossUserQuilt);
    assert!(blob_config::epoch_set(config) == plan.epoch_set, EPolicyNotHomogeneous);
    assert!(blob_config::cycle_limit(config) == plan.cycle_limit, EPolicyNotHomogeneous);

    let generation = blob_config::generation(config);
    if (generation > plan.generation_floor) {
        plan.generation_floor = generation;
    };

    plan.superseded.push_back(config_id);
}

/// Write the compaction's receipt onto its target, and announce it.
///
/// Both commitments are computed here from what the contract holds: the file-set
/// root over the entries the call carries, and the superseded root over the ids
/// of configs `supersede` actually read. Neither is an argument, so neither can
/// be asserted, and a layout that does not match what was submitted cannot be
/// registered.
///
/// The generation must exceed every generation superseded. That is what makes the
/// lineage a strict order rather than a set of claims, and it is what stops a
/// compaction from being re-registered against older content later.
///
/// Nothing here deletes, retires or re-parents anything. The superseded configs
/// are untouched and stay renewable; their owner disposes of them when, and only
/// when, they are satisfied.
public(package) fun register(
    system_id: ID,
    target: &mut BlobConfig,
    plan: CompactionPlan,
    kind: u8,
    generation: u32,
    paths: vector<vector<u8>>,
    content_hashes: vector<vector<u8>>,
    created_at_ms: u64,
    registered_by: address,
) {
    let CompactionPlan {
        target: target_id,
        owner,
        epoch_set: _,
        cycle_limit: _,
        generation_floor,
        superseded,
    } = plan;

    assert!(blob_config::config_id(target) == target_id, ENotTheTarget);
    // A plan and its target are separate transaction inputs, so a call sequence
    // could re-parent the config between opening the plan and closing it.
    assert!(blob_config::owner(target) == owner, EOwnerMoved);
    assert!(!superseded.is_empty(), ENothingSuperseded);
    assert!(generation > generation_floor, EGenerationNotAdvanced);
    assert!(paths.length() == content_hashes.length(), EMismatchedEntries);
    // The order the caller submits is the order the root is folded in, so the
    // list the event carries is the canonical one and a consumer recomputing the
    // commitment has nothing left to infer.
    file_set::assert_ascending_paths(&paths);

    // A quilt is one Walrus blob however many patches it carries, so the kind is
    // checked against the custody rather than believed.
    assert!(
        kind != layout::kind_quilt() || blob_config::blob_count(target) == 1,
        EQuiltIsOneBlob,
    );

    let file_count = paths.length();
    let superseded_count = superseded.length();

    let mut entries = vector<FileEntry>[];
    let mut i = 0;
    // Bounded by `file_set::root`'s own cap, which refuses a longer set below.
    while (i < file_count) {
        entries.push_back(file_set::new_entry(paths[i], content_hashes[i]));
        i = i + 1;
    };

    let file_set_root = file_set::root(entries);
    let superseded_root = id_set::root(superseded);

    let record = layout::new(
        kind,
        generation,
        file_count,
        file_set_root,
        superseded_root,
        superseded_count,
        created_at_ms,
    );

    blob_config::set_layout(target, record);

    // The object keeps the two roots; the stream keeps the members they commit
    // to. That division is what makes the receipt constant-size on chain and
    // still enumerable afterwards ,  and the enumeration has to survive the
    // deletion of the quilt it describes, which is the whole reason it is an
    // event rather than a field.
    storage_events::emit_layout_registered(
        system_id,
        target_id,
        owner,
        registered_by,
        kind,
        generation,
        file_count,
        file_set_root,
        paths,
        content_hashes,
        superseded_root,
        superseded_count,
        superseded,
        created_at_ms,
    );
}
