/// Indexes the blob configs a user has adopted from outside the protocol.
module warlot::foreign_meta;

// === Imports ===

use sui::dynamic_field as dfield;

// === Constants ===

/// The largest number of config ids one vector should hold, chosen to keep the
/// gas cost of appending to it bounded.
const AVG_LEN: u64 = 300;

// === Structs ===

/// A per-user index over the blob configs adopted into the Warlot system.
public struct ForeignMeta has key {
    id: UID,
    /// The vector currently being appended to.
    current_index: u64,
    total_blob_config: u64,
}

// === View functions ===

/// The largest number of config ids one vector should hold.
public(package) fun avg_len(): u64 { AVG_LEN }

/// How many ids the vector currently being appended to already holds.
public(package) fun verify_peak(foreign_meta: &ForeignMeta): u64 {
    vector::length(dfield::borrow<u64, vector<ID>>(&foreign_meta.id, foreign_meta.current_index))
}

// === Package functions ===

/// Create an index for the sender and transfer it to them.
public(package) fun create_meta(ctx: &mut TxContext) {
    let current_index = 0;
    let total_blob_config = 0;
    let mut new_meta = ForeignMeta {
        id: object::new(ctx),
        current_index,
        total_blob_config,
    };

    dfield::add<u64, vector<ID>>(&mut new_meta.id, current_index, vector::empty<ID>());

    transfer::transfer(new_meta, ctx.sender());
}

/// Record `config_blob_list`, starting a new vector when appending would push the
/// current one past its bound.
public(package) fun add_foreign_blob(foreign_meta: &mut ForeignMeta, config_blob_list: vector<ID>) {
    let vec_len = vector::length(
        dfield::borrow<u64, vector<ID>>(&foreign_meta.id, foreign_meta.current_index),
    );
    let config_len = vector::length(&config_blob_list);
    foreign_meta.total_blob_config = foreign_meta.total_blob_config + config_len;

    // Start a new vector when the incoming list alone exceeds the bound, or when
    // the combined size would exceed it and the current vector is already three
    // quarters full. Otherwise append.
    if (
        (config_len > AVG_LEN)
        || ((config_len + vec_len) > AVG_LEN) && vec_len > (3 * AVG_LEN / 4)
    ) {
        foreign_meta.current_index = foreign_meta.current_index + 1;
        dfield::add<u64, vector<ID>>(
            &mut foreign_meta.id,
            foreign_meta.current_index,
            config_blob_list,
        );
    } else {
        vector::append(
            dfield::borrow_mut<u64, vector<ID>>(&mut foreign_meta.id, foreign_meta.current_index),
            config_blob_list,
        );
    }
}
