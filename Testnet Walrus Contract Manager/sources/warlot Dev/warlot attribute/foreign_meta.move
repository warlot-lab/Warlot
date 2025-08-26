module warlot::foreign_meta;
use sui::{
       dynamic_field as dfield, 

};

/*
    keeps track of the blob config that is added to the warlot system
*/

public struct ForeignMeta has key {
    id : UID,
    current_index: u64,

}



//  ===========  average peak foreign meta len ==============//
// this is the max amount of object id a single vector should hold 
// in order for the gas fee to not be high 
const AVG_LEN: u64 = 300;

public(package) fun avg_len():u64{AVG_LEN}



public(package) fun create_meta(ctx: &mut TxContext){
    let current_index = 0;
    let mut new_meta = ForeignMeta{
        id: object::new(ctx),
        current_index,
    };

    dfield::add<u64, vector<ID>>(&mut new_meta.id, current_index, vector::empty<ID>());

    transfer::transfer(
        new_meta,
        ctx.sender()
    );

}


// this function will be used to confirm the lenght of the current_index list 
// to make sure that the built vector<ID> sent does not exceed what the indexer needs
public(package) fun verify_peak(foreign_meta: &ForeignMeta): u64{
    vector::length(dfield::borrow<u64, vector<ID>>(&foreign_meta.id, foreign_meta.current_index))
}

/*
todo 
so here the collection of the warlot config_blob, that have been 
*/
public(package) fun add_foreign_blob(foreign_meta: &mut ForeignMeta, config_blob_list: vector<ID>){
    let vec_len = vector::length(dfield::borrow<u64, vector<ID>>(&foreign_meta.id, foreign_meta.current_index));
    let config_len = vector::length(&config_blob_list);
    
   
    // if the incoming config alone is larger than AVG_LEN,
    // or (the combined size would exceed AVG_LEN AND the current vector set is already >= 3/4 full),
    // then create a new vector set; otherwise append to the current vector set .
    if (
        (config_len > AVG_LEN)
        || 
        (
            (config_len + vec_len) > AVG_LEN) && vec_len > (3 * AVG_LEN/ 4)
            )
     {
        
        foreign_meta.current_index = foreign_meta.current_index + 1;
        dfield::add<u64, vector<ID>>( &mut foreign_meta.id, foreign_meta.current_index, config_blob_list);
    }else{
         // safe to append into the existing vector set
        vector::append(dfield::borrow_mut<u64, vector<ID>>(&mut foreign_meta.id, foreign_meta.current_index), config_blob_list);
    }
}

