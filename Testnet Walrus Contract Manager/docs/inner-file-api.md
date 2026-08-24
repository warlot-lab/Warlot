# 📄 **Warlot Inner File, Quick Docs**

The **Inner File** is a core structure in the Warlot system that enables **trusted, collaborative, and controlled file modification** on the Walrus protocol. It ensures file **integrity**, **ownership**, and **accountable collaboration**, while supporting features like draft editing, file history tracking, and admin-controlled recovery.

---

## 🚀 **What It Does**

✅ Enables secure file creation and modification within Walrus.
✅ Supports draft edits and group collaboration with permission controls.
✅ Maintains a trackable file history (with rollback options via `root_change`).
✅ Allows trusted servers (e.g., Warlot server) to help modify large files.
✅ Lets owners manage writers, collaborators, and admin-level permissions.

---

## 🏗 **Core Data Structures**

### `InnerFile`

```rust
public struct InnerFile has key, store {
    id: UID,
    owner: address,            // Owner and admin of the file
    writers_length: u8,        // Max draft entries a writer can add at a time
    file_history: FileTrack,   // Tracks file data and changes
    created_at_ms: u64
}
```

- **Owner:** Controls the file, manages collaborators, approves/rejects changes.
- **Writers_length:** Limits how many drafts a writer can push in one go.
- **File_history:** Holds file content and change history.

---

### `FileTrack`

```rust
public struct FileTrack has store {
    root_change: Option<FileData>,   // Safe fallback file state
    track_back_length: u8,           // Max history depth
    track_back: vector<FileData>,    // List of file versions
    last_modified: u64
}
```

- **root_change:** The file state the owner can fall back to.
- **track_back:** Stores file history; index `0` = latest change.
- **track_back_length:** Controls how much history is kept on chain.

---

### `FileData`

```rust
public struct FileData has store, drop {
    commit: vector<u8>,         // Encrypted commit message
    commit_by: address,         // Who made the change
    walrus_blob_id: String,     // Blob ID in Walrus
    walrus_blob_object_id: ID   // Blob object ID in Walrus
}
```

---

### `WriterPass` + `AdminPass`

- **WriterPass:** Grants draft-writing or direct edit permission.
- **AdminPass:** Grants admin-level powers to a writer (optional).

---

## ⚙ **How To Use**

### 🔹 `create_file(...)`

```rust
public fun create_file(
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    walrus_blob_id: String,
    walrus_blob_object_id: address,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    ctx: &mut TxContext
)
```

👉 **Creates a new Inner File**.

- Sets up file ownership, history tracking, and default writer/admin passes.
- Can be used to create a file for yourself or someone else (owner address).

---

### 🔹 `write_(...)`

```rust
public fun write_(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    to_draft: bool,
    file_issue: u64,
    should_include_issue: bool,
    commit: vector<u8>,
    walrus_blob_id: String,
    walrus_blob_object_id: address,
    clock: &Clock,
    ctx: &mut TxContext
)
```

👉 **Modifies the Inner File.**

- `to_draft: true` → Add to draft (for review/collab).
- `to_draft: false` → Direct file change (requires admin rights).
- Tracks changes in `FileTrack`.

---

## 🌟 **Key Features**

- **Immutable ownership:** Only the owner can manage collaborators, root_change, and approve final edits.
- **Draft collaboration:** Writers can propose changes without altering the main file.
- **Rollback safety:** `root_change` gives owners a way to revert to a trusted state.
- **History control:** Adjustable `track_back_length` lets owners balance cost vs. recovery options.
- **Trusted server support:** Large files can be modified by approved remote servers to reduce client load.

---

## 💡 **Example Flow**

1️⃣ Owner calls `create_file` to set up the file.
2️⃣ Writers use `write_` with `to_draft = true` to propose edits.
3️⃣ Owner reviews and applies changes, or rolls back if needed.
4️⃣ Admin writers can directly modify files if granted `AdminPass`.
