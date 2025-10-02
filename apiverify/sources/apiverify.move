module apiverify::apiverify;

use std::string::String;
use sui::{
 
    dynamic_field as dfield, 
    };


public struct ApiVerify has  key, store {
    id: UID,
    length: u64,
}


public struct ApiPayload has drop, store {
    hashed_api: String,
    user: address,
}

const ADMIN: address = @0x5038de3e63c8b7b356e598d3c5b9d0efb905533141c11babcab5c59f34d05efb;

fun init(ctx: &mut TxContext){
    let api_verify = ApiVerify {
        id: object::new(ctx),
        length: 0,
    };

    

    transfer::transfer(api_verify, ADMIN);
}

public fun add_api(
    api_verify: &mut ApiVerify,
    key: String,
    hashed_api: String,
    user: address
){
    let payload = ApiPayload {
        hashed_api,
        user,
    };

    dfield::add<String, ApiPayload>(
        &mut api_verify.id,
        key,
        payload,
    );
    api_verify.length = api_verify.length + 1;
}

public fun modify_api(
    api_verify: &mut ApiVerify,
    key: String,
    new_hashed_api: String,
    new_user: address,
){
    let payload = dfield::borrow_mut<String, ApiPayload>(
        &mut api_verify.id,
        key,
    );
    payload.hashed_api = new_hashed_api;
    payload.user = new_user;
}  

public fun remove_api(
    api_verify: &mut ApiVerify,
    key: String,
){
    let payload = dfield::remove<String, ApiPayload>(
        &mut api_verify.id,
        key,
    );

    let ApiPayload{hashed_api: _, user: _} = payload;


    api_verify.length = api_verify.length - 1;
}



