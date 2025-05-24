---
# Warlot Smart Contract Documentation
---

## Overview

Warlot is a decentralized storage management system built on the Sui blockchain. It enables users to register, manage wallets, store and renew blobs (files), track usage data, and interact with dynamic tables for efficient data indexing.

Key features include:

- User registration with wallet creation and metadata initialization
- Blob lifecycle management (add, replace, remove, extend)
- Internal wallet management for deposits, withdrawals, and balance tracking
- Dynamic field usage for scalable and flexible data storage
- Epoch-based state tracking for blobs
- Event emission for key system actions

---

## Modules and Core Components

### 1. `warlot::userstate`

**Purpose:** Manages user-related data including registration, blob management, metadata, and indexing.

#### Structs

- **User**: Stores user identity, owner address, wallet, and metadata.
- **EpochState**: Tracks epoch number and vector index for blobs.
- **DashData**: Aggregates file count and storage size for user statistics.

#### Key Functions

- `create_user(...) -> User`
  Creates a new user with a wallet and registers them in the system.

- `add_blob(user: &mut User, blob_cfg: BlobSettings, epoch: u32)`
  Adds a new blob configuration to a user for a specific epoch, updating the indexing table.

- `remove_blob_from_user(user: &mut User, blob_obj_id: ID) -> BlobSettings`
  Removes a blob configuration from the user, updating the indexer and internal vectors.

- `update_dash_data(user: &mut User, files: u128, storage_size: u128) -> bool`
  Updates user's dashboard data with incremented files and storage usage.

- `reduce_dash_data(user: &mut User, storage_size: u128) -> bool`
  Reduces file count and storage usage for the user.

- `get_mut_obj_list_blob_cfg(user: &mut User, epoch: u32) -> &mut vector<BlobSettings>`
  Access the mutable vector of blob settings for a user at a specific epoch.

- `add_to_indexer(user: &mut User, blob_obj_id: ID, epoch: u32, vector_index: u64)`
  Adds a blob entry to the user’s indexer table.

- `remove_from_indexer(user: &mut User, blob_obj_id: ID, replace: Option<ID>)`
  Removes a blob entry from the indexer, optionally replacing it with another.

---

### 2. `warlot::wallet`

**Purpose:** Manages user wallets and WAL token balances.

#### Structs

- **Wallet**: Holds wallet ID, owner address, creation timestamp, and WAL balance.

#### Key Functions

- `create_wallet(clock: &Clock, ctx: &mut TxContext) -> Wallet`
  Creates a new wallet for a user, initializing balance and emitting creation events.

- `deposit(wallet: &mut Wallet, funds: &mut Coin<WAL>, amount: u64, ctx: &mut TxContext) -> u64`
  Deposits funds into the wallet from an external coin, emits a deposit event.

- `return_balance(wallet: &mut Wallet, coin: Coin<WAL>)`
  Returns coins to the wallet balance.

- `get_balance(wallet: &mut Wallet, ctx: &mut TxContext) -> Coin<WAL>`
  Withdraws all WAL from the wallet as a coin object.

- `has_estimate(wallet: &Wallet, estimate: u64) -> bool`
  Checks if wallet has at least `estimate` amount.

- `get_owner(wallet: &Wallet) -> address`
  Returns the wallet owner's address.

---

### 3. `warlot::tablemain`

**Purpose:** Manages dynamic tables used for indexing blobs and other data structures.

#### Structs

- **Table**: Represents a dynamic table with ID, name, timestamps, and cache references.

#### Key Functions

- `create(name: String, cache_obj: address, cache_file: String, clock: &Clock, ctx: &mut TxContext) -> Table`
  Creates a new table with timestamps.

- `update(table: &mut Table, cache_obj: address, cache_file: String, clock: &Clock)`
  Updates the cache object and file, and refreshes the last updated timestamp.

- `get_name(table: &Table) -> String`
  Returns the name of the table.

---

### 4. Miscellaneous Functions and Modules

- `add_user(system_cfg: &mut SystemConfig, user: User, ctx: &TxContext)`
  Adds a new user to the system configuration, ensuring no duplicate users.

- `get_user_mut(system_cfg: &mut SystemConfig, user: address) -> &mut User`
  Mutable access to a user object.

- `get_user(system_cfg: &SystemConfig, user: address) -> &User`
  Immutable access with user existence check.

- `check_user(system_cfg: &SystemConfig, user: address) -> bool`
  Verifies if a user exists in the system.

- `replace(admin_cap: &mut AdminCap, system_cfg: &mut SystemConfig, old_blob_id: address, blob: Blob, epoch_set: u32, cycle_end: u64, user: address)`
  Replaces an existing blob with a new one, withdrawing the old and storing the new blob.

- `extend_blob(system: &mut System, blob: &mut Blob, payment: &mut Coin<WAL>, new_epoch: u32)`
  Extends the lifetime of a blob with payment.

---

## Data Flow and Typical Usage

1. **User Registration**
   User calls `create_user` providing metadata and keys, which creates the user record and wallet.

2. **Adding Blobs**
   User adds blob settings with `add_blob`, which stores configuration and indexes the blob.

3. **Managing Wallet**
   Deposits and withdrawals handled via `deposit` and `get_balance`.

4. **Blob Lifecycle**
   Blobs can be replaced or extended via `replace` and `extend_blob`. Removing blobs uses `remove_blob_from_user`.

5. **Dashboard Updates**
   File counts and storage sizes are updated via `update_dash_data` and `reduce_dash_data` for usage tracking.

6. **Indexing**
   Dynamic tables maintain blob indices for quick lookup.

---

## Error Codes

- `1`: User does not exist or requested field missing.
- `2`: Blob not deletable or invalid.
- `3`: Unauthorized access (sender mismatch).
- Additional codes should be documented as per your system.

---

## Event Emissions

- **Wallet Created**: Emits on wallet creation.
- **Deposit**: Emits on successful deposit.
- (Add more as you implement further events for blob storage, removal, renewal, etc.)

---
