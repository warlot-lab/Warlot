/// Defines the commitment a revision carries: a fixed-width Merkle root over the
/// operations the revision represents.
module warlot::commit;

// === Imports ===

use std::hash;

// === Errors ===

#[error]
const EInvalidRootLength: vector<u8> = b"A COMMIT MUST BE EXACTLY 32 BYTES";
#[error]
const EInvalidOpHashLength: vector<u8> = b"EVERY OPERATION HASH MUST BE EXACTLY 32 BYTES";
#[error]
const EEmptyCommit: vector<u8> = b"A COMMIT OVER NO OPERATIONS HAS NO ROOT";

// === Constants ===

/// The width of a commitment, in bytes. A commit is a hash, so it is constant
/// sized: the concatenation it replaces grew with the number of operations and
/// eventually exceeded the maximum size of a Sui object, at which point the
/// commit that would have drained the backlog could no longer be executed.
const ROOT_LENGTH: u64 = 32;

/// Domain separator for a leaf. Leaves and interior nodes are hashed in disjoint
/// spaces so no leaf can be presented as a subtree, and vice versa.
const LEAF_PREFIX: u8 = 0x00;
/// Domain separator for an interior node.
const NODE_PREFIX: u8 = 0x01;

// === View functions ===

/// The width of a commitment, in bytes.
public fun root_length(): u64 { ROOT_LENGTH }

/// Whether `commit` is a well-formed commitment.
public fun is_valid_root(commit: &vector<u8>): bool {
    commit.length() == ROOT_LENGTH
}

// === Public functions ===

/// Abort unless `commit` is a well-formed commitment.
public fun assert_valid_root(commit: &vector<u8>) {
    assert!(is_valid_root(commit), EInvalidRootLength);
}

/// The commitment over `op_hashes`.
///
/// `op_hashes` is consumed in the order given and is never sorted: the sequence
/// of operations is itself part of what is being attested, so two histories that
/// applied the same operations in a different order must not share a root.
///
/// A level holding an odd number of nodes pairs its last node with itself. The
/// caller supplies the operation hashes, so the iteration count is bounded by the
/// transaction that carries them.
public fun root(op_hashes: &vector<vector<u8>>): vector<u8> {
    assert!(!op_hashes.is_empty(), EEmptyCommit);

    let mut level = vector<vector<u8>>[];
    op_hashes.do_ref!(|op_hash| level.push_back(leaf(op_hash)));

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

// === Private functions ===

/// Hash one operation into a leaf.
fun leaf(op_hash: &vector<u8>): vector<u8> {
    assert!(op_hash.length() == ROOT_LENGTH, EInvalidOpHashLength);

    let mut preimage = vector[LEAF_PREFIX];
    preimage.append(*op_hash);

    hash::sha2_256(preimage)
}

/// Hash two children into their parent.
fun node(left: &vector<u8>, right: &vector<u8>): vector<u8> {
    let mut preimage = vector[NODE_PREFIX];
    preimage.append(*left);
    preimage.append(*right);

    hash::sha2_256(preimage)
}
