/// The receipt a compaction leaves, and the two commitments it carries.
///
/// A `Layout` has to be constant in the file count or the design fails at scale
/// rather than in principle: a per-file record would pass Sui's maximum object
/// size at roughly five thousand files, at which point the config could no longer
/// be built at all. That is measured here, not assumed.
///
/// The superseded-set construction is pinned against vectors computed from the
/// written rules before any of this was built, the way `file_set`'s were.
#[test_only]
module warlot::layout_tests;

// === Imports ===

use sui::bcs;
use warlot::{file_set, id_set, layout};

// === Constants ===

/// The BCS width of a `Layout`: 1 kind + 4 generation + 8 file count + 33 root +
/// 33 root + 8 superseded count + 8 timestamp.
const LAYOUT_BCS_BYTES: u64 = 95;

// === Test-only helpers ===

/// `sha2_256("A")`, and the first of the three ids the vectors are taken over.
fun id_a(): ID {
    object::id_from_bytes(
        x"559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd",
    )
}

/// `sha2_256("B")`. Sorts last of the three.
fun id_b(): ID {
    object::id_from_bytes(
        x"df7e70e5021544f4834bbee64a9e3789febc4be81470df629cad6ddb03320a5c",
    )
}

/// `sha2_256("C")`. Sorts second.
fun id_c(): ID {
    object::id_from_bytes(
        x"6b23c0d5f35d1b11f9b683f0b0a617355deb11277d91ae091d399c655b87940d",
    )
}

/// A layout over `file_count` files superseding `superseded_count` configs.
fun sized(file_count: u64, superseded_count: u64): layout::Layout {
    layout::new(
        layout::kind_quilt(),
        1,
        file_count,
        file_set::empty_root(),
        id_set::empty_root(),
        superseded_count,
        1_000,
    )
}

// === Tests ===

#[test]
/// The superseded-set root, against vectors computed from the written rules.
///
/// The leaves carry `0x02` rather than the `0x00` the other two constructions
/// use, because an id is exactly as wide as an operation hash and a shared prefix
/// would make a root over a set of ids byte-identical to a commit over the same
/// values in the same order.
fun superseded_root_matches_the_vectors() {
    assert!(
        id_set::leaf(&id_a())
            == x"10db190a64af4a4158e0aa8567952a731aff3827e175c6e190246f3f2a4761b8",
        0,
    );
    assert!(
        id_set::leaf(&id_b())
            == x"2d261e26ed5741759d68b371cecc45695531bbaefa0277271baf14a4844fb4fd",
        1,
    );
    assert!(
        id_set::leaf(&id_c())
            == x"e680b41655206ff60b20e1b3304eff634006671a65d640532468462f4c394132",
        2,
    );

    assert!(
        id_set::root(vector[])
            == x"0000000000000000000000000000000000000000000000000000000000000000",
        3,
    );
    assert!(
        id_set::root(vector[id_a()])
            == x"10db190a64af4a4158e0aa8567952a731aff3827e175c6e190246f3f2a4761b8",
        4,
    );
    assert!(
        id_set::root(vector[id_a(), id_b()])
            == x"f43c1b9481a3fc458dea6a940fdff48666d726dc4f0a6f6ea6cb49bf1d7ee879",
        5,
    );
    // Three entries exercise the odd-level duplication rule and the sort in one
    // go: A sorts first, C second and B last, so a construction that folded them
    // in the order given would land somewhere else.
    assert!(
        id_set::root(vector[id_a(), id_b(), id_c()])
            == x"ed11bb3b80fe70343318515f0be1f931ed330d2caddfc118b26bae5c23b59fa7",
        6,
    );
}

#[test]
/// The root is a function of the set, so the order the caller names it in cannot
/// move it.
fun superseded_root_is_order_independent() {
    let ascending = id_set::root(vector[id_a(), id_c(), id_b()]);
    let descending = id_set::root(vector[id_b(), id_c(), id_a()]);
    let shuffled = id_set::root(vector[id_c(), id_a(), id_b()]);

    assert!(ascending == descending, 0);
    assert!(ascending == shuffled, 1);
}

#[test]
#[expected_failure(abort_code = warlot::id_set::EDuplicateId)]
/// A set that named one predecessor twice would have two leaves for it and a
/// count beside the root that disagreed with the tree.
fun superseded_root_refuses_a_repeat() {
    id_set::root(vector[id_a(), id_b(), id_a()]);
}

#[test]
/// The file-set root the layout carries is s7's frozen construction, unchanged.
fun file_set_root_still_matches_its_vectors() {
    let a = file_set::new_entry(
        b"docs/a.txt",
        x"559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd",
    );
    let b = file_set::new_entry(
        b"docs/b.txt",
        x"df7e70e5021544f4834bbee64a9e3789febc4be81470df629cad6ddb03320a5c",
    );
    let c = file_set::new_entry(
        b"img/c.png",
        x"6b23c0d5f35d1b11f9b683f0b0a617355deb11277d91ae091d399c655b87940d",
    );

    assert!(
        file_set::root(vector[a, b, c])
            == x"f54b57602bd89af3a5e9271c664b77641b176665c51d604e277e1a85e62ae60b",
        0,
    );
}

#[test]
/// The receipt is the same size at one file and at six hundred and sixty-six.
///
/// Measured against BCS rather than reasoned about from the field list, because
/// the property that matters is what the chain bills for.
fun constant_size() {
    let one = bcs::to_bytes(&sized(1, 1)).length();
    let many = bcs::to_bytes(&sized(layout::max_patches(), id_set::max_id_set())).length();
    let middling = bcs::to_bytes(&sized(400, 37)).length();

    assert!(one == many, 0);
    assert!(one == middling, 1);
    assert!(one == LAYOUT_BCS_BYTES, 2);
}

#[test]
/// No accepted flag exists on the receipt.
///
/// A boolean anywhere in the struct would be one more byte, and the width is
/// exactly the seven fields the design names. This is the shape half of the
/// claim; `compaction_tests::no_state_machine` is the behavioural half.
fun no_flag_fits_in_the_receipt() {
    let bytes = bcs::to_bytes(&sized(1, 1));

    assert!(bytes.length() == LAYOUT_BCS_BYTES, 0);
    assert!(1 + 4 + 8 + 33 + 33 + 8 + 8 == LAYOUT_BCS_BYTES, 1);
}

#[test]
#[expected_failure(abort_code = warlot::layout::EInvalidKind)]
fun kind_must_be_known() {
    layout::new(2, 1, 1, file_set::empty_root(), id_set::empty_root(), 1, 0);
}

#[test]
#[expected_failure(abort_code = warlot::layout::EInvalidGeneration)]
/// Generation zero is the floor an uncompacted config reports, so a compaction
/// that claimed it would not be advancing on anything.
fun generation_starts_at_one() {
    layout::new(
        layout::kind_quilt(),
        0,
        1,
        file_set::empty_root(),
        id_set::empty_root(),
        1,
        0,
    );
}

#[test]
#[expected_failure(abort_code = warlot::layout::EFileCountTooLarge)]
/// The layout's bound and `file_set`'s are one bound: a layout the chain cannot
/// recompute a root over is a layout it cannot attest to.
fun file_count_is_bounded_by_the_patch_cap() {
    layout::new(
        layout::kind_quilt(),
        1,
        layout::max_patches() + 1,
        file_set::empty_root(),
        id_set::empty_root(),
        1,
        0,
    );
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EInvalidRootLength)]
fun roots_must_be_well_formed() {
    layout::new(layout::kind_quilt(), 1, 1, b"short", id_set::empty_root(), 1, 0);
}
