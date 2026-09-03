/// Holds `Layout`: the receipt a compaction leaves on the config it produced.
///
/// The receipt has to outlive the data it describes. A quilt's own index and its
/// per-patch tags live *inside* the quilt, so deleting generation N destroys the
/// record of what generation N contained ,  and deleting generation N is the
/// whole point of compacting into N+1. Two Merkle roots close that hole for
/// 64 bytes: one over what the new layout holds, one over what it replaces.
///
/// It is constant in the file count by construction. A per-file record would
/// exceed Sui's maximum object size at roughly five thousand files, at which
/// point the config could no longer be built at all; this one is the same size at
/// one file and at six hundred and sixty-six.
module warlot::layout;

// === Imports ===

use warlot::file_set;

// === Errors ===

#[error]
const EInvalidKind: vector<u8> = b"A LAYOUT KIND MUST BE 0 (RAW BLOBS) OR 1 (QUILT)";
#[error]
const EFileCountTooLarge: vector<u8> = b"A LAYOUT MUST DESCRIBE AT MOST 666 FILES";
#[error]
const EInvalidGeneration: vector<u8> = b"A COMPACTION'S GENERATION MUST BE AT LEAST ONE";

// === Constants ===

/// The content under this config is one or more ordinary Walrus blobs.
const KIND_BLOBS: u8 = 0;
/// The content under this config is a single Walrus quilt.
const KIND_QUILT: u8 = 1;

// === Structs ===

/// How the content under one blob config is laid out, and what it replaced.
///
/// `copy, drop, store` and no `key`: it is a field of `BlobConfig`, never an
/// object. Unlike a `FileData` it names no content that has to be accounted for
/// ,  the content is the config's own blobs ,  so it is safe to let it fall out
/// of scope with the config it belongs to.
public struct Layout has copy, drop, store {
    /// `0` raw blobs, `1` a quilt. The flag that says whether this config is the
    /// product of a compaction and how its bytes are addressed.
    kind: u8,
    /// How many repacks deep this content is. Strictly greater than every
    /// generation it supersedes.
    generation: u32,
    /// How many files the layout resolves.
    file_count: u64,
    /// The Merkle root over this layout's `(path, content_hash)` pairs, in
    /// `file_set`'s frozen construction.
    file_set_root: vector<u8>,
    /// The Merkle root over the config ids this layout replaces, in `id_set`'s
    /// construction. Thirty-two zero bytes when it replaces nothing.
    superseded_root: vector<u8>,
    /// How many configs this layout replaces.
    superseded_count: u64,
    /// When the layout was registered, read from the clock the call was given.
    created_at_ms: u64,
}

// === View functions ===

/// The layout kind meaning raw Walrus blobs.
public fun kind_blobs(): u8 { KIND_BLOBS }

/// The layout kind meaning a single Walrus quilt.
public fun kind_quilt(): u8 { KIND_QUILT }

/// The largest number of files one layout may describe.
///
/// The quilt patch cap, and the same number `file_set` bounds a root at ,  which
/// is not a coincidence: a layout the chain cannot recompute a root over is a
/// layout the chain cannot attest to, so the two bounds are one bound.
public fun max_patches(): u64 { file_set::max_file_set() }

/// `0` raw blobs, `1` a quilt.
public fun kind(layout: &Layout): u8 { layout.kind }

/// Whether this layout describes a quilt.
public fun is_quilt(layout: &Layout): bool { layout.kind == KIND_QUILT }

/// How many repacks deep this content is.
public fun generation(layout: &Layout): u32 { layout.generation }

/// How many files this layout resolves.
public fun file_count(layout: &Layout): u64 { layout.file_count }

/// The commitment to this layout's `(path, content_hash)` pairs.
public fun file_set_root(layout: &Layout): vector<u8> { layout.file_set_root }

/// The commitment to the configs this layout replaces.
public fun superseded_root(layout: &Layout): vector<u8> { layout.superseded_root }

/// How many configs this layout replaces.
public fun superseded_count(layout: &Layout): u64 { layout.superseded_count }

/// When this layout was registered.
public fun created_at_ms(layout: &Layout): u64 { layout.created_at_ms }

// === Package functions ===

/// Record one layout.
///
/// Every field is checked here rather than at the call site, so a second entry
/// point onto compaction cannot be built that skips one. The two roots are
/// derived by the caller from state the contract read, never taken from an
/// argument, which is what makes this a receipt rather than a claim.
public(package) fun new(
    kind: u8,
    generation: u32,
    file_count: u64,
    file_set_root: vector<u8>,
    superseded_root: vector<u8>,
    superseded_count: u64,
    created_at_ms: u64,
): Layout {
    assert!(kind == KIND_BLOBS || kind == KIND_QUILT, EInvalidKind);
    assert!(file_count <= max_patches(), EFileCountTooLarge);
    assert!(generation > 0, EInvalidGeneration);
    file_set::assert_valid_root(&file_set_root);
    file_set::assert_valid_root(&superseded_root);

    Layout {
        kind,
        generation,
        file_count,
        file_set_root,
        superseded_root,
        superseded_count,
        created_at_ms,
    }
}

