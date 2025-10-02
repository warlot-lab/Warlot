# Warlot Waitlist NFT 🎴✨

**Modules:** `wait_list::wait`, `wait_list::contribution`
**Chain:** Sui Move
**Purpose:** On-chain waitlist pass with public minting, admin airdrops, and per-NFT contribution tracking.

---

## Overview 🚀

The **Warlot Waitlist NFT** implements a shared **mint template** with optional suspension, an **admin capability** system with bounded supply, and a lightweight **contribution ledger** attached to each minted NFT via dynamic fields. The design enables:

* 🧩 A single, shared **clone** object defining current mint metadata.
* 👤 **One-per-address** public self-mint.
* 🎁 **Admin airdrops** to arbitrary recipients.
* 📊 Per-NFT **engagement tracking** (`WarlotData`) for interaction points and timestamps.
* 🔐 **Safe admin lifecycle** with cap limits and final-cap burn rules.

---

## High-Level Architecture 🧱

```mermaid
  A[Publish Package (init)] --> B[Mint 1 AdminCap to publisher]
  A --> C[Share CloneWaitCard<WAIT> with Genesis template]
  C -->|Admin| D[modify_clone]
  C -->|Admin| E[suspend_clone]
  C --> F[mint] --> G[WaitCard NFT]
  F --> H[Attach WarlotData (dynamic field)]
  G --> I[(Holder Wallet)]
  D --> C
  E -->|entry=None| X[Mint blocked (ESuspendedClone)]
```

---

## Data Structures 📦

### Witness

```move
public struct WAIT has drop {}
```

Phantom type to brand the shared template to this package lineage.

### NFT

```move
public struct WaitCard has key, store {
  id: UID,
  name: String,
  description: String,
  url: Url,
  warlot: Url,
}
```

### Shared Mint Template

```move
public struct CloneWaitCard<phantom WAIT> has key, store {
  id: UID,
  admin_slot: u8,         // free capacity to mint additional AdminCaps
  entry: Option<WaitCard> // active template; None => suspended
}
```

### Admin Capability

```move
public struct AdminCap has key { id: UID }
```

### Event

```move
public struct WaitCardAdded has copy, drop {
  object_id: ID,
  creator: address,
  receiver: address,
  name: String,
}
```

### Contribution Ledger

```move
public struct WarlotData has drop, store {
  interaction_points: u64,
  last_interaction_time: u64,
}
```

---

## Initialization 🧰

**Function:** `init(_otw: WAIT, ctx: &mut TxContext)`
**Effects:**

* Mints exactly one `AdminCap` to the publisher’s address.
* Creates and **public-shares** a `CloneWaitCard<WAIT>` seeded with a “Genesis NFT” template.
* Sets `admin_slot = ADMINCAP_MAX - 1` where `ADMINCAP_MAX = 4`.

---

## Access Control 🔑

* **Admin-gated functions:**
  `mint_admin`, `burn_admin`, `modify_clone`, `suspend_clone`, `borrow_contribution_mut`, `mint_to_request`.

* **Public functions:**
  `mint`, `mint_to_sender`, read-only views (`name`, `description`, `url`, `warlot`, `borrow_contribution`).

* **One-per-address self-mint:**
  Enforced by a dynamic field on the shared clone keyed by the caller’s `address → bool`. A second mint attempt results in `EInvalidAccess`.

---

## Public Interface 📚

### Views

```move
public fun name(wait_card: &WaitCard): &String
public fun description(wait_card: &WaitCard): &String
public fun url(wait_card: &WaitCard): &Url
public fun warlot(wait_card: &WaitCard): &Url
public fun borrow_contribution(wait: &WaitCard): &WarlotData
```

### Minting

```move
public fun mint(clone_card: &CloneWaitCard<WAIT>, ctx: &mut TxContext): WaitCard
public fun mint_to_sender(clone_card: &mut CloneWaitCard<WAIT>, ctx: &mut TxContext)
public fun mint_to_request(_: &mut AdminCap, clone_card: &CloneWaitCard<WAIT>, user: address, ctx: &mut TxContext)
```

**Rules:**

* `mint` and `mint_to_*` require `clone_card.entry.is_some()`; otherwise `ESuspendedClone`.
* `mint_to_sender` enforces a single claim per address via dynamic field marker; otherwise `EInvalidAccess`.

### Admin

```move
public fun mint_admin(_: &mut AdminCap, clone_card: &mut CloneWaitCard<WAIT>, candidate: address, ctx: &mut TxContext)
public fun burn_admin(admin_cap: AdminCap, clone_card: &mut CloneWaitCard<WAIT>)
public fun modify_clone(_: &mut AdminCap, clone_card: &mut CloneWaitCard<WAIT>, wait_card: WaitCard, warlot: vector<u8>)
public fun suspend_clone(_: &mut AdminCap, clone_card: &mut CloneWaitCard<WAIT>)
public fun borrow_contribution_mut(_: &mut AdminCap, wait: &mut WaitCard): &mut WarlotData
```

**Constraints:**

* `ADMINCAP_MAX = 4`; exceeding this raises `ECapLimit`.
* Burning the **last** admin cap requires `entry == None` (template suspended) or `EActiveClone` is raised.

### Lifecycle

```move
public fun burn(wait_card: WaitCard)
```

Burns the NFT and removes its `WarlotData` dynamic field.

---

## Contribution Ledger (Dynamic Field) 📊

* Key: `CONTRIBUTION = b"WARLOT CONTRIBUTIONS"`.
* Created automatically during mint via `contribution::create()`.
* Read-only access for all holders: `borrow_contribution(&WaitCard)`.
* Mutable access requires `&mut AdminCap` and returns `&mut WarlotData`:

  ```move
  public fun borrow_contribution_mut(_: &mut AdminCap, wait: &mut WaitCard): &mut WarlotData
  ```
* Internal update entrypoint (package scope):

  ```move
  public(package) fun update_points(wd: &mut WarlotData, points: u64, clock: &Clock)
  ```

This pattern preserves global integrity of point accrual while keeping the state transparent to indexers and wallets.

---

## Errors ⚠️

* `EInvalidClone` — suspend requested while no template exists.
* `ESuspendedClone` — mint attempted while template is suspended.
* `ECapLimit` — admin cap limit exceeded.
* `EActiveClone` — attempt to burn final admin cap while template is still active.
* `EInvalidAccess` — self-mint attempted more than once by the same address.

---

## Typical Flows 🎯

1. **Public self-mint (one per address):**
   `mint_to_sender(shared_clone, ctx)` → creates `WaitCard`, attaches `WarlotData`, emits `WaitCardAdded`, transfers to sender, writes address marker on `CloneWaitCard<WAIT>`.

2. **Admin airdrop:**
   `mint_to_request(admin_cap, shared_clone, recipient, ctx)` → creates `WaitCard`, attaches `WarlotData`, emits `WaitCardAdded`, transfers to recipient.

3. **Template update:**
   `modify_clone(admin_cap, shared_clone, new_template_card, new_warlot_bytes)` → replaces template and clears legacy dynamic fields.

4. **Suspend minting:**
   `suspend_clone(admin_cap, shared_clone)` → sets `entry = None`, causing mint to revert with `ESuspendedClone` until a new template is set.

---


## Gas & Storage Considerations ⛽

* `WaitCard` carries two `String` and two `Url` values; concise metadata reduces object size and gas.
* `WarlotData` is compact (`u64 + u64`), but dynamic-field reads/writes incur costs.
* Frequent template rotations imply additional object churn (burn/fill of the template). Rotations should be deliberate.


---

## Testing Checklist 🧪

* **Initialization:** single `AdminCap` to publisher; shared `CloneWaitCard<WAIT>` exists; `admin_slot = ADMINCAP_MAX - 1`.
* **Self-mint:** first call succeeds; second call reverts with `EInvalidAccess`; `WaitCardAdded` fields are consistent.
* **Airdrop:** succeeds under `AdminCap`; event fields reflect creator and receiver.
* **Suspend/Resume:** suspension blocks mint with `ESuspendedClone`; template update reinstates minting.
* **Admin cap bounds:** `mint_admin` respects cap; `burn_admin` enforces suspension when burning the last cap.
* **Contribution ledger:** attached on mint; readable via `borrow_contribution`; `burn` removes the field.

---

## Changelog 🗒️

* **v1.1.0** — Adds one-per-address self-mint gate.
* **v1.0.0** — Initial release with shared template, admin caps, public/airdrop minting, and per-NFT contributions.

---

## License 📄

© Warlot. All rights reserved unless otherwise stated.

---

**Warlot Waitlist NFT** — minimal overhead, verifiable access, durable engagement. 💫
Warlot Waitlist NFT brings early community members on-chain with a clean, verifiable path to engagement
simple to mint, safe to administer, and ready to evolve. 