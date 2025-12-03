module wait_list::wait;


use std::string::String;
use sui::{
    display::{Self, Display},
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
    image_url: String,
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
#[error]
const EInvalidUser: vector<u8> = b"Admin has minted for this user";

// ==================== ENV constants ======================//
const ADMINCAP_MAX: u8  = 4;



// ===================== Nft meta ======================//
const FULL_DESCRIPTION: vector<u8> = b"The genesis piece of the Warlot ecosystem. This NFT embodies the rallying cry that unites builders, creators, and visionaries to join the on-chain movement. The warthog, a symbol of resilience and grit, wears the call proudly across its shades: JOIN US. The patterned circles reflect fragments of on-chain storage coming together; a reminder of how Warlot unites diverse data and use cases into one ecosystem. Owning 'The Warlot Call' marks you as one of the first to answer; a pioneer in shaping the future of transparent, persistent, and community-driven storage."; 
const OVERVIEW_DESCRIPTION: vector<u8> = b"With shades that speak louder than words, The Warlot Call welcomes you to Warlot ecosystem.";
const NAME: vector<u8> = b"The Warlot Call";
const IMAGE_URL: vector<u8> = b"https://waitlist.warlot.xyz/warlot,%20image.png";
const THUMBNAIL_URL: vector<u8> = b"https://waitlist.warlot.xyz/warlot,%20image.png";
const WARLOT_URL: vector<u8> = b"https://www.warlot.xyz";
const CREATOR: vector<u8> = b"WARLOT TEAM";

// ====================  Public Functions  ======================//
// get user name
public fun name(wait_card: &WaitCard): &String {
    &wait_card.name
}

// get user description
public fun description(wait_card: &WaitCard): &String {
    &wait_card.description
}

// get user url
public fun image_url(wait_card: &WaitCard): &String {
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
     let keys = vector[
            b"name".to_string(), 
            b"description".to_string(), 
            b"media_url".to_string(), 
            b"thumbnail_url".to_string(), 
            b"image_url".to_string(),
            b"project_url".to_string(),
            b"creator".to_string(),
            ];
    let values = vector[
            NAME.to_string(), 
            FULL_DESCRIPTION.to_string(), 
            IMAGE_URL.to_string(), 
            THUMBNAIL_URL.to_string(), 
            IMAGE_URL.to_string(),
            WARLOT_URL.to_string(),
            CREATOR.to_string(),
            ];
    let mut display = display::new_with_fields<WaitCard>(
        &pub,
        keys, 
        values, 
        ctx
    );


    let mut admin_cap = AdminCap{id: object::new(ctx)};
    
    let warlot = url::new_unsafe_from_bytes(WARLOT_URL);


    let clone: WaitCard = WaitCard{
        id: object::new(ctx),
        name: NAME.to_string(),
        description: OVERVIEW_DESCRIPTION.to_string(),
        image_url: IMAGE_URL.to_string(),
        warlot
    };

    let clone_card =  CloneWaitCard<WAIT>{
            id: object::new(ctx),
            admin_slot: ADMINCAP_MAX - 1,  // admin cap minted with init
            entry: option::some(clone),
        };


    display.update_version();

    mint_to_request(&mut admin_cap, &clone_card, @0x043a388f2849fecfc38e57cc0928b71d90067dece08564c1215c12d712489d7a, ctx);

    transfer::public_share_object(clone_card);

    transfer::transfer(admin_cap, ctx.sender());
    transfer::public_transfer(display, ctx.sender());
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


// ===================== modify display ========================//
public fun add_display(
    _: &mut AdminCap,
    display_ob: &mut Display<WaitCard>, 
    name: String, 
    value: String
){
    display::add(display_ob, name, value);
}

public  fun add_multiple_display(
    _ : &mut AdminCap,
    display_ob: &mut Display<WaitCard>,
    names: vector<String>,
    values: vector<String>,
) {
    display::add_multiple(display_ob, names, values);
}

public fun  edit_display(
    _: &mut AdminCap,
    display_ob:  &mut Display<WaitCard>, 
    name: String, 
    value: String
) {
    display::edit(display_ob, name, value);
}

public fun remove_display(
    _: &mut AdminCap,
    display_ob: &mut Display<WaitCard>, 
    name: String
) {
    display::remove(display_ob, name);
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
        image_url: image_url.to_string(),
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
fun mint(clone_card: &CloneWaitCard<WAIT>, ctx: &mut TxContext): WaitCard{
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

public fun mint_to_request(admin_cap: &mut AdminCap, clone_card: &CloneWaitCard<WAIT>, user: address, ctx: &mut TxContext){
    let seen = dfield::exists_<address>(&admin_cap.id, user);
    assert!(!seen, EInvalidUser);
    
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
    
    dfield::add<address, bool>(&mut admin_cap.id, user, true); //limit SelfMint to 1 per person 
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



#[test]
fun test_wait() {
    let mut ctx = tx_context::dummy();
    let otw = WAIT{};
    mock_init(otw, &mut ctx);


}

#[test_only]
fun mock_init(){

}

#[test]
fun create_clone(){
    let mut ctx = tx_context::dummy();
    let otw = WAIT{};
    let pub = package::mock_claim(otw, &mut ctx);
    let mut admin_cap = AdminCap{id: object::mock_new(&mut ctx)};
    let warlot = url::new_unsafe_from_bytes(b"");  
}

#[test]
fun create_admin(){
    let mut ctx = tx_context::dummy();
    let otw = WAIT{};
    let pub = package::mock_claim(otw, &mut ctx);
    let mut admin_cap = AdminCap{id: object::mock_new(&mut ctx)};
    let warlot = url::new_unsafe_from_bytes(b"");
}

#[test]
fun create_card(){
    let mut ctx = tx_context::dummy();
    let otw = WAIT{};
    let pub = package::mock_claim(otw, &mut ctx);
    let mut admin_cap = AdminCap{id: object::mock_new(&mut ctx)};
    let warlot = url::new_unsafe_from_bytes(b"");
}