module warlot::config;
use walrus::{blob::Blob, system::System};
use wal::wal::{WAL};
use sui::{
    coin::Coin,
    clock::Clock};


/*
todo move optional meta to this part of the smart contract
1]thereby removing the file object from the warlot attribute. making indexing of the epoch a lot more efficent 
2] set up the warlot dev to be able to put files under users address but only the dev will pay for the data; this will bypass
the allow to store blob permission set for the user. {to be concluded} here  are choose to see if  should make the user have to allow the dev to do this, or if  can just do this and make th edev responsible
*/

// in the application each blob ctored with us is wraped in a blobsetting config; telling the renew system the 
// the renew system uses this to as a guide on how to renew the blob
public struct BlobConfig has key, store{
    id: UID,
    blobs: vector<Blob>, 
    epoch_set: u32, //this is the numbers of epoch that the blob will be renewed by
    cycle_limit: Option<u64>, // set cycle if not an indefinate blob set
    fileMeta_id: Option<ID>,  // index the fileMeta id if there is any 

    /*
    sponsored BlobConfig are blobs that are owned by an individual but the cost for renewing the object is carried out by this address
    this is usually nft platfroms 
    */
    sponsor: Option<address>,

    share_payment: SharedPayment,
    uploaded_on: u64,

    index : Index,

}


/*
    this allows effective loop of the files and arrangement
*/

public struct Index has drop, store{
    pre: Option<ID>,
    next: Option<ID>,
}




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


public(package) fun config_id(blob_cfg: &BlobConfig): ID{
    object::id(blob_cfg)
}

// internal config creation
//todo depreciate this function 
public(package) fun new_config_blob(
    blobs: vector<Blob>, 
    epoch_set: u32, 
    cycle_limit: Option<u64>,  
    fileMeta_id: Option<ID>, 
    clock: &Clock,
    ctx: &mut TxContext): BlobConfig{
    BlobConfig { 
        id: object::new(ctx), 
        blobs, 
        epoch_set, 
        cycle_limit,
        fileMeta_id,  
        sponsor: option::none(),  
        share_payment: SharedPayment{assist: vector::empty()},
        uploaded_on: clock.timestamp_ms(),
        index: Index{
            pre: option::none(),
            next: option::none(),
        }
 }
}

// =============================  chain node functions ======================
public(package) fun pre(blob_cfg: &BlobConfig): &Option<ID>{
    &blob_cfg.index.pre
}


public(package) fun next(blob_cfg: &BlobConfig): &Option<ID>{
    &blob_cfg.index.next
}


public(package) fun set_pre(blob_cfg: &mut BlobConfig, pre: ID): Option<ID>{
    option::swap_or_fill(&mut blob_cfg.index.next, pre)
}

public(package) fun set_next(blob_cfg: &mut BlobConfig, next: ID): Option<ID>{
    option::swap_or_fill(&mut blob_cfg.index.next, next)
}

public(package) fun set_pre_none(blob_cfg: &mut BlobConfig): ID{
     option::extract(&mut blob_cfg.index.pre)
}

public(package) fun set_next_none(blob_cfg: &mut BlobConfig): ID{
     option::extract(&mut blob_cfg.index.next)
}



// get a mutable reference to the internal blob
public(package) fun blob(blob_cfg: &mut BlobConfig): &mut vector<Blob>{
    &mut blob_cfg.blobs
}

// get the epoch set of the blob<the max amount of epoch that the blob should renewed by>
public(package) fun epoch_set(blob_cfg: &BlobConfig): u32{
    blob_cfg.epoch_set
}


// get the amount of times the blobs should be renewed on the system
public(package) fun cycle_limit(blob_cfg: &BlobConfig): Option<u64>{
    if(option::is_none(&blob_cfg.cycle_limit)){
        return option::none()
    };
    option::some(*option::borrow<u64>(&blob_cfg.cycle_limit))
}



// checek if the internal blob is deletable
// returns false if any of the blob collections is not deletable
public(package) fun is_deletable(blob_cfg: &BlobConfig): bool{
    let mut deletable = true;
    blob_cfg.blobs.do_ref!( |blob| {
            if (!blob.is_deletable()){
                deletable = false;
                return
            }
         });

    return deletable 
}


// get the size of the internal blob
public(package) fun blob_cfg_size(blob_cfg: &BlobConfig): u64{
    let mut size = 0;
    blob_cfg.blobs.do_ref!(|blob| {size = size + blob.size() });
    size
}


// this function is used to calculate the number of epoch a blob needs to sync with 
// the needed epoch set
// where ahead is the epoch sync epoch count
public(package) fun get_renew_epoch_count(blob: &Blob, system: &System, ahead: u32): u32 {
    let current_epoch = system.epoch();
    let blob_end_epoch = blob.storage().end_epoch();
    
    let target_epoch = current_epoch + ahead;

    // SAFETY CHECKS:
    // 1. (blob_end_epoch < current_epoch): 
    //    If blob is expired,  cannot renew. Return 0.
    // 2. (blob_end_epoch >= target_epoch): 
    //    If blob is already paid far enough into the future,  owe nothing. Return 0.
    //    (This also prevents the underflow panic).
    if (blob_end_epoch < current_epoch || blob_end_epoch >= target_epoch) {
        return 0
    };

    // Safe subtraction
    target_epoch - blob_end_epoch
}



public(package) fun renew_blob_cfg(
    blob_cfg: &mut BlobConfig, 
    system: &mut System, 
    ahead: u32, 
    payment: &mut Coin<WAL>
) {
    // 1. Handle Cycle Limit
    if (option::is_some(&blob_cfg.cycle_limit)) {
        // Borrow mutably right away to avoid conflicting borrows
        let cycle_limit = option::borrow_mut(&mut blob_cfg.cycle_limit);
        
        if (*cycle_limit == 0) {
            return
        };
        
        // Decrement the limit
        *cycle_limit = *cycle_limit - 1;
    };

    //  Process Blobs

    blob_cfg.blobs.do_mut!( |blob| {
        // get viable epoch end count
        let extend_epoch_count = get_renew_epoch_count(blob, system, ahead);

        // make sure that  only renew needed data
        if (extend_epoch_count > 0) {
            extend_blob(system, blob, payment, extend_epoch_count);
        }
    });
}


// // get the amount or relative amount the is reqired for the blob to be synced with a walrus ahead epoch
// public fun sync_epoch_count(blob_cfg: &BlobConfig, system: &System, epoch_checkpoint: u32): u32 {

//     let current_epoch = system.epoch();

//     let blob_end_epoch = blob_cfg.blob_current();

//      if (blob_end_epoch > current_epoch){
//         return 0
//     };

//     if (blob_end_epoch >= epoch_checkpoint) {
//         return 2
//     };


//     let gap = epoch_checkpoint - blob_end_epoch;


//     if (gap > constants::max_sync_epochs()) {
//         return constants::max_sync_epochs()
//     } else {
//         return gap
//     }
// }


public(package) fun extend_blob(
    system: &mut System,
    blob: &mut Blob,
    payment: &mut Coin<WAL>,
    new_epoch: u32,
) {
    system.extend_blob(blob, new_epoch, payment);
}


// safe return the internal blob and delete the blob config object
public(package) fun withdraw_and_burn(blob_cfg: BlobConfig): vector<Blob>{
   let BlobConfig {id,  blobs, epoch_set: _, cycle_limit: _, fileMeta_id: _, sponsor: _, share_payment: _,   uploaded_on: _, index: _} = blob_cfg;
   id.delete();
    blobs
}
  
// todo
// burn blob
// withdraw blob
// transfer blob
// share blob
// ================== Test Helpers ==================

#[test_only]
public fun create_dummy_config(epoch: u32, clock: &Clock, ctx: &mut TxContext): BlobConfig {
    new_config_blob(vector[], epoch, option::none(), option::none(), clock, ctx)
}

#[test_only]
public fun destroy_dummy_config(cfg: BlobConfig) {
    // Burn the config object and get the internal vector
    let blobs = withdraw_and_burn(cfg);

    vector::destroy_empty(blobs);
}