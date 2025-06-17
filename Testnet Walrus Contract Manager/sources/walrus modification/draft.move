module warlot::draft;
use warlot::innerfiledata::{Self, FileData};
use std::string::String;
use sui::{dynamic_field as dfield, clock::Clock, dynamic_object_field as ofields};



// unlike the main file meta where the walrus blob is managed by the admin or owner of the file 
// here the draft walrus blobs are managed by the writer who pushed it 
//  since the draft is true purpose is just as a branc of the file, and the draft is just for the owner of the file to apporove changes made by a third party
// a draft_epoch_duration is created. this is to make sure that the draft file does not exceed a short duration of the net<main, test, dev> state

public struct FileDraftHolder has key, store{
    id: UID,
    draft_epoch_duration: u32,
    last_modified: u64,
    total_draft: u64,
    available_index: u64, //this is the index of the draft so that writers and contributors can build on the trail of edition and modification of the unapproved draft

    // draft
}

public struct Draft has key, store{
    id: UID,
    writer_pass: ID, // the id os the pass the user used to make this draft
    issue: Option<ID>, //tag the issue it is resolving if any
    file: Option<FileData>
}


// ======    error      =======//
#[error]
const INVALIDDRAFT: vector<u8> = b"enter a vaild draft";
 
public fun writer_pass(draft: &Draft): ID{draft.writer_pass}
public fun issue(draft: &Draft): &Option<ID>{&draft.issue}
public fun file(draft: &Draft): &Option<FileData>{&draft.file}



public(package) fun create_draft_holder(
    draft_epoch_duration: u32,
    ctx: &mut TxContext
): FileDraftHolder{
    FileDraftHolder{
        id : object::new(ctx),
        draft_epoch_duration,
        last_modified: 0,
        total_draft: 0,
        available_index: 0,
     
    }
}

public(package) fun create_draft(
    writer_pass: ID, 
    issue: Option<ID>, 
    file: Option<FileData>,
    ctx: &mut TxContext
): Draft{
    Draft{
        id: object::new(ctx),
        writer_pass,
        issue,
        file,
    }

}


public(package) fun pin_draft(
    draft_holder: &mut FileDraftHolder,
    draft: Draft,
    clock: &Clock
     ){
        let old_total_draft = draft_holder.total_draft;
        let available_index_point = draft_holder.available_index;
        ofields::add<u64, Draft>(&mut draft_holder.id, available_index_point, draft);

        draft_holder.last_modified = clock.timestamp_ms();
        draft_holder.available_index = available_index_point + 1;
        draft_holder.total_draft = old_total_draft + 1;
}


public(package) fun get_draft(
    draft_holder: &mut FileDraftHolder,
    draft: u64
): &mut Draft{
    assert!(ofields::exists_(&draft_holder.id, draft), INVALIDDRAFT);
    ofields::borrow_mut<u64, Draft>(&mut draft_holder.id, draft)
}


// this will be used to merge the properties of 2 draft;
// the issues will be combined 
// the commit will be merged, and a superior walrus file will be used to replace of the draft while the other is deleted 
// public(package) fun merge_draft(
//     draft_holder: &mut FileDraftHolder,
// ){

// }



public(package) fun delete_draft(
    draft_holder: &mut FileDraftHolder,
    draft: u64
){
    assert!(ofields::exists_(&draft_holder.id, draft), INVALIDDRAFT);
    let draft_obj = ofields::remove<u64, Draft>(&mut draft_holder.id, draft);
    let Draft{id, writer_pass: _, issue: _, file: _} = draft_obj;
    id.delete();
    let old_total_draft = draft_holder.total_draft;
    draft_holder.total_draft = old_total_draft - 1; 
}

// public(package) fun clear_all_draft(){
//     // this will delete all the draft concering a particular file

// }




