module warlot::issue;

use sui::{dynamic_field as dfield, clock::Clock, dynamic_object_field as ofields};

// holds the file meta of that file 
public struct FileIssueMeta has store{
    unresolved: u64,
    resolved: u64,
}

public struct Issue has key{
    id: UID,
    problem: vector<u8>,
    state: vector<u8>,
    created_at_ms: u64,
    writer: address,
}


// todo
// create issue by only writers, pin issue to the file object 
// resolve issue, delete issue, update issue and so on