# 🧠 Warlottable Smart Contract

This Sui Move smart contract allows you to manage users and their associated tables containing blob metadata (`blob_id` and `blob_sui_obj_id`). It is useful for systems that store files externally and need to reference or update blob storage identifiers per user and table.

---

## 🔧 Features

- **Initialize the contract** with system configuration and admin rights.
- **Create users** along with API credentials and a placeholder object for dynamic table mappings.
- **Create tables** for users with associated blob IDs.
- **Update tables** to modify blob metadata as needed.

---

## 🧱 Core Data Structures

### ⚓ Admincap

```rust
 ┌──                                                                                                       │
│  │ ObjectID: 0x50aa954eab867d617b9d585b1eecf16e29a81681633f4a35eb77cabe5de85372                            │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                              │
│  │ Owner: Account Address ( 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd )           │
│  │ ObjectType: 0x4a6651ae46511bd1a79a5d750ecfa0dc7ca385145daf8ab67d9786ad13fe127f::warlottable::AdminCap   │
│  │ Version: 423548363                                                                                      │
│  │ Digest: 3MeBw7yPqJamGHa13nyB5YEqbVC42XQpRcZ93yw8w33G                                                    │
│  └──                                                                                                       │
```

### 🛞Systemcfg

```rust
 ┌──                                                                                                       │
│  │ ObjectID: 0xf4a8a88456e8491bb2d26743b59c15c46ef13467e1c8a9ec047ad9e6d6235fd1                            │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                              │
│  │ Owner: Shared( 423548363 )                                                                              │
│  │ ObjectType: 0x4a6651ae46511bd1a79a5d750ecfa0dc7ca385145daf8ab67d9786ad13fe127f::warlottable::SystemCfg  │
│  │ Version: 423548363                                                                                      │
│  │ Digest: AC2NxLNSgpNC7goeJybvpTuL8FKsRTMQQBXLFjMi2svU                                                    │
│  └──                                                                                                       │
```

## 🚀🚀PackageInfo

```rust
  ┌──                                                                                                       │
│  │ PackageID: 0x4a6651ae46511bd1a79a5d750ecfa0dc7ca385145daf8ab67d9786ad13fe127f                           │
│  │ Version: 1                                                                                              │
│  │ Digest: AcRiyDdU4xA8dRX43B331FvzM2M8sHwxiSQo9z89zzKf                                                    │
│  │ Modules: warlottable                                                                                    │
│  └──                                                                                                       │
```

---

### ⚙️ old SystemCfg

```rust
│  ┌──                                                                                                       │
│  │ ObjectID: 0xc8ebbb3a981aa1f3cee0827b3c434f9e45ee7d1b0de3e39bedf6cef976ce54c7                            │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                              │
│  │ Owner: Shared( 418879264 )                                                                              │
│  │ ObjectType: 0x780c6fadcfbb8709beaa2b6f30b3796782f720100729d628df04d6428a70da41::warlottable::SystemCfg  │
│  │ Version: 418879264                                                                                      │
│  │ Digest: 6pJvedNM9PfdXwjsnmEkYeJbmMHpKm5FFw9UzRCzy16D                                                    │
│  └──

```

### 🎫old AdminCap

```rust
┌──                                                                                                          │
│  │ ObjectID: 0xf84579c2cd6949eccf96e9ee23a7fb2bbfed402cebf727606ee5dc87ef34f0af                            │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                              │
│  │ Owner: Account Address ( 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd )           │
│  │ ObjectType: 0x780c6fadcfbb8709beaa2b6f30b3796782f720100729d628df04d6428a70da41::warlottable::AdminCap   │
│  │ Version: 418879264                                                                                      │
│  │ Digest: 2X63ZwYsG5VYbwvonHZWuSnvs5HwTneKRLng5C2KqPDD                                                    │
│  └──

```

## 🚀🚀old PackageInfo

```rust
│ Published Objects:                                                                                         │
│  ┌──                                                                                                       │
│  │ PackageID: 0x780c6fadcfbb8709beaa2b6f30b3796782f720100729d628df04d6428a70da41                           │
│  │ Version: 1                                                                                              │
│  │ Digest: CPXe5VJ7yc6xzKBa193FYVaPtQhhRAvQPufFbyogHgAV                                                    │
│  │ Modules: warlottable                                                                                    │
│  └──                                                                                                       │
```

### `SystemCfg`

Holds global configuration data:

```move
struct SystemCfg {
  id: UID,
  length_users: u64,
  tables: u64
}
```

### `AdminCap`

Used to authorize actions:

```move
struct AdminCap {
  id: UID,
  minter: address
}
```

### `User`

Holds a user's address, API key, URL, and placeholder object:

```move
struct User {
  id: UID,
  user: address,
  api_key: String,
  api_url: String,
  user_place_holder_id: ID,
}
```

### `UserPlaceHolder`

Used to dynamically attach tables to each user:

```move
struct UserPlaceHolder {
  id: UID,
  user: address,
}
```

### `TableSet`

Represents a table's metadata:

```move
struct TableSet {
  id: UID,
  blob_id: String,
  blob_sui_obj_id: String,
}
```

---

## 🛠️ Functions and Usage

### 1. `init(ctx: &mut TxContext)`

Initializes the system:

- Creates a shared `SystemCfg` object.
- Creates and transfers the `AdminCap` to the deployer.

---

### 2. `create_user(...)`

Registers a new user with API credentials:

```move
create_user(
  admin_cap: &mut AdminCap,
  system_cfg: &mut SystemCfg,
  user: address,
  api_key: String,
  api_url: String,
  ctx: &mut TxContext
)
```

✅ Adds a `User` and a `UserPlaceHolder` linked via dynamic fields.

---

### 3. `create_table(...)`

Adds a new table (with blob ID & object ID) under a user:

```move
create_table(
  admin_cap: &mut AdminCap,
  system_cfg: &mut SystemCfg,
  user: address,
  table_name: String,
  blob_id: String,
  blob_sui_obj_id: String,
  ctx: &mut TxContext
)
```

---

### 4. `update_table(...)`

Replaces an existing table's blob metadata:

```move
update_table(
  admin_cap: &mut AdminCap,
  system_cfg: &mut SystemCfg,
  user: address,
  table_name: String,
  blob_id: String,
  blob_sui_obj_id: String
)
```

---

## 🗂️ Use Case Flow

1. **Deploy** the module and call `init()` once.
2. **Admin** uses `create_user(...)` to register users and store their API info.
3. **Admin** uses `create_table(...)` to attach a blob metadata set under a named table.
4. **When updating**, call `update_table(...)` with the new blob details.

---

## 🔐 Blob Authentication

Each user has:

- `api_key`
- `api_url`

These are stored with the user object and can be referenced externally to authenticate or validate blob usage.

---

## 📌 Notes

- Ensure you have access to the `AdminCap` for all operations.
- Table names must be unique per user.
- Dynamic object fields are used to manage per-user table mappings.

---
