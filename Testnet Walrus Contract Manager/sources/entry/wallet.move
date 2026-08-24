/// Funds a user's internal wallet.
module warlot::entry_wallet;

// === Imports ===

use sui::coin::Coin;
use wal::wal::WAL;
use warlot::{system_config::SystemConfig, user};

// === Public functions ===

/// Move `amount` from `coin` into the sender's internal wallet and return the
/// wallet's new WAL balance.
public fun deposit_coin(
    system_cfg: &mut SystemConfig,
    coin: &mut Coin<WAL>,
    amount: u64,
    ctx: &mut TxContext,
): u64 {
    let user = user::get_user_mut(system_cfg, ctx.sender());
    let wallet_state = user.get_wallet();

    wallet_state.deposit(coin, amount, ctx)
}
