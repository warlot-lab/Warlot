
---

**Package ID:**

```
0x9e3c47d1bd8114a33177ae73a8f378fa9c92d053d29eacf7e2cdad8157c40e88
```

**API Object:**

```
0x741376b205b15b9c409b33c11a9241bec986a4834534b49804d109ecca4ee8f0
```

**Module:**

```
apiverify
```

---

### Function Calls

**Add API**

```move
public fun add_api(
    api_verify: &mut ApiVerify,
    key: String,
    hashed_api: String,
    user: address
)
```

* `key = projectholder + projectname`

**Modify API**

```move
public fun modify_api(
    api_verify: &mut ApiVerify,
    key: String,
    new_hashed_api: String,
    new_user: address,
)
```

**Remove API**

```move
public fun remove_api(
    api_verify: &mut ApiVerify,
    key: String,
)
```

---

### Viewing / Checking API Object

* Use **`getDynamicFieldObject`** via RPC.
* Pass the **APIVERIFY object** as the parent.
* Key type = `String`.
* Key value = `projectholder + projectname`.

➡ If it returns something → API exists.
➡ If nothing → API does not exist.

---

### Helper (API Count)

`ApiVerify` struct keeps track of how many APIs are stored:

```move
public struct ApiVerify has key, store {
    id: UID,
    length: u64,
}
```

You can call `getObject` with the `showContent` option to check the `length` from your backend.

---

📌 *I don’t know the exact RPC structure in JS. For reference, check the frontend code or ask Victory (female) for help.*

---
