module warlot::config;
use walrus::{blob::Blob, system::System};
use warlot::constants::Self;
/*
todo move optional meta to this part of the smart contract
1]thereby removing the file object from the warlot attribute. making indexing of the epoch a lot more efficent 
2] set up the warlot dev to be able to put files under users address but only the dev will pay for the data; this will bypass
the allow to store blob permission set for the user. {to be concluded} here we are choose to see if we should make the user have to allow the dev to do this, or if we can just do this and make th edev responsible
*/

// in the application each blob ctored with us is wraped in a blobsetting config; telling the renew system the 
// the renew system uses this to as a guide on how to renew the blob
public struct BlobSettings has key, store{
    id: UID,
    blob: Blob,

    // blobs: Option<vector<Blob>>, //todo make this the main state of the blob identity in the blob config object
    epoch_set: u32, //this is the numbers of epoch that the blob will be renewed by
    cycle_at: u64, // this is the current cycle the blob is at
    cycle_end: u64,
    // todo ^^ to be replaced with this 

    // cycle: Option<RenewCycle>,


    /*
    sponsored blobsettings are blobs that are owned by an individual but the cost for renewing the object is carried out by this address
    this is usually nft platfroms 
    */
    sponsor: Option<address>,

    share_payment: SharedPayment

}

/*
this is the option for user to set the data to exist in the system for just a duration of cycles 
*/

// public struct RenewCycle has store {
//     cycle_at: u64, // this is the current cycle the blob is at
//     cycle_end: u64,
// }

/*
this feature allows for cross payment storage. 
allowing for platforms to built on this.
1) sharing blob to others 
2) paltforms paying for the object and not have ownership of the data
||||||||
\/\/\/\/
in this case if the user that the platform wants to give ownership of the blob does not exist on the platform.
then a short signed user accout will be created on behalf of that user 

todo note 
even during transfer of ownership of the blob, only the owner of the blob can transfer it 
therefore. in this case the platform will have to integrate this transfer functionality with their nft

todo note 
if internal transfer of the nft occurs. the user is responsible to ask the seller to transfer the nft blob as well

*/
public struct SharedPayment has store, drop{
    assist: vector<address>
}


public(package) fun config_id(blob_cfg: &BlobSettings): ID{
    object::id(blob_cfg)
}

// internal config creation
//todo depreciate this function 
public(package) fun new_config_blob(blob: Blob, epoch_set: u32, cycle_end: u64, ctx: &mut TxContext): BlobSettings{
    BlobSettings { id: object::new(ctx), blob, epoch_set, cycle_at: 0, cycle_end,  sponsor: option::none(),  share_payment: SharedPayment{assist: vector::empty()}

 } 
}

// main function to create blob_config
// public(package) fun create_config_blob(): BlobSettings{
//     BlobSettings { 
//         id: object::new(ctx), 
//         blob, 
//         epoch_set, 
//         cycle_at: 0, 
//         cycle_end,  
//         sponsor: option::none(),  
//         share_payment: SharedPayment{assist: vector::empty()},
//     }
// }

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
   let BlobSettings {id,  blob, epoch_set: _, cycle_at: _, cycle_end: _, sponsor: _, share_payment: _} = blob_cfg;
   id.delete();
    blob
}

// todo
// burn blob
// withdraw blob
// transfer blob
// share blob