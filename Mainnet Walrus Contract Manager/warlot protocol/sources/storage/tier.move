/// Resolves a requested `epoch_set` to one of the storage terms the system offers.
module warlot::tier;

// === Constants ===

/// The shortest epoch set the system currently accounts for.
const FIRST_SET: u32 = 13;
/// The middle epoch set the system currently accounts for.
const HALF_SET: u32 = 23;
/// The longest epoch set the system currently accounts for.
const MAX: u32 = 53;

// === View functions ===

/// The shortest storage term on offer.
public(package) fun first_set(): u32 { FIRST_SET }

/// The middle storage term on offer.
public(package) fun half_set(): u32 { HALF_SET }

/// The longest storage term on offer.
public(package) fun max(): u32 { MAX }

// === Package functions ===

/// Map a requested epoch set onto the term the system will actually sell.
public(package) fun get_set(epoch_set: u32): u32 {
    let set = if (epoch_set > half_set()) {
        max()
    } else if (epoch_set > first_set()) {
        half_set()
    } else {
        first_set()
    };

    set
}
