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
///
/// Answers for any term, sold or not. It used to validate first, which meant that
/// a term dropped from the tier table left the backend unable to compute the
/// reserve for a revision it is still allowed to write ,  the refusal arriving one
/// step ahead of the write it was meant to prepare.
///
/// The margin belongs to the live table's longest term, and no unsold term is
/// that, on either side of the ladder ,  a dropped one falls inside the table's
/// range and one above the top is outside it, and both are answered with
/// themselves.
///
/// An answer here is not permission. A caller who is *buying* must ask `validate`
/// or `is_tier` first: reserving against this for a term the system does not sell
/// buys Walrus storage that the store then refuses.
/// `tier_tests::registration_term_answers_for_terms_the_table_does_not_sell` pins
/// both shapes, so restoring the validation fails there rather than in the
/// backend.
public fun registration_term(system_cfg: &SystemConfig, epoch_set: u32): u32 {
    let term = epoch_set;
    let tier_table = system_cfg.tier_table();

    if (term == tier_table[tier_table.length() - 1]) {
        return term + 1
    };

    term
}
