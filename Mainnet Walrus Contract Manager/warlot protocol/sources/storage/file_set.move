/// Defines the commitment that binds logical paths to the content they resolve
/// to: a Merkle root over `(path, content_hash)` pairs.
///
/// Names live off chain, where they are cheap, searchable and free to change.
/// The *binding* between a name and its bytes does not: if
/// `project/bucket/config.json -> blob X` were recorded only in an operator's
/// database, the operator would decide which content answers to which path, and
/// a user could verify content only by hashes they had independently
/// remembered. One 32-byte root commits to the whole mapping, so anyone can
/// recompute it from what they believe they stored and hold it against the
/// chain.
///
/// The construction is frozen. It is reproduced against published test vectors
/// rather than inferred, because an auditor recomputing it off chain has to land
/// on the same bytes, and any ambiguity here reads as tampering rather than as a
/// formatting difference.
module warlot::file_set;

// === Imports ===

use std::hash;

// === Errors ===

#[error]
const EInvalidContentHash: vector<u8> = b"A CONTENT HASH MUST BE EXACTLY 32 BYTES";
#[error]
const EInvalidRootLength: vector<u8> = b"A FILE SET ROOT MUST BE EXACTLY 32 BYTES";
#[error]
const EEmptyPath: vector<u8> = b"A PATH MUST NOT BE EMPTY";
#[error]
const EPathTooLong: vector<u8> = b"A PATH MUST BE AT MOST 1024 BYTES";
#[error]
const EPathNotCanonical: vector<u8> =
    b"A PATH MUST HAVE NO LEADING, TRAILING OR REPEATED SEPARATOR AND NO RELATIVE SEGMENT";
#[error]
const EPathControlCharacter: vector<u8> = b"A PATH MUST CARRY NO CONTROL CHARACTER";
#[error]
const EDuplicatePath: vector<u8> = b"A FILE SET MUST NOT NAME THE SAME PATH TWICE";
#[error]
const EFileSetTooLarge: vector<u8> = b"A FILE SET MUST HOLD AT MOST 666 ENTRIES";
#[error]
const EPathsNotAscending: vector<u8> =
    b"THESE PATHS MUST ARRIVE IN ASCENDING BYTE ORDER, WITH NO REPEAT";

// === Constants ===

/// The width of a root and of a content hash, in bytes.
const ROOT_LENGTH: u64 = 32;

/// Domain separator for a leaf. Leaves and interior nodes are hashed in disjoint
/// spaces so that no leaf can be presented as a subtree, and no subtree as a
/// leaf. RFC 6962's separation, and it is load-bearing rather than decorative.
const LEAF_PREFIX: u8 = 0x00;
/// Domain separator for an interior node.
const NODE_PREFIX: u8 = 0x01;

/// The path separator. Nothing else is one.
const SEPARATOR: u8 = 0x2F;
/// The ASCII full stop, which cannot stand alone as a segment.
const DOT: u8 = 0x2E;
/// The highest control character below the printable range.
const LAST_CONTROL: u8 = 0x1F;
/// Delete, the one control character above the printable range.
const DELETE: u8 = 0x7F;

/// The longest path the commitment will accept, in bytes after encoding.
const MAX_PATH_LENGTH: u64 = 1024;

/// The largest set one root may be taken over.
///
/// Matched to the number of patches a Walrus quilt holds, which is the largest
/// set the protocol ever commits to in one place. The bound is also what keeps
/// the ordering pass affordable: entries arrive in the caller's order and are
/// sorted here, and the sort is quadratic in the entry count.
const MAX_FILE_SET: u64 = 666;

// === Structs ===

/// One path and the hash of the bytes it resolves to.
public struct FileEntry has copy, drop, store {
    /// The logical path, UTF-8, with no leading or trailing separator.
    path: vector<u8>,
    /// The hash of the content, as 32 raw bytes rather than as hex.
    content_hash: vector<u8>,
}

// === Public functions ===

/// Pair `path` with the content it resolves to.
///
/// The path is checked here rather than normalised. Two callers who disagree
/// about whether `docs//a.txt` and `docs/a.txt` are the same path would compute
/// different roots for the same files, so a path that is not already canonical
/// is refused instead of being quietly repaired.
///
/// Unicode normalisation is the one canonicalisation rule this cannot enforce:
/// NFC is not decidable in Move at any sensible cost, and it is the caller's to
/// apply before the bytes arrive.
public fun new_entry(path: vector<u8>, content_hash: vector<u8>): FileEntry {
    assert_canonical_path(&path);
    assert!(content_hash.length() == ROOT_LENGTH, EInvalidContentHash);

    FileEntry { path, content_hash }
}

/// Hash one `(path, content_hash)` pair into a leaf.
///
/// The length prefix on the path is what stops `("docs/a", H)` and
/// `("docs", "/a" || H)` from serialising to the same bytes.
public fun leaf(path: &vector<u8>, content_hash: &vector<u8>): vector<u8> {
    assert!(content_hash.length() == ROOT_LENGTH, EInvalidContentHash);

    let mut preimage = vector[LEAF_PREFIX];
    preimage.append(u32_be(path.length()));
    preimage.append(*path);
    preimage.append(*content_hash);

    hash::sha2_256(preimage)
}

/// The commitment over `entries`.
///
/// `entries` is taken by value because the root is a function of the *set*: the
/// entries are sorted here by raw path bytes, so two servers that replayed the
/// same uploads in a different order agree. This is the difference from
/// `commit::root`, whose input is a *sequence* and is never reordered, and it is
/// why the two constructions stay separate functions.
///
/// A level holding an odd number of nodes pairs its last node with itself. The
/// empty set has a root, unlike a commit over no operations: a scope holding no
/// files is a state the chain has to be able to attest to.
public fun root(mut entries: vector<FileEntry>): vector<u8> {
    assert!(entries.length() <= MAX_FILE_SET, EFileSetTooLarge);

    if (entries.is_empty()) {
        return empty_root()
    };

    sort_by_path(&mut entries);
    assert_no_duplicate_path(&entries);

    let mut level = vector<vector<u8>>[];
    entries.do_ref!(|entry| level.push_back(leaf(&entry.path, &entry.content_hash)));

    // Each pass halves the level, and the level starts bounded by `MAX_FILE_SET`.
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

/// Hash two children into their parent.
///
/// Public alongside `leaf` so that a holder of one file can check it against the
/// root on chain by folding an audit path, without being handed every other path
/// in the set.
public fun node(left: &vector<u8>, right: &vector<u8>): vector<u8> {
    let mut preimage = vector[NODE_PREFIX];
    preimage.append(*left);
    preimage.append(*right);

    hash::sha2_256(preimage)
}

/// Abort unless `file_set_root` is a well-formed commitment.
public fun assert_valid_root(file_set_root: &vector<u8>) {
    assert!(file_set_root.length() == ROOT_LENGTH, EInvalidRootLength);
}

/// Abort unless `paths` is already in the order `root` folds them in.
///
/// `root` sorts, so it accepts any order and produces the same commitment ,  but
/// the sort is insertion sort and therefore quadratic in the entry count, and
/// measured against the Move test runner's execution bound a set of 666 entries
/// in arbitrary order does not finish while the same 666 already in order does.
/// A caller that has to supply the order anyway is the cheaper side of that
/// trade, so the one path that commits to a full quilt asks for it and checks it
/// here in one pass.
///
/// It is also what makes an announcement of the set canonical: an event carrying
/// the caller's order beside a root over the sorted order leaves a consumer to
/// re-derive which is which.
public fun assert_ascending_paths(paths: &vector<vector<u8>>) {
    let length = paths.length();
    let mut i = 1;

    while (i < length) {
        assert!(before(&paths[i - 1], &paths[i]), EPathsNotAscending);
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

/// The width of a root, in bytes.
public fun root_length(): u64 { ROOT_LENGTH }

/// The largest set one root may be taken over.
public fun max_file_set(): u64 { MAX_FILE_SET }

/// The logical path this entry names.
public fun entry_path(entry: &FileEntry): &vector<u8> { &entry.path }

/// The hash of the content this entry's path resolves to.
public fun entry_content_hash(entry: &FileEntry): &vector<u8> { &entry.content_hash }

// === Private functions ===

/// `n` as four big-endian bytes. Bounded by `MAX_PATH_LENGTH`, so it always fits.
fun u32_be(n: u64): vector<u8> {
    vector[
        (((n >> 24) & 0xFF) as u8),
        (((n >> 16) & 0xFF) as u8),
        (((n >> 8) & 0xFF) as u8),
        ((n & 0xFF) as u8),
    ]
}

/// Abort unless `path` is already in the canonical form the leaves are taken over.
fun assert_canonical_path(path: &vector<u8>) {
    let length = path.length();
    assert!(length > 0, EEmptyPath);
    assert!(length <= MAX_PATH_LENGTH, EPathTooLong);

    assert!(path[0] != SEPARATOR, EPathNotCanonical);
    assert!(path[length - 1] != SEPARATOR, EPathNotCanonical);

    // One pass over the bytes, closing each segment at the separator that ends
    // it and at the end of the path. Bounded by `MAX_PATH_LENGTH`.
    let mut segment_start = 0;
    let mut i = 0;
    while (i < length) {
        let byte = path[i];

        assert!(byte > LAST_CONTROL && byte != DELETE, EPathControlCharacter);

        if (byte == SEPARATOR) {
            assert_segment(path, segment_start, i);
            segment_start = i + 1;
        };

        i = i + 1;
    };

    assert_segment(path, segment_start, length);
}

/// Abort unless `path[from, to)` is a segment a canonical path may carry.
fun assert_segment(path: &vector<u8>, from: u64, to: u64) {
    // An empty segment is a repeated separator, which the leading and trailing
    // checks do not catch in the middle of a path.
    assert!(to > from, EPathNotCanonical);

    let length = to - from;
    if (length > 2) return;

    let dot_only = path[from] == DOT && (length == 1 || path[from + 1] == DOT);
    assert!(!dot_only, EPathNotCanonical);
}

/// Order `entries` ascending on raw path bytes.
///
/// Insertion sort: the set is bounded at `MAX_FILE_SET`, the input is very often
/// already close to ordered, and a comparison here is a byte-wise walk over two
/// paths rather than a machine word.
fun sort_by_path(entries: &mut vector<FileEntry>) {
    let length = entries.length();
    let mut i = 1;

    while (i < length) {
        let mut j = i;
        while (j > 0 && before(&entries[j].path, &entries[j - 1].path)) {
            entries.swap(j, j - 1);
            j = j - 1;
        };
        i = i + 1;
    };
}

/// Abort if two entries name the same path.
///
/// Checked after ordering, so equal paths are adjacent. A set that named one
/// path twice would have two leaves for it and no defined answer to what that
/// path resolves to.
fun assert_no_duplicate_path(entries: &vector<FileEntry>) {
    let length = entries.length();
    let mut i = 1;

    while (i < length) {
        assert!(entries[i].path != entries[i - 1].path, EDuplicatePath);
        i = i + 1;
    };
}

/// Whether `a` sorts strictly before `b` on raw bytes.
fun before(a: &vector<u8>, b: &vector<u8>): bool {
    let a_length = a.length();
    let b_length = b.length();
    let shortest = if (a_length < b_length) a_length else b_length;

    let mut i = 0;
    while (i < shortest) {
        if (a[i] != b[i]) {
            return a[i] < b[i]
        };
        i = i + 1;
    };

    a_length < b_length
}
