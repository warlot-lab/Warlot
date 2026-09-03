# Deployment resources

**The state inventory lives in `documentation/deployment.md`, at the repository root.** It records
the package id, the `SystemConfig`, the original `AdminCap`, the `UpgradeCap` and the `Clock` for
each network, together with what holds them — read from the chain rather than transcribed.

This file used to hold a publish transcript for a package called `setandrenew`, at
`0xe0b7c456…dd0a200e9`, whose modules were `bucketmain`, `config`, `constants`, `event`,
`filemain`, `projectmain`, `registry`, `setandrenew`, `tablemain`, `userstate`, `wallet` and
`warlotpackage`. **None of those modules exist in this package**, and none of those ids describe
anything this source tree can be deployed as. It also ended with an
`sui client upgrade --package 0xe0b7c456…` command, which would have been aimed at that dead
package.

It is removed rather than corrected because a second inventory is how the two come to disagree,
which is the failure this file was already an instance of.
