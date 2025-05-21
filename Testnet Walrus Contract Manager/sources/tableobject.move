module warlot::tablemain;
use sui::clock::Clock;
use std::string::{String};

public struct Table has key, store{
    id: UID,
    name: String,
    time_created: u64,
    last_updated: u64,
    cache_obj: address,
    cache_file: String, //this is the table file id
}

public fun create(
    name: String,
    cache_obj: address,
    cache_file: String,
    clock: &Clock,
    ctx: &mut TxContext): Table{

    let table = Table{
        id: object::new(ctx),
        name,
        time_created: clock.timestamp_ms(),
        last_updated: clock.timestamp_ms(),
        cache_obj,
        cache_file, 

    };

    table

}




public fun get_name(table: &Table): String{
    table.name 
}



public fun update(
    table: &mut Table, 
    cache_obj: address,
    cache_file: String,
    clock: &Clock
    ){
    table.cache_file = cache_file;
    table.cache_obj  = cache_obj;
    table.last_updated = clock.timestamp_ms();
}
// ======helper =======///




