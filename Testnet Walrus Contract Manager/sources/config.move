module warlot::config;
use walrus::{blob::Blob, system::System};
use warlot::constants::Self;

// in the application each blob ctored with us is wraped in a blobsetting config; telling the renew system the 
// the renew system uses this to as a guide on how to renew the blob
public struct BlobSettings has store{
    blob: Blob,
    epoch_set: u32, //this is the numbers of epoch that the blob will be renewed by
    cycle_at: u64, // this is the current cycle the blob is at
    cycle_end: u64,
    //  _marker:    K, 

}




// internal config creation
public(package) fun new_config_blob(blob: Blob, epoch_set: u32, cycle_end: u64): BlobSettings{
    BlobSettings { blob, epoch_set, cycle_at: 0, cycle_end }
}

// get a mutable reference to the internal blob
public(package) fun blob(blob_cfg: &mut BlobSettings): &mut Blob{
    &mut blob_cfg.blob
}

// get the epoch set of the blob<the max amount of epoch that the blob should renewed by>
public(package) fun epoch_set(blob_cfg: &BlobSettings): u32{
    blob_cfg.epoch_set
}

// get the cycle that the blob has completed
public(package) fun cycle_at(blob_cfg: &BlobSettings): u64{
    blob_cfg.cycle_at
}

// get the amount of times the blobs should be renewed on the system
public(package) fun cycle_end(blob_cfg: &BlobSettings): u64{
    blob_cfg.cycle_end
}

//internal cycle reduction  
public(package) fun reduce_cycle(blob_cfg: &mut BlobSettings): u64{
    blob_cfg.cycle_at = blob_cfg.cycle_at + 1;
    blob_cfg.cycle_at
}

// get Id of the blob object
public(package) fun get_blob_obj_id(blob_cfg: &BlobSettings):ID{
    blob_cfg.blob.object_id()
}

// checek if the internal blob is deletable
public(package) fun is_deletable(blob_cfg: &BlobSettings): bool{
    blob_cfg.blob.is_deletable()
}

// get the size of the internal blob
public(package) fun blob_size(blob_cfg: &BlobSettings): u64{
    blob_cfg.blob.size()
}

// get the period the blob will expire
public(package) fun blob_current(blob_cfg: &BlobSettings): u32{
    blob_cfg.blob.storage().end_epoch()
}

// this function is used to calculate the number of epoch a blob needs to sync with 
// the needed epoch set
// where ahead is the epoch sync epoch count
public(package) fun get_renew_epoch_count(blob_cfg: &BlobSettings, system: &System, ahead: u32): u32{
    let current_epoch = system.epoch();
    let blob_end_epoch = blob_cfg.blob_current();
    // to make sure that the expired blobs do not panic the transaction 
    if (blob_end_epoch > current_epoch){
        return 0
    };
    let new_end_epoch = current_epoch + ahead;
    new_end_epoch - blob_end_epoch
    // 33
    // 44
    // 53

}


// get the amount or relative amount the is reqired for the blob to be synced with a walrus ahead epoch
public fun sync_epoch_count(blob_cfg: &BlobSettings, epoch_checkpoint: u32, system: &System): u32 {

    let current_epoch = system.epoch();

    let blob_end_epoch = blob_cfg.blob_current();

     if (blob_end_epoch > current_epoch){
        return 0
    };

    if (blob_end_epoch >= epoch_checkpoint) {
        return 2
    };


    let gap = epoch_checkpoint - blob_end_epoch;


    if (gap > constants::max_sync_epochs()) {
        return constants::max_sync_epochs()
    } else {
        return gap
    }
}

// safe return the internal blob and delete the blob config object
public(package) fun withdraw_and_burn(blob_cfg: BlobSettings): Blob{
   let BlobSettings { blob, epoch_set: _, cycle_at: _, cycle_end: _ } = blob_cfg;
    blob
}

// todo
// burn blob
// withdraw blob
// transfer blob
// share blob