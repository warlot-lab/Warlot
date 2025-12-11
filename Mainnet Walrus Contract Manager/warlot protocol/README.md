# Warlot Set and Renew Module

This Move smart contract module is part of the **Warlot** system, designed for managing user registrations, system administration, and blob storage with renew and update functionality. It provides core functionality for initializing the system, managing users, minting system administration capabilities, storing and renewing blobs (data chunks), and handling associated balances with the WAL token.

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Core Structures](#core-structures)
- [Public Functions](#public-functions)
- [Events](#events)
- [Error Handling](#error-handling)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

The **Warlot Set and Renew** module governs system-wide configurations and user interactions within the Warlot platform. It manages the lifecycle of users and system state via an admin capability pattern, ensuring that only authorized actors can perform critical system updates.

The module also handles storing and renewing blobs (files or data objects) linked to users and manages WAL token balances associated with these operations.

---

## Key Features

- System initialization and admin capability minting
- User creation with unique public usernames and API keys
- Controlled minting of new system versions
- Updating user API keys and usernames with associated costs
- Secure storage and management of blobs
- Renewal logic for blob lifecycle with token payments
- Coin deposit and balance management within user wallets

---

## Core Structures

### `SystemConfig`

- Holds the global system state, including user counts, system version, blob management, and balance.

### `SystemMintCap`

- Tracks minting status for linear system upgrades.

### `AdminCap`

- Admin capability token used for privileged actions like minting new systems, withdrawing funds, and blob management.

### `UserMdCfg`

- Configuration for user modification costs (e.g., updating API keys, migrating systems).

---

## Public Functions

### System Management

- **`init(ctx: &mut TxContext)`**
  Initializes the system, creating the first `SystemConfig` and minting the original `AdminCap`.

- **`mint_admin(receiver: address, admin_cap: &AdminCap, ctx: &mut TxContext)`**
  Mint a new admin capability if caller holds the original admin cap.

- **`mint_system(...)`**
  Mint a new system configuration with incremented version, ensuring linear system upgrades and only allowed by the original admin.

- **`update_cost(...)`**
  Update user modification costs in the system config.

- **`withdraw_system(system_cfg: &mut SystemConfig, admin_cap: &mut AdminCap, amount: u64, ctx: &mut TxContext)`**
  Withdraw WAL tokens from the system balance, callable only by the original admin.

---

### User and Blob Management

- **`create_user(...)`**
  Create a new user with API keys and public username, incrementing user count.

- **`update_api_key(...)`**
  Update a user's API keys with associated WAL token payment.

- **`update_username(...)`**
  Update a user's public username with associated WAL token payment.

- **`store_blob(...)`**
  Store a blob linked to a user, only callable by an admin.

- **`deposit_coin(...)`**
  Deposit WAL tokens into the user's internal wallet.

- **`renew(...)`**
  Renew blobs for a list of users, deducting funds from their wallets and updating blob states.

- **`sync_blob(...)`**
  Sync blob states across users and system.

---

## Events

The module emits events for:

- Minting of new admin caps
- Minting of new systems
- Blob storage
- Blob renewals and updates

These events are crucial for tracking system changes and user interactions on-chain.

---

## Error Handling

The contract defines explicit errors such as:

- `EUserExist`: Returned if attempting to create a user that already exists.
- Various asserts ensure only authorized admin caps can perform sensitive actions.
- Minting and versioning are strictly enforced to maintain system integrity.

---

## Usage

1. **System Initialization**
   Call `init` once to create the initial system configuration and mint the original admin cap.

2. **Minting Admins and Systems**
   Use the original admin cap to mint additional admin caps or upgrade the system by minting a new system.

3. **User Registration**
   Users can be created with unique public usernames and secured API keys.

4. **Blob Management**
   Admins store blobs on behalf of users and renew them periodically.

5. **Token Management**
   WAL tokens are used for payment of user updates and system operations, managed internally.

---

## Contributing

Contributions and improvements to this module are welcome. Please submit pull requests or open issues for bugs, enhancements, or questions.

---
