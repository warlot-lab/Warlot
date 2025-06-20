// module warlot::issue;

// use sui::{dynamic_field as dfield, clock::Clock, dynamic_object_field as ofields};

// // holds the file meta of that file 
// public struct FileIssueMeta has store{
//     unresolved: u64,
//     resolved: u64,
// }

// // type to show unresolved file type
// public struct Unresolved has drop{};

// // type to show resolved type 
// public struct Resolved has drop{};


// public struct Issue<T> has key{
//     id: UID,

//     problem: vector<u8>,
//     state: vector<u8>,
//     created_at_ms: u64,
//     writer: address,
// }


// public fun create_issue_Meta<T: drop>(_: T, ){

// }

// // check if the issue exist 
// public(package) fun confirm_issue(issue_meta: &mut FileIssueMeta, issue: u64){
//     assert!(ofields::exists_(&issue_meta.id, ));
// }

// // todo
// // create issue by only writers, pin issue to the file object 
// // resolve issue, delete issue, update issue and so on