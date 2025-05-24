---
# RenewBot Documentation
---

## Overview

**RenewBot** is a service that monitors user wallet balances and blob storage renewal requirements on the Warlot decentralized storage platform. It periodically checks if users have sufficient funds to renew their stored blobs and triggers renewal transactions or sends failure notification emails if funds are insufficient.

---

## Components

RenewBot consists of three main packages:

- `renewal`: Core logic for renewal checking and scheduling.
- `sui`: Blockchain interaction to fetch Walrus system state and perform renewal transactions.
- `mailer`: Sending emails notifying users of failed renewals (not fully shown but referenced).

---

## Package: `renewal`

This package handles:

- Checking users' blob storage epochs and required funds.
- Comparing required funds against wallet balances.
- Sending notifications for insufficient funds.
- Triggering renewal calls for eligible users.

### Structs

```go
type BlobRenewal struct {
    Address        string  // User wallet address
    TotalEpochDiff int64   // Total epochs difference needing renewal
    RequiredFunds  int64   // Calculated required funds to renew blobs
    Balance        int64   // Current wallet balance
    HasSufficient  bool    // True if balance >= required funds
}
```

### Constants / Variables

```go
var EpochSets = []int{13, 23, 53}  // Epoch intervals to check renewal

var syncQueue = make(map[int]uint64)  // Map of epoch sets to next target Walrus epoch
```

### Functions

#### `CheckAndRenew`

```go
func CheckAndRenew(epoch int, walrusEpoch uint64, storageCost uint64, blobDB, userDB *sql.DB)
```

- **Description:** Checks renewal eligibility for each epoch set. Queries the database for users whose blobs require renewal, compares balances, sends failure emails, and queues renewal transactions.

- **Parameters:**

  - `epoch`: Current global epoch.
  - `walrusEpoch`: Current Walrus system epoch.
  - `storageCost`: Cost per storage unit.
  - `blobDB`: Database connection to blob-related data.
  - `userDB`: Database connection to user information.

- **Process:**

  - Loops through predefined epoch sets (`13`, `23`, `53`).
  - Runs renewal checks only on epochs divisible by `base-1` for each base.
  - Queries blob and wallet data joined with user info.
  - For each user:

    - Checks if wallet balance is sufficient.
    - Sends failure notification if not.
    - Adds user address to renewal list if sufficient.

  - Calls `sui.RenewBlob` with eligible users and epoch set.

---

#### `EnqueueNext`

```go
func EnqueueNext(set int, walrusEpoch uint64)
```

- **Description:** Schedules the next Walrus renewal epoch for a given epoch set.
- **Parameters:**

  - `set`: Epoch set (e.g., 13, 23, 53).
  - `walrusEpoch`: Current Walrus epoch to schedule from.

---

#### `GetQueuedTarget`

```go
func GetQueuedTarget(set int) uint64
```

- **Description:** Retrieves the queued target epoch for a given epoch set.
- **Returns:** Target epoch or zero if none queued.

---

## Package: `sui`

This package manages interaction with the Sui blockchain and the Walrus system.

### Key Functions

#### `GetWalrusEpoch`

```go
func GetWalrusEpoch() (epoch uint64, storageCost uint64, err error)
```

- **Description:** Fetches the current Walrus epoch and storage cost per unit from the blockchain.
- **Returns:**

  - `epoch`: Current Walrus system epoch.
  - `storageCost`: Storage price per unit.
  - `err`: Error if fetching fails.

---

#### `RenewBlob`

```go
func RenewBlob(usersAddress []string, epochs uint64) error
```

- **Description:** Performs blockchain transactions to renew storage blobs for specified users.
- **Parameters:**

  - `usersAddress`: List of user wallet addresses to renew.
  - `epochs`: Number of epochs to renew for.

- **Returns:** Error if the transaction fails.

---

### Internal Helpers

- `extractStorageCost` parses the storage price from raw blockchain data.
- Uses environment variables to configure blockchain client and credentials.

---

## Package: `mailer` (Referenced)

- **Function:** `SendFailureEmail` sends emails to users who do not have sufficient balance to renew their blobs.
- **Parameters:** Includes user name, wallet, email, required funds, available funds, etc.

---

## Environment Variables

RenewBot requires these environment variables for operation:

| Variable            | Description                                   |
| ------------------- | --------------------------------------------- |
| `WALRUS_SYSTEM`     | Walrus system object ID on the blockchain.    |
| `RPC_URL`           | Sui blockchain RPC endpoint.                  |
| `WARLOT_PACKAGE_ID` | Move package ID for transactions.             |
| `MOVE_MODULE_NAME`  | Move module name for Warlot smart contract.   |
| `ADMIN_CAP`         | Admin capability object ID for transactions.  |
| `SYSTEM_CFG_ID`     | System configuration object ID.               |
| `USER_MNEMONIC`     | Mnemonic for the wallet to sign transactions. |

---

## Database Schema (Approximate)

- `poc.warlot_stored_file`:

  - `owner_id`: references users
  - `epoch_set`: int epoch set value
  - `current_epoch`: int current epoch of blob
  - `encoded_size`: blob size in bytes

- `poc.app_user`:

  - `user_id`
  - `address`: user wallet address

- `poc.wallet`:

  - `user_id`
  - `balance`: wallet balance in WAL units

---

## Workflow Summary

1. **Epoch Trigger:** The bot runs periodically at new epochs.
2. **Renewal Check:** For each epoch set (13, 23, 53), checks if renewal is due.
3. **DB Query:** Fetches all users whose blobs need renewal based on epochs and size.
4. **Balance Check:** Compares required funds against wallet balances.
5. **Notifications:** Sends email if balance insufficient.
6. **Renewal Transactions:** Calls blockchain renew function for eligible users.
7. **Queue Management:** Manages next epoch target for renewals.

---

## Usage Notes

- Ensure environment variables are correctly set.
- Database connections (`blobDB` and `userDB`) must be configured and connected.
- Scheduler (cron or similar) should call `CheckAndRenew` periodically.
- Email service must be configured to send failure notifications.
- Wallet mnemonic used for signing transactions must be kept secure.

---

## How It Works

The bot retrieves the current Walrus system epoch and storage cost from the blockchain.

For each configured epoch set (13, 23, 53), the bot checks if blobs require renewal based on their stored epochs and user balances.

It queries the database to find users whose blobs are eligible for renewal.

It calculates the funds required for renewal and compares this to the users' wallet balances.

For users with insufficient funds, the bot sends a failure notification email.

For users with sufficient funds, it batches their renewal requests and sends transactions to the blockchain to renew their blobs.

The bot schedules the next renewal check per epoch set.

---

## Email Notifications

When a user does not have sufficient funds to renew their blobs, RenewBot sends an email notification with details:

- User name
- Wallet address
- Required renewal amount
- Current wallet balance

Ensure your SMTP credentials and email configuration are properly set to enable email sending.

---
