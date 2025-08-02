module warlot::innerfiledata;
use std::string::String;

// holds the blob address and idnetifer of that file change
public struct FileData has store, drop{
    commit: vector<u8>,
    commit_by: address,  // address that  made  the changes 
    walrus_blob_id: String,
    walrus_blob_object_id: ID
}


// view fields of file data
public fun commit(file_data: &FileData): vector<u8>{
    file_data.commit
}

public fun commit_by(file_data: &FileData): address{
    file_data.commit_by
}

public fun walrus_blob_id(file_data: &FileData): String{
    file_data.walrus_blob_id
}

public fun walrus_blob_object_id(file_data: &FileData): ID{
    file_data.walrus_blob_object_id
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
