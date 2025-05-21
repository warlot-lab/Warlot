module warlot::config;
use walrus::{blob::Blob, system::System};
use warlot::constants::Self;


// public struct Table has copy, drop, store {}
// public struct File has copy, drop, store {}
// public struct Foreign has copy, drop, store {}

public struct BlobSettings has store{
    blob: Blob,
    epoch_set: u32, //this is the numbers of epoch that the blob will be renewed by
    cycle_at: u64, // this is the current cycle the blob is at
    cycle_end: u64,
    //  _marker:    K, 

}





public(package) fun new_config_blob(blob: Blob, epoch_set: u32, cycle_end: u64): BlobSettings{
    BlobSettings { blob, epoch_set, cycle_at: 0, cycle_end }
}


public(package) fun blob(blob_cfg: &mut BlobSettings): &mut Blob{
    &mut blob_cfg.blob
}


public(package) fun epoch_set(blob_cfg: &BlobSettings): u32{
    blob_cfg.epoch_set
}

public(package) fun cycle_at(blob_cfg: &BlobSettings): u64{
    blob_cfg.cycle_at
}

public(package) fun cycle_end(blob_cfg: &BlobSettings): u64{
    blob_cfg.cycle_end
}

public(package) fun reduce_cycle(blob_cfg: &mut BlobSettings): u64{
    blob_cfg.cycle_at = blob_cfg.cycle_at + 1;
    blob_cfg.cycle_at
}

public(package) fun get_blob_obj_id(blob_cfg: &BlobSettings):ID{
    blob_cfg.blob.object_id()
}

public(package) fun is_deletable(blob_cfg: &BlobSettings): bool{
    blob_cfg.blob.is_deletable()
}

public(package) fun blob_size(blob_cfg: &BlobSettings): u64{
    blob_cfg.blob.size()
}

public(package) fun blob_current(blob_cfg: &BlobSettings): u32{
    blob_cfg.blob.storage().end_epoch()
}

// this function is used to calculate the number of epoch a blob needs to sync with 
// the needed epoch set
// where ahead is the epoch sync epoch count
public(package) fun get_renew_epoch_count(blob_cfg: &BlobSettings, system: &System, ahead: u32): u32{
    let current_epoch = system.epoch();
    let blob_end_epoch = blob_cfg.blob_current();
    let new_end_epoch = current_epoch + ahead;
    new_end_epoch - blob_end_epoch
    // 33
    // 44
    // 53

}

public fun sync_epoch_count(blob_cfg: &BlobSettings, epoch_checkpoint: u32): u32 {

  

    let blob_end_epoch = blob_cfg.blob_current();

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

public(package) fun withdraw_and_burn(blob_cfg: BlobSettings): Blob{
   let BlobSettings { blob, epoch_set: _, cycle_at: _, cycle_end: _ } = blob_cfg;
    blob
}

// todo
// burn blob
// withdraw blob
// transfer blob
// share blob