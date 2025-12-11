module warlot::version;

const VERSION: u64 = 1;

public(package) fun get_version(): u64 {
    VERSION
}

public(package) fun panic_invalid(version: u64) {
     assert!(version == VERSION, 1);
}

public(package) fun is_valid(version: u64): bool {
    version == VERSION
}

