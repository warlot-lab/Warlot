module warlot::innerfiledata;
use std::string::String;

// holds the blob address and idnetifer of that file change
public struct FileData has store, drop{
    commit: vector<u8>,
    commit_by: address,  // address that  made  the changes 
    walrus_blob_id: String,
    walrus_blob_object_id: ID
}



public(package) fun create_file_data(
    commit: vector<u8>,
    commit_by: address,  
    walrus_blob_id: String,
    walrus_blob_object_id: ID
): FileData{
    FileData{
        commit,
        commit_by,
        walrus_blob_id,
        walrus_blob_object_id
    }
}
