/// Funds a user's internal wallet, and pays it back out.
module warlot::entry_wallet;

// === Imports ===

use sui::coin::Coin;
use wal::wal::WAL;
use warlot::{system_config::SystemConfig, user, wallet};

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

/// Move `amount` of WAL out of the sender's internal wallet and hand it back to them.
///
/// The wallet is reached through the user record keyed by the sender's own
/// address, so the lookup is the authorization: no address can name another's
/// wallet.
#[allow(lint(self_transfer))]
public fun withdraw_wal(system_cfg: &mut SystemConfig, amount: u64, ctx: &mut TxContext) {
    let user = user::get_user_mut(system_cfg, ctx.sender());
    let coin = wallet::withdraw<WAL>(user.get_wallet(), amount, ctx);

    transfer::public_transfer(coin, ctx.sender());
}

/// Empty the sender's internal WAL balance back to them.
#[allow(lint(self_transfer))]
public fun withdraw_all_wal(system_cfg: &mut SystemConfig, ctx: &mut TxContext) {
    let user = user::get_user_mut(system_cfg, ctx.sender());
    let coin = wallet::withdraw_all<WAL>(user.get_wallet(), ctx);

    transfer::public_transfer(coin, ctx.sender());
}
