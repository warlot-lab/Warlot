/// Defines the commitment over a set of object ids: the Merkle root a compaction
/// uses to name every config it supersedes in 32 bytes.
///
/// A compaction merges many predecessors into one, so a single back-pointer is
/// the wrong shape and a stored list of ids is a vector that grows without bound
/// on an object that is billed per byte. One root commits to the whole set, the
/// event carries the members, and a holder of one id can fold an audit path
/// against the root without being handed the rest.
///
/// The third of the protocol's three commitments, and deliberately its own
/// module. `commit::root` is over a *sequence* and never reorders; `file_set::root`
/// is over a set of `(path, content_hash)` pairs; this is over a set of ids. They
/// share a shape and nothing else, and folding them together would mean one
/// change to a frozen construction silently moving two others.
module warlot::id_set;

// === Imports ===

use std::hash;

// === Errors ===

#[error]
const EDuplicateId: vector<u8> = b"AN ID SET MUST NOT NAME THE SAME ID TWICE";
#[error]
const EIdSetTooLarge: vector<u8> = b"AN ID SET MUST HOLD AT MOST 666 ENTRIES";
#[error]
const EIdsNotAscending: vector<u8> =
    b"THESE IDS MUST ARRIVE IN ASCENDING BYTE ORDER, WITH NO REPEAT";

// === Constants ===

/// The width of a root and of an id, in bytes.
const ROOT_LENGTH: u64 = 32;

/// Domain separator for a leaf.
///
/// `0x02` rather than the `0x00` the other two constructions use, because an id
/// is exactly as wide as an operation hash: sharing the prefix would make a root
/// over a set of ids byte-identical to a commit over the same 32-byte values in
/// the same order, and two attestations that mean different things would be the
/// same 32 bytes. Interior nodes keep `0x01`, since a node's preimage is already
/// separated from every leaf's by the prefix its children carry.
const LEAF_PREFIX: u8 = 0x02;
/// Domain separator for an interior node.
const NODE_PREFIX: u8 = 0x01;

/// The largest set one root may be taken over.
///
/// Matched to the quilt patch cap for the same reason `file_set` is: the ordering
/// pass is quadratic in the entry count, and a compaction never names more
/// predecessors than a quilt holds patches. In practice a transaction's limit on
/// shared-object inputs binds long before this does.
const MAX_ID_SET: u64 = 666;

// === Public functions ===

/// The commitment over `ids`.
///
/// `ids` is taken by value because the root is a function of the *set*: the ids
/// are sorted here on raw bytes, so two callers that named the same predecessors
/// in a different order agree. A repeated id is refused rather than folded away,
/// because a set that names one predecessor twice has two leaves for it and the
/// count beside the root would disagree with the tree.
///
/// A level holding an odd number of nodes pairs its last node with itself. The
/// empty set has a root, which is what lets a config carry a layout that
/// supersedes nothing.
public fun root(mut ids: vector<ID>): vector<u8> {
    assert!(ids.length() <= MAX_ID_SET, EIdSetTooLarge);

    if (ids.is_empty()) {
        return empty_root()
    };

    sort(&mut ids);
    assert_no_duplicate(&ids);

    let mut level = vector<vector<u8>>[];
    ids.do_ref!(|id| level.push_back(leaf(id)));

    // Each pass halves the level, and the level starts bounded by `MAX_ID_SET`.
    while (level.length() > 1) {
        if (level.length() % 2 == 1) {
            let last = level[level.length() - 1];
            level.push_back(last);
        };

        let mut parents = vector<vector<u8>>[];
        let mut i = 0;
        while (i < level.length()) {
            parents.push_back(node(&level[i], &level[i + 1]));
            i = i + 2;
        };

        level = parents;
    };

    level.pop_back()
}

/// Hash one id into a leaf.
public fun leaf(id: &ID): vector<u8> {
    let mut preimage = vector[LEAF_PREFIX];
    preimage.append(object::id_to_bytes(id));

    hash::sha2_256(preimage)
}

/// Hash two children into their parent.
///
/// Public alongside `leaf` so a holder of one superseded id can check it against
/// the root on chain by folding an audit path.
public fun node(left: &vector<u8>, right: &vector<u8>): vector<u8> {
    let mut preimage = vector[NODE_PREFIX];
    preimage.append(*left);
    preimage.append(*right);

    hash::sha2_256(preimage)
}

/// Whether `a` sorts strictly before `b`.
///
/// Public so a caller assembling a set can keep it ordered as it goes, which is
/// what turns `root`'s quadratic sort into a linear scan.
public fun is_before(a: &ID, b: &ID): bool { before(a, b) }

/// Abort unless `ids` is already in the order `root` folds them in.
///
/// The same trade `file_set::assert_ascending_paths` makes, for the same measured
/// reason: the sort is quadratic, and a caller that names the predecessors is in
/// a position to name them in order.
public fun assert_ascending(ids: &vector<ID>) {
    let length = ids.length();
    let mut i = 1;

    while (i < length) {
        assert!(before(&ids[i - 1], &ids[i]), EIdsNotAscending);
        i = i + 1;
    };
}

// === View functions ===

/// The root of the empty set: thirty-two zero bytes.
public fun empty_root(): vector<u8> {
    let mut zero = vector<u8>[];
    let mut i = 0;
    while (i < ROOT_LENGTH) {
        zero.push_back(0);
        i = i + 1;
    };
    zero
}

/// The largest set one root may be taken over.
public fun max_id_set(): u64 { MAX_ID_SET }

// === Private functions ===

/// Order `ids` ascending on raw bytes.
///
/// Insertion sort, for the reason `file_set` uses one: the set is bounded, the
/// input is very often already close to ordered, and a comparison is a byte-wise
/// walk over two ids rather than a machine word.
fun sort(ids: &mut vector<ID>) {
    let length = ids.length();
    let mut i = 1;

    while (i < length) {
        let mut j = i;
        while (j > 0 && before(&ids[j], &ids[j - 1])) {
            ids.swap(j, j - 1);
            j = j - 1;
        };
        i = i + 1;
    };
}

/// Abort if two entries name the same id.
///
/// Checked after ordering, where equal ids are adjacent.
fun assert_no_duplicate(ids: &vector<ID>) {
    let length = ids.length();
    let mut i = 1;

    while (i < length) {
        assert!(ids[i] != ids[i - 1], EDuplicateId);
        i = i + 1;
    };
}

/// Whether `a` sorts strictly before `b` on raw bytes.
fun before(a: &ID, b: &ID): bool {
    let left = object::id_to_bytes(a);
    let right = object::id_to_bytes(b);

    let mut i = 0;
    while (i < ROOT_LENGTH) {
        if (left[i] != right[i]) {
            return left[i] < right[i]
        };
        i = i + 1;
    };

    false
}
