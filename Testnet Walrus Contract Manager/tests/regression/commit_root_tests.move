/// A commit is a fixed-width root over the operations it attests, not the
/// operations themselves concatenated. The construction is frozen and published,
/// because the service that computes it off chain and the contract that stores it
/// have to land on the same bytes ,  so these vectors, not the description of the
/// algorithm, are what the implementation is held to.
#[test_only]
module warlot::commit_root_tests;

// === Imports ===

use warlot::{commit, file_data};

// === Test-only helpers ===

/// `sha2_256(b"op1")`, as an operation hash arrives from the log.
fun op1(): vector<u8> {
    x"7d3c6b8d51ac8ec79a2adbf98045944f934c1279a57f689cd5ce997fc223b48e"
}

/// `sha2_256(b"op2")`.
fun op2(): vector<u8> {
    x"2465a128ca302ed5d3a3a2c232fa6895f02c62fb632deb33193ea12d4224dba7"
}

/// `sha2_256(b"op3")`.
fun op3(): vector<u8> {
    x"5f34e666d53c0fc5ab0d0266a94e8df043084e6c13bd8e48bf519ad7b562a870"
}

#[test]
fun vectors() {
    assert!(
        commit::root(&vector[op1()]) ==
            x"690f5b1479190da0d494b1b813f3a0d67a087e7f968451d01bd50c5218750bcf",
        0,
    );
    assert!(
        commit::root(&vector[op1(), op2()]) ==
            x"4b10fba8cae3423c4999ca7516223b79f6ae73148d7aa87145c82115f9a3bbae",
        1,
    );
    // Three operations exercise the odd-level rule, which one and two do not.
    assert!(
        commit::root(&vector[op1(), op2(), op3()]) ==
            x"30b053da8def73ef2fab82f86514ff5943be50ff336c2251201466cd0d1d0b95",
        2,
    );

    // And a root is always exactly one commitment wide, however many operations
    // went into it.
    assert!(commit::root(&vector[op1(), op2(), op3()]).length() == commit::root_length(), 3);
}

#[test]
fun order_matters() {
    // The operation log is a sequence, not a set: two histories that applied the
    // same changes in a different order are not the same history, so a root that
    // sorted its input would attest to one that never happened.
    assert!(
        commit::root(&vector[op1(), op2(), op3()]) !=
            commit::root(&vector[op3(), op2(), op1()]),
        0,
    );
}

#[test]
#[expected_failure(abort_code = warlot::commit::EInvalidRootLength)]
fun fixed_width() {
    // A revision cannot carry anything but a commitment ,  which is what stops the
    // field growing with the number of operations until the object no longer fits.
    //
    // Unpacked rather than discarded, because a revision has no `drop`: the
    // compiler refuses to let one fall out of scope even in a test.
    let (_, _, _) = file_data::destroy(
        file_data::create_file_data(b"not a root", @0xA11CE, object::id_from_address(@0x1)),
    );
}

#[test]
#[expected_failure(abort_code = warlot::commit::EInvalidOpHashLength)]
fun operation_hashes_are_fixed_width_too() {
    let _ = commit::root(&vector[b"short"]);
}

#[test]
#[expected_failure(abort_code = warlot::commit::EEmptyCommit)]
fun no_operations_has_no_root() {
    let _ = commit::root(&vector<vector<u8>>[]);
}
