module warlot::issue;

use sui::{clock::Clock, dynamic_object_field as ofields};

// holds the file meta of that file 
public struct FileIssueMeta has key, store{
    id: UID,
    unresolved: u64,
    resolved: u64,
    last_modified: u64,
    available_index: u64, 
}

// type to show unresolved file type
public struct Unresolved has key, store { id: UID}

// type to show resolved type 
public struct Resolved has key, store{id: UID}


public struct Issue has key, store{
    id: UID,
    problem: vector<u8>,
    state: vector<u8>,
    created_at_ms: u64,
    writer: address,
}


// ======================dynamic fileds key ====================//
const UNRESOLVEDKEY: vector<u8> = b"Unresolved Key";
const RESOLVEDKEY: vector<u8> = b"Resolved Key";


//=========================error ============================//
#[error]
const INVALIDISSUEINDEX: vector<u8> = b"enter valid index";



public(package) fun create_file_issue_meta(clock: &Clock, ctx: &mut TxContext): FileIssueMeta{
    let mut issue_meta = FileIssueMeta{
        id: object::new(ctx),
        unresolved: 0,
        resolved: 0,
        last_modified: clock.timestamp_ms(),
        available_index: 0,
    };

    // creating the 2 issue types
    ofields::add<vector<u8>, Unresolved>(&mut issue_meta.id, UNRESOLVEDKEY, Unresolved{id: object::new(ctx)});
    ofields::add<vector<u8>, Resolved>(&mut issue_meta.id, RESOLVEDKEY, Resolved{id: object::new(ctx)});
    issue_meta
}



public fun create_issue_Meta(
    issue_meta: &mut FileIssueMeta,
    problem: vector<u8>,
    state: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
     ){
        let issue = Issue{
            id : object::new(ctx),
            problem,
            state,
            created_at_ms: clock.timestamp_ms(),
            writer: ctx.sender(),
        };

        let unresolved = ofields::borrow_mut<vector<u8>, Unresolved>(&mut issue_meta.id, UNRESOLVEDKEY);
        let available_index = issue_meta.available_index;
        ofields::add<u64, Issue>(&mut unresolved.id, available_index, issue);
        issue_meta.available_index = available_index + 1;
  
}


// public(package) fun resolve_issue(
//       issue_meta: &mut FileIssueMeta,
//       issue: u64
// ){

// }

// issue:
// // check if the issue exist 
// public(package) fun confirm_issue(issue_meta: &mut FileIssueMeta, issue: u64){
//     assert!(ofields::exists_(&issue_meta.id, ));
// }

// todo
// create issue by only writers, pin issue to the file object 
// resolve issue, delete issue, update issue and so on