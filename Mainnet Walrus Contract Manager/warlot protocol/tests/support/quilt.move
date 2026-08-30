/// A stand-in for a Walrus quilt, and the client procedure that verifies a
/// compaction against one.
///
/// The verification is a *client* procedure and could not be anything else: a
/// quilt's patch index lives inside the quilt and its patch ids are derived from
/// the whole quilt's composition, so Move cannot ask whether a file is inside a
/// blob. It is written here, once, so that the two failures it exists to catch
/// can be exhibited rather than described ,  and so that the claim that its steps
/// are not redundant is a test rather than an assertion in a comment.
///
/// The five steps, and what each one binds:
///
/// ```
/// 1. list the identifiers the new quilt holds
/// 2. read each patch; assert H(bytes) == its tag        bytes  -> tag
/// 3. recompute the file-set root from the tags          tags   -> chain
/// 4. assert every identifier the superseded quilts held bytes are all still
///    appears in step 1                                  present
/// 5. only now delete the superseded blobs
/// ```
///
/// Steps 2 and 3 are a chain of two bindings and neither end is the other's.
/// Step 3 recomputes the root from the **tags**, not from the bytes, which is
/// what leaves room for step 2 to be load-bearing: a quilt whose tags match the
/// chain says nothing about whether the bytes match the tags. Step 4 is over the
/// *previous* generation's identifiers, which is why it can only be run while the
/// superseded blobs are still alive ,  and therefore why deletion is step 5.
#[test_only]
module warlot::quilt;

// === Imports ===

use std::hash;
use warlot::file_set;

// === Structs ===

/// One patch of a quilt.
public struct Patch has copy, drop, store {
    /// The stable identity the naming layer resolves to. Survives a repack; the
    /// `QuiltPatchId` beside it does not, and is a cache rather than an identity.
    identifier: vector<u8>,
    /// The logical path this patch answers to, which is what the file-set root
    /// is taken over.
    path: vector<u8>,
    /// The bytes stored under the identifier.
    bytes: vector<u8>,
    /// The tag Walrus stores beside the patch, set at store time and immutable
    /// thereafter. A substituted patch no longer matches its own tag.
    tag_hash: vector<u8>,
}

/// A quilt: the patches it holds, in the order they were packed.
public struct Quilt has copy, drop, store {
    patches: vector<Patch>,
}

// === Test-only helpers ===

/// A patch whose tag is the hash of its own bytes, as a faithful store produces.
public fun patch(identifier: vector<u8>, path: vector<u8>, bytes: vector<u8>): Patch {
    let tag_hash = hash::sha2_256(bytes);

    Patch { identifier, path, bytes, tag_hash }
}

/// A patch whose bytes were replaced after the tag was written.
///
/// What a substituting compactor produces: the identifier still resolves, the
/// name still points somewhere, and the content is somebody else's choice.
public fun substituted_patch(
    identifier: vector<u8>,
    path: vector<u8>,
    bytes: vector<u8>,
    substitute: vector<u8>,
): Patch {
    let tag_hash = hash::sha2_256(bytes);

    Patch { identifier, path, bytes: substitute, tag_hash }
}

/// A quilt holding `patches`.
public fun new(patches: vector<Patch>): Quilt {
    Quilt { patches }
}

/// This patch's identifier.
public fun patch_identifier(p: &Patch): vector<u8> { p.identifier }

/// This patch's logical path.
public fun patch_path(p: &Patch): vector<u8> { p.path }

/// The tag stored beside this patch.
public fun patch_tag(p: &Patch): vector<u8> { p.tag_hash }

/// How many patches this quilt holds.
public fun patch_count(q: &Quilt): u64 { q.patches.length() }

/// Step 1: every identifier the quilt holds.
public fun list_patches(q: &Quilt): vector<vector<u8>> {
    let mut identifiers = vector<vector<u8>>[];
    q.patches.do_ref!(|p| identifiers.push_back(p.identifier));
    identifiers
}

/// Step 2: whether every patch's bytes hash to the tag stored beside them.
///
/// Catches SUBSTITUTION, and only substitution. It says nothing about what is
/// missing: a quilt holding one faithful patch passes this.
public fun no_substitution(q: &Quilt): bool {
    let mut faithful = true;
    q.patches.do_ref!(|p| {
        if (hash::sha2_256(p.bytes) != p.tag_hash) {
            faithful = false;
        };
    });
    faithful
}

/// Step 3: the file-set root the quilt's tags imply.
///
/// Taken over the **tags** rather than over the bytes, which is the whole reason
/// step 2 exists. A verifier that recomputed this from the bytes would fold the
/// two steps into one and would then have no separate answer to "do these bytes
/// match what was stored".
public fun root_from_tags(q: &Quilt): vector<u8> {
    let mut entries = vector[];
    q.patches.do_ref!(|p| entries.push_back(file_set::new_entry(p.path, p.tag_hash)));
    file_set::root(entries)
}

/// Step 3: whether the quilt's tags reproduce the root the chain holds.
///
/// Catches a quilt the chain never attested to. It says nothing about the bytes,
/// which the tags only claim to describe.
public fun chain_agrees(q: &Quilt, on_chain_root: vector<u8>): bool {
    root_from_tags(q) == on_chain_root
}

/// Step 4: whether every identifier in `superseded_identifiers` is present.
///
/// Catches OMISSION, and only omission. A compaction that quietly drops a file
/// produces a perfectly valid root over the files that remain, so steps 2 and 3
/// both pass on it; this is the only step that has anything to compare the
/// survivors against, and it can only be run while the superseded blobs are still
/// readable.
public fun complete(q: &Quilt, superseded_identifiers: vector<vector<u8>>): bool {
    let present = list_patches(q);
    let mut whole = true;
    superseded_identifiers.do_ref!(|id| {
        if (!present.contains(id)) {
            whole = false;
        };
    });
    whole
}

/// Steps 2, 3 and 4 together, in that order.
///
/// Returned separately rather than as one boolean so a test can show which step
/// caught a failure and, just as importantly, which steps did not.
public fun verify(
    q: &Quilt,
    on_chain_root: vector<u8>,
    superseded_identifiers: vector<vector<u8>>,
): (bool, bool, bool) {
    (
        no_substitution(q),
        chain_agrees(q, on_chain_root),
        complete(q, superseded_identifiers),
    )
}

/// The paths the quilt resolves, in packing order.
public fun paths(q: &Quilt): vector<vector<u8>> {
    let mut out = vector<vector<u8>>[];
    q.patches.do_ref!(|p| out.push_back(p.path));
    out
}

/// The tag beside each patch, positionally matching `paths`.
public fun tags(q: &Quilt): vector<vector<u8>> {
    let mut out = vector<vector<u8>>[];
    q.patches.do_ref!(|p| out.push_back(p.tag_hash));
    out
}
