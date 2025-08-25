module warlot::foreign_meta;

/*
    keeps track of the blob config that is added to the warlot system
*/

public struct ForeignMeta has key {
    id : UID,
}


public(package) fun create_meta(ctx: &mut TxContext){
    transfer::transfer(ForeignMeta{
        id: object::new(ctx)
    },
    ctx.sender()
    )

}

/*
todo 
collect blob collection, add them to a vector list, list has a limit to make sure that the object does not get to expensive
*/
public(package) fun add_foreign_blob(){
    
}

