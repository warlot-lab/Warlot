module warlot::innerfile;
use std::string::String;
use warlot::{
    innerfiledata::{Self, FileData},
    draft::{Self, FileDraftHolder}
    };
use sui::{dynamic_field as dfield, clock::Clock, dynamic_object_field as ofields};


public struct InnerFile has key, store{
    id: UID,
    owner: address,  //address of the owner of the data or admin of the data
    writers_length: u8, // total amount of draft a writer can add to the draft obj at a time 
    file_history: FileTrack,
    created_at_ms: u64,
}


public struct FileTrack has store{
    // root change is a file meta that the owner of the file can choose to fall back to if significant changes have been made to the fileTrack
    // like a remote server making multiple chages to the file, and the user do not approve of this changes. 
    // this will give the user a safe state of the file to fall back to
    // this gives the power of collaboration while still keeping the integrity of the file state 
    root_change: Option<FileData>, 
    track_back_length: u8, //this is the max cache of file change of this file can exist on chain; it is needed so that users that want to revert changes can find it possible 
    track_back: vector<FileData>, // holds file history
    last_modified : u64,
}





// this holds the dynamic list of all the address that have been denied access to modify this file
// so that if they have a writters pass, and they try to modify the file the writers pass will be destroyed 
public struct DenyList  has key, store{
    id: UID,
    numbers_of_deny: u64,
}



public struct WriterPass has key{
    id: UID,
    file_id: ID,
    duration: u64, //decay period of the pass
    // current_write: u64, //total number of draft added 
    admin_privilege: Option<AdminPass>
}

// this pass is given to users for them to bypass the draft and push direct chages to the file trackback 
// example useage will be a user that want to give a remote server the ability to modify large files that the user local system can not handle
//  since the user can not load the draft on their local system. it makes more sense for the user to give their trusted service the permission to make this modification
//  example this pass can be given to warlot, to modify table files, and sql based files. thereby reducing the load on the user local machine; expecialy if you want to build a service ontop of walrus 

public struct AdminPass has store, drop{
    admin: address
}





// ========= File attribute keys =========//
const DENYLISTKEY: vector<u8> = b"deny list";
const FILEDRAFTKEY: vector<u8> = b"file draft";
const FileDataKEY: vector<u8> = b"file meta";


// ======== writer attributes ======= //
const ImmortalPASS: u64 = 0; // a pass with the duration as {0} will be taken as a pass that cannot decay by the system.

//  ======== error =============//
#[error]
const INVALIDWRITER: vector<u8> = b"permission denied";
#[error]
const INVALIDTIME: vector<u8> = b"enter valid time";
#[error]
const DECAYEXCEEDED: vector<u8> = b"destroy current pass, and create new pass";
#[error]
const INVALIDPASS: vector<u8> = b"enter valid pass";
#[error]
const ACCESSDENIED: vector<u8> =  b"invalid writer pass";
#[error]
const INVALIDTRACKBACKLENGTH: vector<u8> = b"provide a valid track back len data";

// file track data
public fun root_change(inner_file: &InnerFile): &FileData{
    inner_file.file_history.root_change.borrow()
}

public fun track_back_length(inner_file: &InnerFile): u8{
    inner_file.file_history.track_back_length
}

public fun track_back(inner_file: &InnerFile): &vector<FileData>{
    &inner_file.file_history.track_back
}




// using 
public fun create_file(
    owner: address, 
    writers_length: u8,
    track_back_length: u8,
    walrus_blob_id: String,
    walrus_blob_object_id: address,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    ctx: &mut TxContext){
    // make sure that the trackbcak_length is > 0
    assert!(track_back_length > 0 , INVALIDTRACKBACKLENGTH);

    let mut new_file  = InnerFile{
        id : object::new(ctx),
        
        owner,
        writers_length,
        file_history: FileTrack{

            root_change : option::none(),
            track_back_length,
            track_back: vector::singleton(

                innerfiledata::create_file_data(
                    commit,
                    ctx.sender(),
                    walrus_blob_id,
                    object::id_from_address(walrus_blob_object_id),
                )

            ),
            last_modified: clock.timestamp_ms(),
        },
        created_at_ms: clock.timestamp_ms(),
    };

    let default_deny_list = DenyList{
        id: object::new(ctx),
        numbers_of_deny: 0
    };

    // give the author or owner of the file an immortal pass
    let immortal_pass = WriterPass{
        id: object::new(ctx),
        file_id: object::id(&new_file),
        duration: ImmortalPASS,
        admin_privilege: option::some(
            AdminPass{
                admin: owner
            }
        )
    };



    ofields::add<vector<u8>, DenyList>(&mut new_file.id, DENYLISTKEY, default_deny_list);
    // add draftholder object to the file 
    ofields::add<vector<u8>, FileDraftHolder>(&mut new_file.id, FILEDRAFTKEY, draft::create_draft_holder(draft_epoch_duration, ctx));

    // todo to be updated to party share, to allow more secure group modification of the file
    transfer::public_share_object(new_file);
    transfer::transfer(immortal_pass, owner);
}




public fun deny_writer(file: &mut InnerFile, writer: address, period: u64, clock: &Clock,  ctx: &mut TxContext){
    assert!(file.owner == ctx.sender(), 1);
    let deny_obj = ofields::borrow_mut<vector<u8>, DenyList>(&mut file.id, DENYLISTKEY);
    // the deny list can be used to restrict a user from the file for just a duration
    //  in this case if the value  ==  0; then the deny is indefinate 
    // any > 0 is a period
    // <user, period>
    assert!(period == 0 || period > clock.timestamp_ms(), INVALIDTIME);
    if (dfield::exists_(&deny_obj.id, writer)){
        // if deny exist, modify period
        *dfield::borrow_mut<address, u64>(&mut deny_obj.id, writer) = period;
    
    }else{
         dfield::add<address, u64>(&mut deny_obj.id, writer, period);
    };

    let old_d_o = deny_obj.numbers_of_deny;
    deny_obj.numbers_of_deny = 1 + old_d_o;
}


public fun remove_deny_writer(file: &mut InnerFile, writer: address, ctx: &mut TxContext){
    assert!(file.owner == ctx.sender(), 1);
    let deny_obj = ofields::borrow_mut<vector<u8>, DenyList>(&mut file.id, DENYLISTKEY);
    let _ = dfield::remove<address, u64>(&mut deny_obj.id, writer);
}

// this function allows the use to write directly to the inner file object
//warning: using this fuction will make unreversable changes to the inner file object
fun write(
    file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    system_to_draft: bool, //force file to draft
    walrus_blob_id: String,
    walrus_blob_object_id: address,
    clock: &Clock,
    issue: Option<ID>,
    file_data: Option<FileData>,
    commit: vector<u8>,
){


}

// allows users to write to the draft object awaiting approval from the admin
public fun write_(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    to_draft: bool, // this allows for flexibility. when modifing the file the user even if they have the admin pass can still choose to push to the draft branch of the application
    issue: address,
    // fileData info
    commit: vector<u8>,
    walrus_blob_id: String,
    walrus_blob_object_id: ID,
    clock: &Clock,
    ctx: &mut TxContext
){
    verify_pass(inner_file, ctx.sender(), writer_pass, clock);

    //  build the fileData object
    let file_data: FileData = innerfiledata::create_file_data(commit, ctx.sender(), walrus_blob_id, walrus_blob_object_id);

    // create issue option
    let issue_state =  {
        if (issue == @0x0){
            option::none()
        }else{
            option::some(object::id_from_address(issue))
        }
    };

    // generate the issue
    if (!to_draft){
        // confirm if the user have the permission to make this changes
        assert!(option::is_some(&writer_pass.admin_privilege), ACCESSDENIED);
        // make the chages and return
        override_file_add(inner_file, file_data, clock);
        return
    };

    // todo check if the issue is @0x0 if not check if the issue exist 
    // create the draft obj
    let file_draft = draft::create_draft(
        object::id(writer_pass), 
        issue_state,
        option::some(file_data),
        ctx );

    draft::pin_draft(
        get_draft_holder(inner_file), //draft holder of this file
        file_draft,
        clock,
        );
    
}



// create pass with either admin functionality or without
public fun create_pass(file: &InnerFile, writer: address, duration: u64,admin_pass: bool, ctx: &mut TxContext){
    assert!(file.owner == ctx.sender(), 1);
    let admin_pass: Option<AdminPass> = {
        if (admin_pass){
            option::some(
                AdminPass{
                    admin: file.owner
                }
            )
        }else {
            option::none()
        }
    };

    let writer_pass = WriterPass{
        id: object::new(ctx), 
        file_id: object::id(file),
        duration,
        admin_privilege: admin_pass,
    };

    transfer::transfer(writer_pass, writer);
}

public fun destroy_writer_pass(pass :WriterPass){
    let WriterPass {id, file_id: _, duration: _,  admin_privilege: _} = pass;
    id.delete();
}



//  If the writer is not denied, or has an ImmortalPASS, allow access.
// ensure their pass is not expired
// ensure they are not still in the deny period or permanently denied.
public fun verify_pass(file: &InnerFile, writer: address, writer_pass: &WriterPass, clock: &Clock){
    // check if the pass is for this file
    assert!(object::id(file) == writer_pass.file_id, INVALIDPASS);

    //  check if the user is in the deny list 
    let deny_obj = ofields::borrow<vector<u8>, DenyList>(&file.id, DENYLISTKEY);
    if (!dfield::exists_(&deny_obj.id, writer) ||  writer_pass.duration == ImmortalPASS ){
        return
    };


    let current_time = clock.timestamp_ms();

    // check if the writer pass has decayed
    assert!(
       writer_pass.duration > current_time,
        DECAYEXCEEDED 
    );

    let user_deny_period = *dfield::borrow(&deny_obj.id, writer);
    // check if the user is banned indefinately 
    assert!(
        !(user_deny_period == 0 || user_deny_period > current_time),
        INVALIDWRITER
    );
}


//======= helper functions ======//


fun get_draft_holder(inner_file: &mut InnerFile): &mut FileDraftHolder{
    ofields::borrow_mut<vector<u8>, FileDraftHolder>(&mut inner_file.id, FILEDRAFTKEY)
}

fun get_file_track(inner_file: &mut InnerFile): &mut FileTrack{
    &mut inner_file.file_history
}

// modifies and add new files to the file track
fun override_file_add(
    inner_file: &mut InnerFile,
    file_data: FileData,
    clock: &Clock
){
    // checking if the track_back length is less than the max track back length 

    let max_length = inner_file.file_history.track_back_length as u64;
    let current_length = vector::length(&inner_file.file_history.track_back);

    if ( max_length <= current_length){
        // pop the oldest file in the history and place the new one
        let _ = inner_file.file_history.track_back.pop_back();  
    };

    // inserts the file at the beging of the list
    // making the order of file to be latest at index [0]
    inner_file.file_history.track_back.insert(file_data, 0);
    inner_file.file_history.last_modified = clock.timestamp_ms();

}

// todo replace main file with draft and delete draft option
// deleting draft is not reversable
// fun override_file_add_via_draft(
//     inner_file: &mut InnerFile,

// ){

// }
// todo delete file track
