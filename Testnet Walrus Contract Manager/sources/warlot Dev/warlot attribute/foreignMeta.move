module warlot::ForeignMeta;

/*
    keeps track of the blob config that is added to the warlot system
*/

public struct ForeignMeta has key {
    id : UID,
}


public(package) fun create_meta(ctx: &mut TxContext): ForeignMeta{
    ForeignMeta{
        id: object::new(ctx)
    }
}

public(package) fun add_foreign_blob(){
    
}

