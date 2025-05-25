---
# 📖 Warlot Sui Indexer Documentation
---

## 🔍 Overview

The **Warlot Sui Indexer** is a backend service written in Go that listens to events from the **Sui blockchain** related to the Warlot project. It processes those events in real-time, decodes them, and persists relevant data into a **PostgreSQL** database for efficient querying and analytics.

This indexer powers dashboards, user insights, and other applications that rely on on-chain event data.

---

### Configure Environment Variables

Create a `.env` file at the root with these variables:

```env
BLOB_DATABASE_URL=postgres://reader:readerpass@98.82.8.211:5432/postgres?sslmode=require
RETRY_INTERVAL=3s
```

- **BLOB_DATABASE_URL** — PostgreSQL connection string
- **SUI_RPC_URL** — Sui blockchain RPC node URL TestNet

### Step 3: Build & Run

Build the indexer binary:

```bash
go build -o warlot-indexer ./cmd/indexer
```

Run the indexer:

```bash
./warlot-indexer
```

---

## 🚦 Usage

Once running, the indexer will:

- Connect to the Sui RPC node
- Continuously fetch blockchain events in batches, starting from the latest known cursor
- Process each event type according to predefined handlers
- Insert or update data in the PostgreSQL database within transactions to ensure consistency
- Retry on RPC or DB failures

You can monitor the logs for successful processing or errors.

---

## 📚 Supported Event Types

The indexer currently supports processing the following event types:

| Event Type           | Description                       |
| -------------------- | --------------------------------- |
| `NewUser`            | Detects when a new user registers |
| `Deposit`            | User deposits tokens/funds        |
| `ManagedBlobs`       | Handles user-managed blob data    |
| `WarlotFileStore`    | Publisher blob storage events     |
| `RenewDigest`        | Updates to blob digest            |
| `BlobUpdate`         | Metadata updates for blobs        |
| `WithdrawBlob`       | Blob withdrawals                  |
| `BlobWarlotAttribut` | Attribute changes on blobs        |

If an unknown event type appears, it will be logged for manual review.

---

## 🏗️ Architecture

### Components

| Module          | Responsibility                                      |
| --------------- | --------------------------------------------------- |
| `main.go`       | Entry point; handles main event polling loop        |
| `rpc/client.go` | Interfaces with Sui RPC node for event retrieval    |
| `processor`     | Contains handlers to decode and process events      |
| `store`         | Wraps PostgreSQL operations with transaction safety |
| `sui/types.go`  | Sui-specific types and constants                    |

### Flow Diagram

```
Sui RPC Node  <--->  Indexer (Go)  <--->  PostgreSQL DB
       ↑                                 ↓
    Blockchain                       Event Data Storage
```

---

## 🧩 Database Schema

The indexer stores data in tables tailored to each event type. The schema is designed to optimize query speed and integrity.

Example tables:

- **users**: stores new user data
- **deposits**: logs deposits with amounts and timestamps
- **blobs**: tracks blob metadata and ownership
- **blob_attributes**: stores dynamic attributes on blobs

_Schema scripts are in `/db/schema.sql` (if you want I can help generate it)._

---

## 🛠️ Error Handling & Retry

- On RPC errors, the indexer waits for `RETRY_INTERVAL` before retrying
- Database transaction errors cause rollback to prevent partial data
- Unrecognized events are logged but do not stop the indexer
- Cursor position is saved only after successful batch processing

---
