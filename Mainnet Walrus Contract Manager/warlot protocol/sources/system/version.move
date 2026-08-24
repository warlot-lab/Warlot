/// Declares the package version and the gate every public entry point asserts against.
module warlot::version;

// === Constants ===

const VERSION: u64 = 1;

// === View functions ===

/// The version this build of the package was compiled at.
public(package) fun get_version(): u64 {
    VERSION
}

/// Aborts unless `version` matches the package version.
public(package) fun panic_invalid(version: u64) {
    assert!(version == VERSION, 1);
}

/// Whether `version` matches the package version.
public(package) fun is_valid(version: u64): bool {
    version == VERSION
}
