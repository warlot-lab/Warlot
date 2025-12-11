# Warlot Protocol Technical Documentation

## 1\. Protocol Overview

Warlot is a decentralized storage management protocol built on the Sui blockchain. It serves as an orchestration layer for the Walrus file system, providing user identity management, multi-currency financial infrastructure, and automated storage renewal cycles.

The protocol operates through a singleton `SystemConfig` shared object that indexes users and manages a central financial `Vault`. Users possess distinct `User` objects containing their storage metadata and personal `Wallet` for interacting with the system.

-----

## 2\. Core Modules

### 2.1. Module: `warlot::warlot_system`

The central hub of the protocol. It manages global configuration, user indexing, and the protocol's treasury.

#### Structs

  * **`SystemConfig`** (`key`, `store`)

      * **Description:** The singleton shared object acting as the entry point for the protocol.
      * **Fields:**
          * `id`: Unique Identifier.
          * `version`: Current protocol version.
          * `users`: Counter for registered users.
          * `managed_blobs`: Counter for total active blobs.
          * `user_modification_cfg`: Struct defining costs for system operations (migration, name updates).
          * *Dynamic Fields:*
              * `USERINDEX`: A `TableVec<address>` listing all registered users.
              * `USER_INDEX_MAP`: A `Table<address, u64>` for O(1) user lookups.
              * `SYSTEM_VAULT`: A `Vault` object holding system revenue.

  * **`AdminCap`** (`key`, `store`)

      * **Description:** Capability granting administrative privileges.
      * **States:**
          * `STATE_ORIGINAL` (0): Full access (Minting systems, withdrawing funds, adding coin types).
          * `STATE_DUPLICATE` (1): Restricted access.

#### Key Functions

  * **`init`**
      * Initializes the protocol, creates the `SystemConfig` and `Vault`, sets WAL as the default accepted token, and shares the object.
  * **`add_user`**
      * Registers a new `User` object into the system. Updates both the `TableVec` and `Table` indexers to ensure O(1) access and iteration.
  * **`remove_user`**
      * Removes a user from the system. Utilizes a "swap-and-pop" strategy to remove the user from the `TableVec` in O(1) time without gas scaling issues.
  * **`migrate_system`**
      * Transfers a user's registry and identity from an old `SystemConfig` to a new one. Requires payment of a migration fee.
  * **`mint_system`**
      * Creates a new generation of `SystemConfig`. Only callable by the holder of the Original `AdminCap`.
  * **`withdraw_system_coin<T>`**
      * Allows the admin to withdraw accumulated fees of type `T` (e.g., WAL, USDC) from the system vault.

-----

### 2.2. Module: `warlot::vault`

The financial engine supporting multi-token architecture.

#### Structs

  * **`Vault`** (`key`, `store`)
      * **Description:** A container for assets. Unlike standard Move structs, it does not use a generic type parameter `<T>` on the struct itself, allowing it to hold mixed asset types simultaneously via Dynamic Fields.
      * **Fields:**
          * `accepted_coins`: A `Table<String, bool>` tracking allowed coin types.

#### Key Functions

  * **`deposit<T>`**
      * Accepts a `Coin<T>`. Verifies `T` is in `accepted_coins`. Merges the coin into the vault's internal balance stored under a dynamic field key derived from the type name.
  * **`withdraw<T>`**
      * Extracts a specific amount of `Coin<T>` from the vault. Fails if the balance is insufficient.
  * **`add_supported_coin<T>`**
      * Registers a new coin type (e.g., USDC, SUI) as accepted.
  * **`balance_of<T>`**
      * Returns the current balance of type `T` held in the vault.

-----

### 2.3. Module: `warlot::user_state`

Manages individual user identity, permissions, and the storage blob data structure.

#### Structs

  * **`User`** (`key`, `store`)

      * **Description:** Represents a registered entity.
      * **Fields:**
          * `owner`: The Sui address controlling this user.
          * `wallet`: The internal `Wallet` struct.
          * `meta_data`: Statistics on file count and storage size.
          * `index`: A `Table<u32, ID>` mapping an `EpochSet` to the **Head** of a Linked List of blobs.

  * **`SubPermission`** (`store`)

      * **Description:** Granular access control list for third-party operators.
      * **Flags:** `add_blob_to_address`, `create_inner_file`, `create_writer_pass`, `can_init_db`.

#### Blob Chain Architecture (LIFO)

Storage blobs are organized as a Linked List to enable efficient processing.

  * **Insertion (`add_blob`):** New blobs are prepended to the **HEAD**. The `index` table is updated to point to the new blob ID.
  * **Traversal:** Iteration starts at the ID found in `index` and follows the `next` pointer until `None`.
  * **Removal:** Removing a blob repairs the chain by linking its `pre` and `next` neighbors. If the Head is removed, the `index` is updated to the next node.

#### Key Functions

  * **`create_user`**
      * mints a new `User` object, initializes the wallet and permission tables.
  * **`add_blob`**
      * Prepends a `BlobConfig` to the user's list for a specific epoch set.
  * **`remove_blob_cfg_from_user`**
      * Detaches a blob from the linked list, repairing links and updating statistics.
  * **`check_permission_[action]`**
      * Verifies if the caller has the specific `SubPermission` flag or is the owner.

-----

### 2.4. Module: `warlot::wallet`

The user's internal banking interface.

#### Structs

  * **`Wallet`** (`key`, `store`)

      * **Description:** The user-facing interface for funds.
      * **Storage:** Contains a `Bank` struct as a Dynamic Object Field.

  * **`Bank`** (`key`, `store`)

      * **Description:** Holds balances for multiple coin types using Dynamic Fields.

#### Key Functions

  * **`deposit<T>`**
      * Splits a mutable `Coin<T>` and deposits the amount into the internal Bank.
  * **`withdraw<T>`**
      * Withdraws assets from the Bank to a `Coin<T>`.
  * **`get_balance<T>`**
      * Returns the available balance for a specific asset.

-----

### 2.5. Module: `warlot::renew`

Handles the periodic renewal of storage blobs to prevent expiration.

#### Logic Flow (`renew_system_blob`)

1.  **Iterate Users:** Loops through the global user indexer in `SystemConfig`.
2.  **Access Chain:** For each user, retrieves the **Head** blob ID for the target `epoch_set`.
3.  **Traverse List:** Iterates through the Linked List of `BlobConfig` objects.
4.  **Execute Renewal:** Calls `renew_blob_cfg` on each config, calculating the cost based on the `ahead` parameter (target duration).
5.  **Payment:** Deducts the total cost from the provided `Estimate` budget.

-----

## 3\. Data Structures & Relationships

### Hierarchy

```text
SystemConfig (Shared)
├── User Indexer (TableVec<address>)
├── User Index Map (Table<address, u64>)
└── System Vault (Dynamic Object Field)
    └── Dynamic Fields: Balance<WAL>, Balance<USDC>, etc.

User (Owned/Child Object)
├── Wallet
│   └── Bank (Dynamic Object Field)
│       └── Dynamic Fields: Balance<WAL>, Balance<SUI>, etc.
└── Blob Index (Table<u32, ID>)
    └── Maps EpochSet -> Head Blob ID
```

### Blob Linked List

```text
[Index Table] points to -> [Blob A (Head)]
                              |
                              v
                           [Blob B]
                              |
                              v
                           [Blob C (Tail)] -> Next: None
```

