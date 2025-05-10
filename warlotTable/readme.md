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
