module wait_list::wait;


use std::string::String;
use sui::{
    display::Self,
    package::Self,
    url::{Self, Url},
    event,
    dynamic_field as dfield
    };
use wait_list::{
    contribution::{WarlotData, Self}
    };


// ======== witness =========
public struct WAIT has drop{}



// ====================   wait nft ===================
public struct WaitCard has key, store{
    id: UID,
    name: String,
    description: String,
    image_url: Url,
    warlot: Url,
}



// =============== clone ===============

public struct CloneWaitCard<phantom WAIT> has key, store{
    id: UID,
    admin_slot: u8,
    entry: Option<WaitCard>,
}


// ================ AdminCap Objects ==============

public struct AdminCap has key {
    id: UID,
}


//============  Events  ===========//

public struct WaitCardAdded has copy, drop {
    object_id: ID,
    creator: address,
    receiver: address,
    name: String,
}


//  ==================  Dynamic Field Keys  ================= //
const CONTRIBUTION : vector<u8> = b"WARLOT CONTRIBUTIONS";

//  ==================  Error ==================//
#[error]
const EInvalidClone: vector<u8> = b"Empty Clone";
#[error]
const ESuspendedClone: vector<u8> = b"Clone Suspended";
#[error]
const ECapLimit: vector<u8> = b"Admin cap exceeded";
#[error]
const EActiveClone: vector<u8> = b"Clone Not Yet Suspended";
#[error]
const EInvalidAccess: vector<u8> = b"Already Minted to self";

// ==================== ENV constants ======================//
const ADMINCAP_MAX: u8  = 4;

//============  Public View Functions  ===========//
// get user name
public fun name(wait_card: &WaitCard): &String {
    &wait_card.name
}

// get user description
public fun description(wait_card: &WaitCard): &String {
    &wait_card.description
}

// get user url
public fun image_url(wait_card: &WaitCard): &Url {
    &wait_card.image_url
}

public fun warlot(wait_card: &WaitCard): &Url {
    &wait_card.warlot
}


// get contributions 

public fun borrow_contribution(wait: &WaitCard): &WarlotData { 
    dfield::borrow<vector<u8>, WarlotData>(&wait.id, CONTRIBUTION) 
}


/*
    contributioins will be registered on the WARLOT REGISTRY OBJECT 
    during lunch, the user can then update their mainnet contribution points with the registry
    1> here they can also increase the points using any warlot application that supports this nft
*/
public fun borrow_contribution_mut(_: &mut AdminCap, wait: &mut WaitCard): &mut WarlotData { 
    dfield::borrow_mut<vector<u8>, WarlotData>(&mut wait.id, CONTRIBUTION) 
}




//============  Internal Functions  ===========//
fun init(otw: WAIT, ctx: &mut TxContext) {
    let pub = package::claim(otw, ctx);
    let display = display::new_with_fields<WaitCard>(
        &pub,
        vector[b"name".to_string(), b"description".to_string(), b"media_url".to_string()],
        vector[b"{name}".to_string(), b"{description}".to_string(), b"https://cdn.galxe.com/galaxy/walrus/415ae051-b583-4654-872a-b676c51d94b7.jpeg".to_string()],
        ctx
    );


    let mut admin_cap = AdminCap{id: object::new(ctx)};
    
    let warlot = url::new_unsafe_from_bytes(b"");


    let clone: WaitCard = WaitCard{
        id: object::new(ctx),
        name: b"Genesis NFT".to_string(),
        description: b"url point".to_string(),
        image_url: url::new_unsafe_from_bytes(b"https://cdn.galxe.com/galaxy/walrus/415ae051-b583-4654-872a-b676c51d94b7.jpeg"),
        warlot
    };

    let clone_card =  CloneWaitCard<WAIT>{
            id: object::new(ctx),
            admin_slot: ADMINCAP_MAX - 1,  // admin cap minted with init
            entry: option::some(clone),
        };

    mint_to_request(&mut admin_cap, &clone_card, @0xb694df4db79bca01d90e6d523d0efb3ff494a12dc5cf4396eeb553f7ed7a7f44, ctx);

    transfer::public_share_object(clone_card);

    transfer::transfer(admin_cap, ctx.sender());
    transfer::public_transfer(display, @0xb694df4db79bca01d90e6d523d0efb3ff494a12dc5cf4396eeb553f7ed7a7f44);
    transfer::public_transfer(pub, ctx.sender());

}


// =====================  admin cap =====================//
public fun mint_admin(
    _: &mut AdminCap, 
    clone_card: &mut CloneWaitCard<WAIT>,
    candidate: address,
    ctx: &mut TxContext
){
    assert!(clone_card.admin_slot > 0 , ECapLimit);
    transfer::transfer(
        AdminCap{id: object::new(ctx)},
        candidate
    );

    clone_card.admin_slot = clone_card.admin_slot - 1;

}

// burn AdminCap
public fun burn_admin(
    admin_cap: AdminCap, 
    clone_card: &mut CloneWaitCard<WAIT>,
){
    /*
        making sure that the admin cap to be burnt is not the last one 
         if it is, making sure that the CloneWaitCard<WAIT> has been Suspended
    */
    let minted = ADMINCAP_MAX - clone_card.admin_slot;
    if (minted == 1) { assert!(
        // check to make sure the clone_card have been suspended
        clone_card.entry.is_none(), EActiveClone); 
    };
   

    // terminate  admin_cap
    let AdminCap{id} = admin_cap;
        id.delete();
        clone_card.admin_slot = clone_card.admin_slot + 1;

}

// ===================== admin functions ====================== //
public fun modify_clone(
    _: &mut AdminCap, 
    clone_card: &mut CloneWaitCard<WAIT>,
    wait_card: WaitCard,
    warlot: vector<u8>)
    {

        match(clone_card.entry.is_some()){
            true => {burn(clone_card.entry.swap(wait_card))},
            _ => {clone_card.entry.fill(wait_card)},
        };

        let entry_card = clone_card.entry.borrow_mut();
        entry_card.warlot = url::new_unsafe_from_bytes(warlot); 
        //remove dfields if exist on card to be cloned
        destroy_dfield(&mut entry_card.id);
}

// create a mode wait_card
public fun create_mod(
    _: &mut AdminCap,
    name: String,
    description: String,
    image_url: vector<u8>,
    warlot: vector<u8>,
    ctx: &mut TxContext
): WaitCard{
    
    WaitCard{
        id: object::new(ctx),
        name,
        description,
        image_url: url::new_unsafe_from_bytes(image_url),
        warlot: url::new_unsafe_from_bytes(warlot),
    }

}

// removes all clone parameters
public fun suspend_clone(
    _: &mut AdminCap,
    clone_card: &mut CloneWaitCard<WAIT>
){
    assert!(clone_card.entry.is_some(), EInvalidClone);
    burn(clone_card.entry.extract())
}


// =========== mint  =================  // 
public fun mint(clone_card: &CloneWaitCard<WAIT>, ctx: &mut TxContext): WaitCard{
    assert!(clone_card.entry.is_some(),  ESuspendedClone);
    let state_card = clone_card.entry.borrow();
    let mut wait_card = WaitCard{
        id: object::new(ctx),
        name: state_card.name,
        description: state_card.description,
        image_url: state_card.image_url,
        warlot: state_card.warlot,
    };
    let contribution_card: WarlotData = contribution::create();
    dfield::add<vector<u8>, WarlotData>(&mut wait_card.id, CONTRIBUTION, contribution_card);

    wait_card

}

public fun mint_to_request(_: &mut AdminCap, clone_card: &CloneWaitCard<WAIT>, user: address, ctx: &mut TxContext){
    
    let wait_card = mint(clone_card, ctx);


    event::emit(WaitCardAdded {
        object_id: object::id(&wait_card),
        creator: ctx.sender(),
        receiver: user,
        name: wait_card.name,
    });

    transfer::transfer(
        wait_card,
        user);
}

#[allow(lint(self_transfer))]
public fun mint_to_sender(clone_card: &mut CloneWaitCard<WAIT>, ctx: &mut TxContext){
    let seen = dfield::exists_<address>(&clone_card.id, ctx.sender());
    assert!(!seen, EInvalidAccess);

    let wait_card = mint(clone_card, ctx);
   
    event::emit(WaitCardAdded {
        object_id: object::id(&wait_card),
        creator: ctx.sender(),
        receiver: ctx.sender(),
        name: wait_card.name,
    });

    transfer::transfer(
        wait_card,
        ctx.sender()
        );
    
    dfield::add<address, bool>(&mut clone_card.id, ctx.sender(), true); //limit SelfMint to 1 per person 
       
}

// ======== burn WaitCard   ======================= //

public fun burn(wait_card: WaitCard){
    let  WaitCard{mut id, name: _, description: _, image_url: _, warlot: _} = wait_card;
    destroy_dfield(&mut id);
    id.delete();
}



// ============== helpers ============= //


fun destroy_dfield(wait_card: &mut UID){
    let field_exist = dfield::exists_<vector<u8>>(wait_card, CONTRIBUTION);
            match(field_exist){
                true => {contribution::destroy(dfield::remove<vector<u8>, WarlotData>(wait_card, CONTRIBUTION))},
                _ => {},
            };
}

