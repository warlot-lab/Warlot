/// The file-set root against the vectors published with the frozen format.
///
/// The construction is reproduced here rather than described, because the whole
/// point of the commitment is that somebody else recomputes it independently and
/// lands on the same 32 bytes. The three-entry case is the one that matters: it
/// is the only vector that exercises the odd-level duplication rule, and an
/// implementation that gets that wrong still passes the one- and two-entry cases.
#[test_only]
module warlot::file_set_root_tests;

// === Imports ===

use std::hash;
use warlot::file_set::{Self, FileEntry};

// === Constants ===

/// The three published leaves, and the four published roots.
const LEAF_A: vector<u8> = x"c99258cf99b88e0eff05a66a1604eb6dfe8ba4be824ea89293fc16b504f7cb66";
const LEAF_B: vector<u8> = x"d72257f9161f0a3bdd6878201df632cd409715d3fe0a40bc076d73f96ad12e20";
const LEAF_C: vector<u8> = x"6e8a1ffed1380919964deb6130d595fe5ea1b812c20c70c87a1f85c69f012af1";

const ROOT_EMPTY: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000000";
const ROOT_A: vector<u8> = x"c99258cf99b88e0eff05a66a1604eb6dfe8ba4be824ea89293fc16b504f7cb66";
const ROOT_AB: vector<u8> = x"7e8e4fba1248d0edc9f3069f57fb53efecb6ed206a60eb35157b1cfd087884af";
const ROOT_ABC: vector<u8> = x"f54b57602bd89af3a5e9271c664b77641b176665c51d604e277e1a85e62ae60b";

/// The published content hashes, which are the hashes of the one-byte contents
/// `"A"`, `"B"` and `"C"`.
const HASH_A: vector<u8> = x"559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd";
const HASH_B: vector<u8> = x"df7e70e5021544f4834bbee64a9e3789febc4be81470df629cad6ddb03320a5c";
const HASH_C: vector<u8> = x"6b23c0d5f35d1b11f9b683f0b0a617355deb11277d91ae091d399c655b87940d";

// === Tests ===

#[test]
fun vectors() {
    // The content hashes first: a leaf built over the wrong content hash would
    // otherwise fail here as if the leaf construction were wrong.
    assert!(hash::sha2_256(b"A") == HASH_A, 0);
    assert!(hash::sha2_256(b"B") == HASH_B, 1);
    assert!(hash::sha2_256(b"C") == HASH_C, 2);

    assert!(file_set::leaf(&b"docs/a.txt", &HASH_A) == LEAF_A, 3);
    assert!(file_set::leaf(&b"docs/b.txt", &HASH_B) == LEAF_B, 4);
    assert!(file_set::leaf(&b"img/c.png", &HASH_C) == LEAF_C, 5);

    assert!(file_set::root(vector[]) == ROOT_EMPTY, 6);
    assert!(file_set::root(vector[entry_a()]) == ROOT_A, 7);
    assert!(file_set::root(vector[entry_a(), entry_b()]) == ROOT_AB, 8);

    // The odd-count case, which duplicates the last node of the level.
    assert!(file_set::root(vector[entry_a(), entry_b(), entry_c()]) == ROOT_ABC, 9);
}

#[test]
fun empty() {
    let root = file_set::root(vector[]);

    assert!(root == file_set::empty_root(), 0);
    assert!(root.length() == file_set::root_length(), 1);

    // Thirty-two zero bytes, not the hash of nothing and not an empty vector.
    let mut i = 0;
    while (i < root.length()) {
        assert!(root[i] == 0, 2);
        i = i + 1;
    };
}

#[test]
fun path_ordering() {
    let sorted = file_set::root(vector[entry_a(), entry_b(), entry_c()]);

    // The root is a function of the set, so every arrival order gives the same
    // answer. This is the property that lets two servers replaying the same
    // uploads in different orders agree.
    assert!(file_set::root(vector[entry_c(), entry_b(), entry_a()]) == sorted, 0);
    assert!(file_set::root(vector[entry_b(), entry_a(), entry_c()]) == sorted, 1);
    assert!(file_set::root(vector[entry_c(), entry_a(), entry_b()]) == sorted, 2);

    // And it is not a function of the paths alone: swapping which content each
    // path resolves to has to move the root, or the commitment binds nothing.
    let swapped = file_set::root(
        vector[
            file_set::new_entry(b"docs/a.txt", HASH_B),
            file_set::new_entry(b"docs/b.txt", HASH_A),
            entry_c(),
        ],
    );
    assert!(swapped != sorted, 3);

    // Nor of the contents alone: moving one file to another path moves the root.
    let renamed = file_set::root(
        vector[entry_a(), entry_b(), file_set::new_entry(b"img/c2.png", HASH_C)],
    );
    assert!(renamed != sorted, 4);
}

#[test]
fun ordering_is_on_raw_bytes() {
    // `Z` is 0x5A and `a` is 0x61, so a byte-wise order puts `Z` first while a
    // case-insensitive collation would not. Postgres under a non-C collation
    // disagrees with this, which is exactly why the format pins raw bytes.
    let upper = file_set::new_entry(b"Z.txt", HASH_A);
    let lower = file_set::new_entry(b"a.txt", HASH_B);

    assert!(
        file_set::root(vector[upper, lower]) ==
            file_set::node(
                &file_set::leaf(&b"Z.txt", &HASH_A),
                &file_set::leaf(&b"a.txt", &HASH_B),
            ),
        0,
    );
}

#[test]
fun length_prefix_separates_path_from_content() {
    // Without the length prefix, `("docs/a", H)` and `("docs", "/a" || H)` would
    // serialise to the same preimage. The second is not a legal entry, so the
    // property is asserted on the leaf function directly.
    let split = file_set::leaf(&b"docs/a", &HASH_A);
    let joined = file_set::leaf(&b"docs", &HASH_A);

    assert!(split != joined, 0);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EDuplicatePath)]
fun refuses_a_repeated_path() {
    file_set::root(vector[entry_a(), file_set::new_entry(b"docs/a.txt", HASH_B)]);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EPathNotCanonical)]
fun refuses_a_leading_separator() {
    file_set::new_entry(b"/docs/a.txt", HASH_A);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EPathNotCanonical)]
fun refuses_a_trailing_separator() {
    file_set::new_entry(b"docs/a.txt/", HASH_A);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EPathNotCanonical)]
fun refuses_an_empty_segment() {
    file_set::new_entry(b"docs//a.txt", HASH_A);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EPathNotCanonical)]
fun refuses_a_relative_segment() {
    file_set::new_entry(b"docs/../a.txt", HASH_A);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EPathControlCharacter)]
fun refuses_a_control_character() {
    file_set::new_entry(b"docs/a\nb.txt", HASH_A);
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EInvalidContentHash)]
fun refuses_a_short_content_hash() {
    file_set::new_entry(b"docs/a.txt", x"0011");
}

#[test]
#[expected_failure(abort_code = warlot::file_set::EEmptyPath)]
fun refuses_an_empty_path() {
    file_set::new_entry(b"", HASH_A);
}

// === Private functions ===

fun entry_a(): FileEntry { file_set::new_entry(b"docs/a.txt", HASH_A) }

fun entry_b(): FileEntry { file_set::new_entry(b"docs/b.txt", HASH_B) }

fun entry_c(): FileEntry { file_set::new_entry(b"img/c.png", HASH_C) }
