/// Declares the package version and the gate every public entry point asserts against.
module warlot::version;

// === Errors ===

#[error]
const EWrongPackageVersion: vector<u8> = b"THIS OBJECT IS NOT AT THE PACKAGE VERSION";

// === Constants ===

const VERSION: u64 = 1;

// === View functions ===

/// The version this build of the package was compiled at.
public(package) fun get_version(): u64 {
    VERSION
}

/// Aborts unless `version` matches the package version.
public(package) fun panic_invalid(version: u64) {
    assert!(version == VERSION, EWrongPackageVersion);
}
