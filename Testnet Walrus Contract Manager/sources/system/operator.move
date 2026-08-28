/// Holds the operator set: the admin capabilities a system accepts as backend
/// credentials, each with an expiry and a draft-bypass bit.
///
/// The set is keyed by capability **id** rather than by address. Moving a
/// capability to another wallet is a transfer of an owned object and touches
/// nothing here, so rotating a backend key costs no on-chain write at all; only
/// adding or retiring a slot does. An address set would need one admin
/// transaction per key swap, on top of the per-user re-granting the old single
/// `warlot_allowed_address` demanded.
module warlot::operator;

// === Imports ===

use sui::vec_map::{Self, VecMap};
use warlot::admin_cap::{Self, AdminCap};

// === Errors ===

#[error]
const ENotAnOperator: vector<u8> = b"THIS CAPABILITY IS NOT IN THE SYSTEM OPERATOR SET";
#[error]
const EOperatorExpired: vector<u8> = b"THIS OPERATOR CREDENTIAL HAS EXPIRED";
#[error]
const ENotDuplicateCap: vector<u8> =
    b"AN OPERATOR CREDENTIAL MUST BE A DUPLICATE ADMIN CAPABILITY";
#[error]
const ECapForAnotherSystem: vector<u8> = b"THIS ADMIN CAPABILITY WAS MINTED FOR A DIFFERENT SYSTEM";
#[error]
const EOperatorSetFull: vector<u8> = b"THIS SYSTEM ALREADY HOLDS AS MANY OPERATORS AS IT ALLOWS";
#[error]
const EAlreadyAnOperator: vector<u8> =
    b"THIS CAPABILITY ALREADY HOLDS A SLOT IN THE SYSTEM OPERATOR SET";
#[error]
const EInvalidOperatorExpiry: vector<u8> =
    b"AN OPERATOR SLOT MUST EXPIRE AT A FUTURE TIMESTAMP";

// === Constants ===

/// The largest operator set a system will hold.
///
/// The set lives inline on a shared object and is scanned on every delegated
/// call, so it is bounded for the same reason the tier table is. Sixteen is far
/// past the size of any real signing pool and keeps the scan free.
const MAX_OPERATORS: u64 = 16;

// === Structs ===

/// The capabilities this system accepts as operator credentials.
public struct OperatorSet has store {
    /// Keyed by capability id, so a rotation is a transfer and not a write.
    slots: VecMap<ID, Operator>,
}

/// One operator slot.
public struct Operator has copy, drop, store {
    /// The timestamp in ms past which this slot is refused.
    expires_at_ms: u64,
    /// Whether this operator may ask for a write that skips the draft queue.
    /// The file's own bit still has to agree ,  see `inner_file`.
    may_bypass_draft: bool,
}

/// Proof, good for the length of one call, that the sender presented a live
/// operator credential.
///
/// It has no `store`, so no object can keep one: a struct with `key` or `store`
/// cannot carry a field that lacks `store`. The only way to obtain one is
/// `authorise`, which needs a `&AdminCap`, so a function taking one cannot be
/// reached by a caller that does not hold the capability.
public struct OperatorAuth has copy, drop {
    cap_id: ID,
    may_bypass_draft: bool,
}

// === View functions ===

/// How many operators this system holds.
public fun operator_count(operators: &OperatorSet): u64 {
    operators.slots.size()
}

/// Whether `cap_id` holds a slot, expired or not.
public fun is_operator(operators: &OperatorSet, cap_id: ID): bool {
    operators.slots.contains(&cap_id)
}

/// The timestamp in ms past which `cap_id`'s slot is refused.
public fun operator_expiry(operators: &OperatorSet, cap_id: ID): u64 {
    assert!(operators.slots.contains(&cap_id), ENotAnOperator);
    operators.slots[&cap_id].expires_at_ms
}

/// Whether `cap_id`'s slot carries the draft-bypass bit.
public fun operator_may_bypass_draft(operators: &OperatorSet, cap_id: ID): bool {
    assert!(operators.slots.contains(&cap_id), ENotAnOperator);
    operators.slots[&cap_id].may_bypass_draft
}

/// Every capability id this system holds a slot for.
public fun operator_ids(operators: &OperatorSet): vector<ID> {
    operators.slots.keys()
}

/// The largest operator set a system will hold.
public fun max_operators(): u64 { MAX_OPERATORS }

/// The capability the authorised sender presented.
public fun auth_cap_id(auth: &OperatorAuth): ID { auth.cap_id }

/// Whether the authorised sender's slot carries the draft-bypass bit.
public fun auth_may_bypass_draft(auth: &OperatorAuth): bool { auth.may_bypass_draft }

// === Package functions ===

/// An operator set holding nobody.
///
/// A system opens with no operator. The capability minted beside it is an
/// original, and an original is refused as a credential by `authorise`, so the
/// hot signing key has to be minted and enrolled deliberately rather than
/// arriving with the system.
public(package) fun empty(): OperatorSet {
    OperatorSet { slots: vec_map::empty() }
}

/// Give `cap_id` a slot it does not already hold.
///
/// Refuses an id that is already enrolled rather than overwriting it. Onboarding
/// a key and extending one are different acts with different consequences ,  an
/// enrolment that quietly became an extension would move a live key's deadline
/// and change its bypass bit while the admin believed they were adding a new one
/// ,  so each is its own call and each says which it is.
public(package) fun enrol(
    operators: &mut OperatorSet,
    cap_id: ID,
    expires_at_ms: u64,
    may_bypass_draft: bool,
    now_ms: u64,
) {
    assert!(expires_at_ms > now_ms, EInvalidOperatorExpiry);
    assert!(!operators.slots.contains(&cap_id), EAlreadyAnOperator);
    assert!(operators.slots.size() < MAX_OPERATORS, EOperatorSetFull);

    operators.slots.insert(cap_id, Operator { expires_at_ms, may_bypass_draft });
}

/// Replace the terms of a slot `cap_id` already holds.
///
/// Refuses an id that holds none, so a refresh cannot silently become an
/// enrolment. This is what keeps the expiry from being a one-way countdown to an
/// outage: the admin moves the deadline rather than retiring and re-adding, and a
/// full set can still be kept alive because no slot is consumed.
public(package) fun refresh(
    operators: &mut OperatorSet,
    cap_id: ID,
    expires_at_ms: u64,
    may_bypass_draft: bool,
    now_ms: u64,
) {
    assert!(expires_at_ms > now_ms, EInvalidOperatorExpiry);
    assert!(operators.slots.contains(&cap_id), ENotAnOperator);

    *operators.slots.get_mut(&cap_id) = Operator { expires_at_ms, may_bypass_draft };
}

/// Drop `cap_id`'s slot, reporting whether it held one.
///
/// Retiring an id that holds no slot is not an error, for the reason a
/// revocation never is here: the caller gets the state they asked for either
/// way, and a retirement that can abort is one that can fail inside the batch
/// where a compromised key is being pulled. The return value is what the caller
/// announces, so a no-op is visibly a no-op in the stream rather than being
/// reported as a retirement that did not happen.
public(package) fun remove(operators: &mut OperatorSet, cap_id: ID): bool {
    if (!operators.slots.contains(&cap_id)) {
        return false
    };

    let (_, Operator { expires_at_ms: _, may_bypass_draft: _ }) = operators.slots.remove(&cap_id);

    true
}

/// Abort unless `admin_cap` is a live operator credential for `system_id`, and
/// hand back the proof that it is.
///
/// Four conditions. The capability is a duplicate, so the credential the backend
/// signs with cannot reach the treasury, mint a system or change a cost ,
/// `assert_original_cap_for` already refuses a duplicate everywhere that matters
/// and this is the other half of that fence. It names this system, for the same
/// reason every other capability check does. It holds a slot. And the slot has
/// not expired: a capability does not decay on its own, so without this the
/// operator path would be the one delegated credential in the protocol that
/// outlives its own usefulness silently.
public(package) fun authorise(
    operators: &OperatorSet,
    admin_cap: &AdminCap,
    system_id: ID,
    now_ms: u64,
): OperatorAuth {
    assert!(admin_cap.state() == admin_cap::state_duplicate(), ENotDuplicateCap);
    assert!(admin_cap.system_config_id() == system_id, ECapForAnotherSystem);

    let cap_id = object::id(admin_cap);
    assert!(operators.slots.contains(&cap_id), ENotAnOperator);

    let slot = operators.slots[&cap_id];
    assert!(slot.expires_at_ms > now_ms, EOperatorExpired);

    OperatorAuth { cap_id, may_bypass_draft: slot.may_bypass_draft }
}
