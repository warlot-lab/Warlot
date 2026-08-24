/// Tracks the issues raised and resolved against one inner file.
module warlot::issue;

// === Imports ===

use sui::{clock::Clock, dynamic_object_field as ofields};

// === Errors ===

#[error]
const INVALIDISSUEINDEX: vector<u8> = b"enter valid index";

// === Constants ===

/// Dynamic object field key for the unresolved issue collection.
const UNRESOLVEDKEY: vector<u8> = b"Unresolved Key";
/// Dynamic object field key for the resolved issue collection.
const RESOLVEDKEY: vector<u8> = b"Resolved Key";

// === Structs ===

/// The issue counters for one file.
public struct FileIssueMeta has key, store {
    id: UID,
    unresolved: u64,
    resolved: u64,
    last_modified: u64,
    available_index: u64,
}

/// Container for the issues still open.
public struct Unresolved has key, store { id: UID }

/// Container for the issues closed.
public struct Resolved has key, store { id: UID }

/// One raised issue.
public struct Issue has key, store {
    id: UID,
    problem: vector<u8>,
    state: vector<u8>,
    created_at_ms: u64,
    resolved_meta: Option<IssueResolvedMeta>,
    writer: address,
}

/// When and by whom an issue was closed.
public struct IssueResolvedMeta has store, drop {
    resolved_at: u64,
    resolved_by: address,
}

// === Public functions ===

/// Raise an issue against the file.
public fun create_issue_Meta(
    issue_meta: &mut FileIssueMeta,
    problem: vector<u8>,
    state: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let issue = Issue {
        id: object::new(ctx),
        problem,
        state,
        created_at_ms: clock.timestamp_ms(),
        resolved_meta: option::none(),
        writer: ctx.sender(),
    };

    let unresolved = ofields::borrow_mut<vector<u8>, Unresolved>(&mut issue_meta.id, UNRESOLVEDKEY);
    let available_index = issue_meta.available_index;
    ofields::add<u64, Issue>(&mut unresolved.id, available_index, issue);
    issue_meta.available_index = available_index + 1;
}

// === Package functions ===

/// Build the issue counters and both issue collections for a new file.
public(package) fun create_file_issue_meta(clock: &Clock, ctx: &mut TxContext): FileIssueMeta {
    let mut issue_meta = FileIssueMeta {
        id: object::new(ctx),
        unresolved: 0,
        resolved: 0,
        last_modified: clock.timestamp_ms(),
        available_index: 0,
    };

    ofields::add<vector<u8>, Unresolved>(
        &mut issue_meta.id,
        UNRESOLVEDKEY,
        Unresolved { id: object::new(ctx) },
    );
    ofields::add<vector<u8>, Resolved>(
        &mut issue_meta.id,
        RESOLVEDKEY,
        Resolved { id: object::new(ctx) },
    );
    issue_meta
}

/// Move one issue from the unresolved collection to the resolved one.
public(package) fun resolve_issue(
    issue_meta: &mut FileIssueMeta,
    state: vector<u8>,
    clock: &Clock,
    resolved_by: address,
    issue_index: u64,
) {
    confirm_issue(issue_meta, issue_index);
    let unresolved = ofields::borrow_mut<vector<u8>, Unresolved>(&mut issue_meta.id, UNRESOLVEDKEY);
    let mut resolved_issue = ofields::remove<u64, Issue>(&mut unresolved.id, issue_index);
    resolved_issue.state = state;
    option::fill(
        &mut resolved_issue.resolved_meta,
        IssueResolvedMeta {
            resolved_at: clock.timestamp_ms(),
            resolved_by,
        },
    );

    let resolved = ofields::borrow_mut<vector<u8>, Resolved>(&mut issue_meta.id, RESOLVEDKEY);
    ofields::add<u64, Issue>(&mut resolved.id, issue_index, resolved_issue);
}

/// The id of the unresolved issue at `issue`, or an abort if there is none.
public(package) fun confirm_issue(issue_meta: &FileIssueMeta, issue: u64): Option<ID> {
    let unresolved = ofields::borrow<vector<u8>, Unresolved>(&issue_meta.id, UNRESOLVEDKEY);
    assert!(ofields::exists_(&unresolved.id, issue), INVALIDISSUEINDEX);
    let issue = ofields::borrow<u64, Issue>(&unresolved.id, issue);
    let issue_id = object::id(issue);
    option::some(issue_id)
}
