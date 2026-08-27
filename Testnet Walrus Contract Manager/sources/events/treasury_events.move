/// Declares the events the protocol treasury raises: what it accepts, what it
/// takes in, and what it pays out.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::treasury_events;

// === Imports ===

use std::string::String;
use sui::event;

// === Events ===

/// A coin type was added to or removed from the treasury's accepted list.
public struct VaultCoinSupportChanged has copy, drop, store {
    system_id: ID,
    coin_type: String,
    supported: bool,
}

/// The treasury took a payment.
public struct VaultDeposited has copy, drop, store {
    system_id: ID,
    coin_type: String,
    amount: u64,
    new_balance: u64,
}

/// The treasury paid out.
///
/// The coin type is carried because the vault is multi-coin: without it every
/// type collapses into one number that sums balances of different things.
public struct SystemWithdraw has copy, drop, store {
    system_id: ID,
    operator: address,
    coin_type: String,
    amount: u64,
    new_balance: u64,
}

// === Package functions ===

/// Announce a change to the treasury's accepted-coin list.
public(package) fun emit_vault_coin_support_changed(
    system_id: ID,
    coin_type: String,
    supported: bool,
) {
    event::emit(VaultCoinSupportChanged { system_id, coin_type, supported })
}

/// Announce a payment into the treasury.
public(package) fun emit_vault_deposited(
    system_id: ID,
    coin_type: String,
    amount: u64,
    new_balance: u64,
) {
    event::emit(VaultDeposited { system_id, coin_type, amount, new_balance })
}

/// Announce a treasury payout.
public(package) fun emit_system_withdraw(
    system_id: ID,
    operator: address,
    coin_type: String,
    amount: u64,
    new_balance: u64,
) {
    event::emit(SystemWithdraw { system_id, operator, coin_type, amount, new_balance })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `VaultCoinSupportChanged`, in declaration order.
public fun read_vault_coin_support_changed(e: &VaultCoinSupportChanged): (ID, String, bool) {
    let VaultCoinSupportChanged {
        system_id: _system_id,
        coin_type: _coin_type,
        supported: _supported,
    } = e;

    (*_system_id, *_coin_type, *_supported)
}

#[test_only]
/// Every field of `VaultDeposited`, in declaration order.
public fun read_vault_deposited(e: &VaultDeposited): (ID, String, u64, u64) {
    let VaultDeposited {
        system_id: _system_id,
        coin_type: _coin_type,
        amount: _amount,
        new_balance: _new_balance,
    } = e;

    (*_system_id, *_coin_type, *_amount, *_new_balance)
}

#[test_only]
/// Every field of `SystemWithdraw`, in declaration order.
public fun read_system_withdraw(e: &SystemWithdraw): (ID, address, String, u64, u64) {
    let SystemWithdraw {
        system_id: _system_id,
        operator: _operator,
        coin_type: _coin_type,
        amount: _amount,
        new_balance: _new_balance,
    } = e;

    (*_system_id, *_operator, *_coin_type, *_amount, *_new_balance)
}
