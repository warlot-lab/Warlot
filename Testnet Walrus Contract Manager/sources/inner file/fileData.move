module warlot::innerfiledata;


// holds the blob address and idnetifer of that file change
public struct FileData has store, drop{
    commit: vector<u8>,
    commit_by: address,  // address that  made  the changes 

    /*
    todo remove walrus_blob_object_id and blob_id and replace it with warlot blobconfig, as it will hold the config details like 
    if the file is larger than 13gb then this will account for that and reconstruct it based on that config and also tag<note this is not a clue of the encryption but a tag to help identify the encryption model for this file> the state of the encryption model
    */
    walrus_blob_id: u256,
    walrus_blob_object_id: ID
}


// view fields of file data
public fun commit(file_data: &FileData): vector<u8>{
    file_data.commit
}

public fun commit_by(file_data: &FileData): address{
    file_data.commit_by
}

public fun walrus_blob_id(file_data: &FileData): u256{
    file_data.walrus_blob_id
}

public fun walrus_blob_object_id(file_data: &FileData): ID{
    file_data.walrus_blob_object_id
}


public(package) fun create_file_data(
  
    commit: vector<u8>,
    commit_by: address,  
    walrus_blob_id: u256,
    walrus_blob_object_id: ID,
): FileData{
  
    let file = FileData{
        commit,
        commit_by,
        walrus_blob_id,
        walrus_blob_object_id,
    };


    file
}
