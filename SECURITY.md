# Security Policy

Warlot Protocol is on-chain software. A defect here can result in permanent, irreversible loss of
user assets. This policy covers how to report a vulnerability and what the project commits to in
return.

## Reporting a vulnerability

Report privately to **gospelifeadi.job@gmail.com**. Do not open an issue, discussion, or pull
request describing a vulnerability, and do not disclose it publicly before it is resolved.

Include what you have: affected module and function, the conditions required to trigger it,
observed or expected impact, and any proof of concept. A Move test that reproduces the issue is the
most useful thing you can send.

Acknowledgement is sent within **3 business days**, an initial assessment within **10 business
days**, and remediation is prioritised by severity. You will be told when a fix ships.

## Scope

**In scope:** the Move packages in this repository, the off-chain services in `RenewBot/` and
`sui-indexer/`, and the build and deployment configuration.

**Out of scope:** vulnerabilities in Sui, Walrus, or their reference clients, report those upstream
to the relevant project. Third-party dependency vulnerabilities are in scope only for how this
project uses or exposes them.

## Testing rules

Test against **Sui testnet or a local network only**. Do not test against mainnet.

Do not access, alter, or destroy assets belonging to anyone else. Do not degrade network
availability. Automated transaction flooding is not authorised.

Because this project's renewal path is deliberately permissionless, any address may pay to renew
any user's storage, a call succeeding from an unrelated address is **expected behaviour, not a
vulnerability**. What would be a vulnerability is an unrelated address causing loss, denial, or
state change beyond paying for someone's renewal.

## Properties worth understanding before testing

These are design decisions, not oversights. Reports that describe them as bugs will be closed as
working-as-intended.

- **Renewal is permissionless by design.** No capability and no allowlist gates it. This is the
  property that lets a user's storage survive without our cooperation, and it is not a defect.
- **Custody is mediated by code, not by raw object ownership.** The protocol holds a user's Walrus
  blobs so that a third party can renew them. The user's guarantee is that withdrawal is
  unconditional for the owner, a defect in *that* is a serious vulnerability.
- **Storage terms are quantised.** Walrus mainnet epochs are two weeks, so no storage term lands on
  an exact calendar boundary. Terms are approximate by construction.
- **The protocol does not hold file contents or file metadata.** Names, descriptions and counters
  are off-chain. The chain holds a commitment binding them, so a mismatch between an off-chain
  record and its on-chain commitment is a finding worth reporting.

## What we consider severe

In rough order of severity:

1. Loss of, or permanent loss of access to, a user's blobs or funds.
2. An unauthorised party causing a user's storage to expire.
3. Bypass of the permission model, the writer-pass expiry, or the deny list.
4. Unauthorised treasury access.
5. A state transition that cannot be recovered from and was not consented to.
6. Denial of service that cannot be resolved by waiting or by paying more gas.

## Disclosure

Coordinated. We will agree a disclosure timeline with you, publish a fix, and credit you if you
wish to be credited.

## No bounty

There is no paid bounty programme at this time. Good-faith reports are welcomed and credited.

## Audit status

**This code has not completed an external audit.** Until it has, and until the pre-release banner in
[README.md](README.md) changes, treat any deployment as experimental and do not entrust it with
assets you cannot afford to lose.
