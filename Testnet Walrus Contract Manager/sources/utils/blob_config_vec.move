
module warlot::blob_config_vec;

use sui::{
       dynamic_object_field as ofields, 
};

use warlot::{
    config::{BlobSettings},
};


public struct BlobConfigVec has key, store{
    id: UID,
    length: u64,
    sync_limit: u64, //when performing a renew,this will allow the system to know where the user funds went out of bound instade of looping throught the whole vector 
}

public(package) fun length(b_cfg_vec: &BlobConfigVec): u64{
    b_cfg_vec.length
}

public(package) fun is_empty(b_cfg_vec: &BlobConfigVec): bool{
    b_cfg_vec.length() == 0
}


public(package) fun empty(ctx: &mut TxContext): BlobConfigVec {
    BlobConfigVec{
        id: object::new(ctx),
        length: 0,
        sync_limit: 0
    }
} 

public(package) fun singleton(item: BlobSettings, ctx: &mut TxContext): BlobConfigVec {
    let mut new = empty(ctx);
    new.push_back(item);

    new
}



public(package) fun push_back(b_cfg_vec: &mut BlobConfigVec, config: BlobSettings){
    let length = b_cfg_vec.length();
    ofields::add<u64, BlobSettings>(
        &mut b_cfg_vec.id,
        length,
        config
    );

    b_cfg_vec.increase_length()

}



public(package) fun borrow(b_cfg_vec: &BlobConfigVec, i : u64): &BlobSettings{
    ofields::borrow<u64, BlobSettings>(
        &b_cfg_vec.id,
        i
    )
}


public(package) fun  borrow_mut(b_cfg_vec: &mut BlobConfigVec, i: u64): &mut BlobSettings{
     ofields::borrow_mut<u64, BlobSettings>(
        &mut b_cfg_vec.id,
        i
    )
}

fun add(b_cfg_vec: &mut BlobConfigVec, config: BlobSettings, i: u64){

    assert!(!ofields::exists_(&b_cfg_vec.id, i), 0);
    ofields::add<u64, BlobSettings>(
        &mut b_cfg_vec.id,
        i,
        config
    );

}


public(package) fun remove(b_cfg_vec: &mut BlobConfigVec, i: u64): BlobSettings{
    ofields::remove<u64, BlobSettings>(
        &mut b_cfg_vec.id,
        i
    )
}


public(package) fun swap(b_cfg_vec: &mut BlobConfigVec, i : u64, j: u64) {

    if (i == j) {
        return
    };

    let config_i = b_cfg_vec.remove(i);
    let config_j = b_cfg_vec.remove(j);
    b_cfg_vec.add(config_i, j);
    b_cfg_vec.add(config_j, i);
}


public fun pop_back(b_cfg_vec: &mut BlobConfigVec): BlobSettings {
    let length = b_cfg_vec.length();
    b_cfg_vec.remove(length - 1)
}



public fun swap_remove(b_cfg_vec: &mut BlobConfigVec, i: u64): BlobSettings {
    let tail = b_cfg_vec.length() - 1;
    b_cfg_vec.swap(i, tail);
    b_cfg_vec.pop_back()
}


fun increase_length(b_cfg_vec: &mut BlobConfigVec,){
    b_cfg_vec.length = b_cfg_vec.length() + 1
}