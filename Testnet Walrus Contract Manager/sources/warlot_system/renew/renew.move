module warlot::renew;
// module for renew blobs
// context | -> warlot_system::renew -> get price cut for storage range -> get debit amount -> callculate amount for cost -> drop blob with inefficent; calculate total of inefficent -> return total inefficent amount to user wallet -> sync function to renew inefficent if needed  with context 
use wal::wal::{WAL};
use walrus::{blob::Blob, system::System};
use warlot::{
    warlot_system::{SystemConfig, Self},
};


fun get_user_