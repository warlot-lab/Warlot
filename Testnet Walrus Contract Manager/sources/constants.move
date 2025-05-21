module warlot::constants;
use std::string::String;
// ===== setandrenew.move
const STATE_ORIGINAL: u8 = 0;
const STATE_DUPLICATE: u8 = 1;

const FIRST_SET: u32 = 13;
const HALF_SET: u32 = 23;
const MAX: u32 = 53;

const  API_DECAY: u64 = 10000000000;

const MAX_SYNC_EPOCHS: u32 = 53;

// =======User Indexer value   =========//
const USER_INDEXER: vector<u8> = b"INDEXER";


// ==== exposed constants ======= //
public(package) fun state_original(): u8{STATE_ORIGINAL}
public(package) fun state_duplicate(): u8{STATE_DUPLICATE}


public(package) fun first_set(): u32{FIRST_SET}
public(package) fun half_set(): u32{HALF_SET}
public(package) fun max(): u32{MAX}



public(package) fun api_decay(): u64{API_DECAY}


public(package) fun indexer_key(): String{USER_INDEXER.to_string()} 

public(package) fun max_sync_epochs():u32{MAX_SYNC_EPOCHS}