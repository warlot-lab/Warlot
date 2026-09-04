/// Composes the upgrade authority an `AdminCap` holder exercises over the
/// package's own code.
///
/// **Nothing here takes a `SystemConfig`, and nothing here asserts the version.**
/// That is the one deliberate exception to the rule the rest of the entry surface
/// keeps, and it is the same exception `admin::migrate_version` makes, for the
/// same reason. The version gate fences the state a mismatched build could write
/// to; an upgrade writes none of it. What an upgrade is, is the repair. A bad
/// build that broke migration would leave every system permanently behind the
/// package, and if reaching this module needed a system that was at the package
/// version, the one lever that could fix it would be the one the fault had
/// already taken away.
///
/// The version gate still applies afterwards, and hard: committing an upgrade
/// leaves every `SystemConfig` behind the new package, so the whole surface stays
/// closed until an admin calls `admin::migrate_version` on each one. Authorising
/// cannot raise the version on the way past, because the code executing here is
/// the code being replaced ,  `version::get_version()` in this transaction is the
/// old constant, and the new one does not exist on chain until the upgrade
/// command that runs after this call has returned.
module warlot::entry_upgrade;

// === Imports ===

use sui::package::{UpgradeCap, UpgradeReceipt, UpgradeTicket};
use warlot::{
    admin_cap::AdminCap,
    entry_admin,
    upgrade::{Self, UpgradeAuthority}
};

// === Admin functions ===

/// Take the capability the publish transaction created under the authority of
/// the system `admin_cap` names.
///
/// The system is read from the capability because there is no authority yet to
/// name one; what the check does here is refuse a duplicate. Run once, in the
/// transaction after publication ,  until it is, the package's code is governed
/// by whatever wallet holds the capability and by nothing else.
///
/// The capability is not checked against this package's own id, because the
/// framework exposes no way to do it that keeps working: `upgrade_package`
/// returns the *current* package, which equals the original only until the first
/// upgrade, and there is no accessor for the original. The ids are announced in
/// `UpgradeAuthorityCreated` instead, and `documentation/deployment.md` records
/// what they were, so a mismatch is visible rather than prevented.
public fun take_custody(cap: UpgradeCap, admin_cap: &AdminCap, ctx: &mut TxContext) {
    let system = admin_cap.system_config_id();
    entry_admin::assert_original_cap_for(admin_cap, system);

    upgrade::new(cap, system, ctx.sender(), ctx);
}

/// Issue a ticket authorising an upgrade to the build `digest` names.
///
/// Returns the ticket rather than acting on it, because only the transaction's
/// own `Upgrade` command can. The three steps are one programmable transaction:
/// this call, the upgrade command that turns the ticket into a receipt, then
/// `commit_upgrade`. They cannot be split across transactions and there is no
/// design decision in that ,  `UpgradeTicket` has no abilities, so it cannot be
/// stored, transferred or dropped, and a transaction that issues one and does not
/// spend it does not commit at all. The capability can therefore never be left
/// stranded in the authorised state its package id being zero represents.
public fun authorise_upgrade(
    authority: &mut UpgradeAuthority,
    admin_cap: &AdminCap,
    digest: vector<u8>,
    ctx: &TxContext,
): UpgradeTicket {
    entry_admin::assert_original_cap_for(admin_cap, authority.system());

    upgrade::authorise(authority, digest, ctx.sender())
}

/// Consume the receipt the upgrade command produced, moving the authority onto
/// the new package.
public fun commit_upgrade(
    authority: &mut UpgradeAuthority,
    admin_cap: &AdminCap,
    receipt: UpgradeReceipt,
    ctx: &TxContext,
) {
    entry_admin::assert_original_cap_for(admin_cap, authority.system());

    upgrade::commit(authority, receipt, ctx.sender());
}

/// Give up the right to change existing code, keeping the right to add to it and
/// to move dependencies.
///
/// The ratchet turns one way. The framework refuses anything less restrictive
/// than the policy already in force, so this cannot be undone here or anywhere
/// else, and a system that has taken this step cannot rewrite a function body
/// again.
public fun restrict_to_additive(
    authority: &mut UpgradeAuthority,
    admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    entry_admin::assert_original_cap_for(admin_cap, authority.system());

    upgrade::restrict_to_additive(authority, ctx.sender());
}

/// Give up everything but moving dependencies.
public fun restrict_to_dep_only(
    authority: &mut UpgradeAuthority,
    admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    entry_admin::assert_original_cap_for(admin_cap, authority.system());

    upgrade::restrict_to_dep_only(authority, ctx.sender());
}

/// Freeze the package: destroy the authority and the capability inside it.
///
/// Exposed rather than withheld, because the alternative to a deliberate call is
/// not safety. A protocol that means to become unchangeable and has no way to say
/// so keeps a live upgrade key forever, and a key that exists is a key that can
/// be compromised; the honest end state is one where there is nothing to steal.
///
/// It takes the authority by value and there is no way back. After this the code
/// this package runs is the code it runs, and the system chain ,  `mint_system`
/// beside the old system, users walking across ,  is the only change left that
/// reaches anything.
public fun make_immutable(
    authority: UpgradeAuthority,
    admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    entry_admin::assert_original_cap_for(admin_cap, authority.system());

    upgrade::destroy(authority, ctx.sender());
}
