module warlottable::warlottable;
use std::string::String;
use sui::dynamic_object_field as ofields;

public struct SystemCfg has store, key{
    id: UID,
    length_users: u64,
    tables: u64
}

public struct AdminCap has store, key{
    id: UID,
    minter: address
}

public struct User has store, key{
    id: UID,
    user: address,
    api_key: String,
    api_url: String,
    user_place_holder_id: ID,
}

public struct UserPlaceHolder has store, key{
    id: UID,
    user: address,
}

public struct TableSet has store, key{
    id: UID,
    blob_id: String,
    blob_sui_obj_id: String,

}

fun init(ctx: &mut TxContext){
    let system_cfg = SystemCfg {
        id: object::new(ctx),
        length_users: 0,
        tables: 0,
    };
    

    let admin_cap = AdminCap {
        id:        object::new(ctx),
        minter: ctx.sender()
    };

    // share the system config so others can reference it
    transfer::public_share_object(system_cfg);
    transfer::public_transfer(admin_cap, ctx.sender());
}


public fun create_user(_: &mut AdminCap, system_cfg: &mut SystemCfg, user: address, api_key: String, api_url: String, ctx: &mut TxContext){
    let user_place_holder_state = UserPlaceHolder{
        id: object::new(ctx),
        user,
    };

    let user_obj =   User{
        id: object::new(ctx),
        user,
        api_key,
        api_url,
         user_place_holder_id: object::id(&user_place_holder_state),
    };

    ofields::add<address, UserPlaceHolder>(&mut system_cfg.id, user, user_place_holder_state);
    transfer::transfer(user_obj, user);

    let old_system_user = system_cfg.length_users;
    system_cfg.length_users = 1 + old_system_user;

}



public fun update_data(user: &mut User, api_key: String, api_url: String){
    user.api_key = api_key;
    user.api_url = api_url;
}

public fun create_table(_: &mut AdminCap, system_cfg: &mut SystemCfg, user: address, table_name: String, blob_id: String, blob_sui_obj_id: String,  ctx: &mut TxContext){
    let user_holder = ofields::borrow_mut<address, UserPlaceHolder>(&mut system_cfg.id, user);
    ofields::add<String, TableSet>(&mut user_holder.id, table_name, TableSet{
    id: object::new(ctx),
    blob_id,
    blob_sui_obj_id
    });

    let old_system_tables = system_cfg.tables;
    system_cfg.tables = old_system_tables + 1; 
}

public fun update_table(_: &mut AdminCap, system_cfg: &mut SystemCfg, user: address, table_name: String, blob_id: String, blob_sui_obj_id: String, ){
    let user_holder = ofields::borrow_mut<address, UserPlaceHolder>(&mut system_cfg.id, user);
    let table = ofields::borrow_mut<String, TableSet>(&mut user_holder.id, table_name);
    table.blob_id = blob_id;
    table.blob_sui_obj_id =  blob_sui_obj_id;
}



