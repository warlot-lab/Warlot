/// Names the authority one inner-file write was made under.
///
/// A `Credential` is an argument and an event field, never a struct field. It is
/// constructible only from the object it names, so a function that takes one
/// cannot be reached by a caller holding neither a writer pass nor an admin
/// capability, and the kind is settled by the type system rather than by the
/// caller's word for it. A bare `ID` carries no such answer: nothing on chain can
/// take an id and say what it names.
///
/// **Never store it.** Not, as was assumed when this was designed, because the
/// variant set only becomes frozen once it sits inside a stored struct: adding a
/// variant to *any* enum a published module declares is refused as an
/// incompatible upgrade, stored or not, and Move has no internal enum to escape
/// into. Storing it would freeze the field's layout as well, which is the second
/// refusal on top of the first ,  so the rule stands and its price is already
/// paid. A third credential kind needs a new package either way.
module warlot::credential;

// === Imports ===

use warlot::{admin_cap::AdminCap, writer_pass::WriterPass};

// === Constants ===

/// The discriminant a pass-authorised write carries in the event stream.
const KIND_PASS: u8 = 0;

/// The discriminant an operator-authorised write carries in the event stream.
const KIND_OPERATOR: u8 = 1;

// === Structs ===

/// The authority behind one write: a writer pass, or a system operator's admin
/// capability.
public enum Credential has copy, drop {
    /// A writer pass minted on the file being written.
    Pass(ID),
    /// An admin capability holding a live slot in the system's operator set.
    Operator(ID),
}

// === View functions ===

/// The id of the object the credential names.
public fun id(credential: &Credential): ID {
    match (credential) {
        Credential::Pass(pass_id) => *pass_id,
        Credential::Operator(cap_id) => *cap_id,
    }
}

/// Whether the credential is an operator's capability rather than a pass.
public fun is_operator(credential: &Credential): bool {
    match (credential) {
        Credential::Pass(_) => false,
        Credential::Operator(_) => true,
    }
}

/// The credential's kind as the event stream carries it: `0` a pass, `1` an
/// operator capability.
///
/// The discriminant goes into the event rather than onto the object, which is
/// what lets the id on a draft be either kind without the draft having to hold a
/// field saying which.
public fun kind(credential: &Credential): u8 {
    match (credential) {
        Credential::Pass(_) => KIND_PASS,
        Credential::Operator(_) => KIND_OPERATOR,
    }
}

/// The discriminant a pass-authorised write carries.
public fun kind_pass(): u8 { KIND_PASS }

/// The discriminant an operator-authorised write carries.
public fun kind_operator(): u8 { KIND_OPERATOR }

// === Package functions ===

/// The credential a writer pass confers.
public(package) fun from_pass(pass: &WriterPass): Credential {
    Credential::Pass(object::id(pass))
}

/// The credential an admin capability confers.
///
/// Holding the capability is not on its own authority to act for anyone: the
/// slot in the system's operator set and the account owner's grant of the
/// operator role are checked separately, and this only records which capability
/// was presented.
public(package) fun from_operator(admin_cap: &AdminCap): Credential {
    Credential::Operator(object::id(admin_cap))
}
