## warlot creation details

## transaction digest

```txt
Ai1ETiYWThWNS6wmvyFMERNGP4Mi5kUUZrU5Fh6T8auE
```

```rust
   ┌──                                                                                                                                        │
│  │ ObjectID: 0x0653b1458143ea7295a04b439a49d358777228abbceb2561ff827a236f650625                                                             │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                                                               │
│  │ Owner: Account Address ( 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd )                                            │
│  │ ObjectType: 0x2::package::UpgradeCap                                                                                                     │
│  │ Version: 432844092                                                                                                                       │
│  │ Digest: E1dfgoToPKf1krCBjWAW5eecLpJEWRpBrL6BLvw1L2qb                                                                                     │
│  └──                                                                                                                                        │
│  ┌──                                                                                                                                        │
│  │ ObjectID: 0x413db6f44095b14773bebf452d2d770df6624aa157d54f9b6f7320ac09ecae4d                                                             │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                                                               │
│  │ Owner: Account Address ( 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd )                                            │
│  │ ObjectType: 0xe0b7c4563c4cdfb71a046931c1b5724192ad515ed33bb73718a414bdd0a200e9::setandrenew::AdminCap                                    │
│  │ Version: 432844092                                                                                                                       │
│  │ Digest: G84K5Merwp5iHDwqubrGyXvq5MD5kbTtudMd9g2ELG4g                                                                                     │
│  └──                                                                                                                                        │
│  ┌──                                                                                                                                        │
│  │ ObjectID: 0xa9435bf6bc30002a80eb4b6c108c2b5c6d8215781530660ce7a228f49ee8eb6b                                                             │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                                                               │
│  │ Owner: Shared( 432844092 )                                                                                                               │
│  │ ObjectType: 0xe0b7c4563c4cdfb71a046931c1b5724192ad515ed33bb73718a414bdd0a200e9::setandrenew::SystemConfig                                │
│  │ Version: 432844092                                                                                                                       │
│  │ Digest: 5KP3U1zcW41T6Ax6aLWxtctbj1ro1nLCCmbmTsLXxJkt                                                                                     │
│  └──                                                                                                                                        │
│ Mutated Objects:                                                                                                                            │
│  ┌──                                                                                                                                        │
│  │ ObjectID: 0x28f812c2fdff84e316d580515e1e408d68dfe6ab5931c1dda89f07b83589976b                                                             │
│  │ Sender: 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd                                                               │
│  │ Owner: Account Address ( 0xa8c88213fac31eab2dd706c6e981072894a23e5479c18dcfe42dcdc2fc44bebd )                                            │
│  │ ObjectType: 0x2::coin::Coin<0x2::sui::SUI>                                                                                               │
│  │ Version: 432844092                                                                                                                       │
│  │ Digest: DS23UzN8z2ZM1ajx4bDjrPCQsUDTSbzWE5518m5FpVaZ                                                                                     │
│  └──                                                                                                                                        │
│ Published Objects:                                                                                                                          │
│  ┌──                                                                                                                                        │
│  │ PackageID: 0xe0b7c4563c4cdfb71a046931c1b5724192ad515ed33bb73718a414bdd0a200e9                                                            │
│  │ Version: 1                                                                                                                               │
│  │ Digest: DbhDk889m8PTspAT1u399JMqh73mtFAwDb1dbyV7GJfq                                                                                     │
│  │ Modules: bucketmain, config, constants, event, filemain, projectmain, registry, setandrenew, tablemain, userstate, wallet, warlotpackage │
│  └──                                                                                                                                        │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

```

sui client upgrade -- --package 0xe0b7c4563c4cdfb71a046931c1b5724192ad515ed33bb73718a414bdd0a200e9 --upgrade-cap 0x0653b1458143ea7295a04b439a49d358777228abbceb2561ff827a236f650625
