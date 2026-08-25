/// Decides whether a requested `epoch_set` is a storage term the system sells.
module warlot::tier;

// === Imports ===

use warlot::system_config::SystemConfig;

// === Errors ===

#[error]
const EInvalidTier: vector<u8> = b"THIS IS NOT A STORAGE TERM THIS SYSTEM SELLS";

// === View functions ===

/// Whether `epoch_set` is one of the terms the system sells.
public fun is_tier(system_cfg: &SystemConfig, epoch_set: u32): bool {
    system_cfg.tier_table().contains(&epoch_set)
}

// === Public functions ===

/// Return `epoch_set` unchanged, or abort because the system does not sell it.
///
/// The term a caller asks for is the term they get. The previous form folded any
/// number into whichever of three buckets it fell nearest, so a request for 30
/// epochs came back as 53 with no error and no event, and the caller was billed
/// for a term they had not chosen. Refusing by name costs one failed transaction;
/// coercing silently costs the difference between the two terms, forever.
///
/// The scan is bounded by the tier table, which the system caps and validates.
public fun validate(system_cfg: &SystemConfig, epoch_set: u32): u32 {
    assert!(is_tier(system_cfg, epoch_set), EInvalidTier);

    epoch_set
}

/// How far ahead storage is bought when a caller registers at `epoch_set`.
///
/// Every term but the longest registers at itself. The longest registers one
/// epoch higher and is renewed back down to itself, so that a blob on the term
/// where the most valuable data lives always has one epoch of extension left ,
/// Walrus refuses to extend past the horizon, and a blob already sitting on it
/// has nowhere to go if a renewal cycle fails or a wallet runs dry. Shorter terms
/// need no such margin; they are already far below the horizon.
///
/// Read off chain, by whoever reserves the storage: registration happens against
/// Walrus before the protocol ever sees the blob, so this is the one place the
/// reserve rule is written down in a form both sides can agree on.
public fun registration_term(system_cfg: &SystemConfig, epoch_set: u32): u32 {
    let term = validate(system_cfg, epoch_set);
    let tier_table = system_cfg.tier_table();

    if (term == tier_table[tier_table.length() - 1]) {
        return term + 1
    };

    term
}
