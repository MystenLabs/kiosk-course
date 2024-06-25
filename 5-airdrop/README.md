# Airdrop

In the previous section we tried to emulate an airdrop in `Kiosk` using `PurchaseCap`.

In this section we will directly airdrop to a user's `Kiosk` using a `kiosk_extension`.

## Kiosk Extension

Let's take a look inside the `sui::kiosk_extension` module. You can find it [here](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/kiosk_extension.move).

- A main functionality of an extension is to enable `place` and `lock` operations from it to the user's `Kiosk`.
- The user always holds the keys to enable/disable the above functionality.
- The extension can also do other things via the storage it has access to.

```rust
/// A Kiosk Extension is a module that implements any functionality on top of
/// the `Kiosk` without discarding nor blocking the base. Given that `Kiosk`
/// itself is a trading primitive, most of the extensions are expected to be
/// related to trading. However, there's no limit to what can be built using the
/// `kiosk_extension` module, as it gives certain benefits such as using `Kiosk`
/// as the storage for any type of data / assets.
///
/// ### Flow:
/// - An extension can only be installed by the Kiosk Owner and requires an
/// authorization via the `KioskOwnerCap`.
/// - When installed, the extension is given a permission bitmap that allows it
/// to perform certain protected actions (eg `place`, `lock`). However, it is
/// possible to install an extension that does not have any permissions.
/// - Kiosk Owner can `disable` the extension at any time, which prevents it
/// from performing any protected actions. The storage is still available to the
/// extension until it is completely removed.
/// - A disabled extension can be `enable`d at any time giving the permissions
/// back to the extension.
/// - An extension permissions follow the all-or-nothing policy. Either all of
/// the requested permissions are granted or none of them (can't install).
```

The extension can be used to implement custom trading logic. It can be used alongside
`TransferPolicy.rules` and `PurchaseCap` to implement more advanced functionality.

```rust
/// ### Examples:
/// - An Auction extension can utilize the storage to store Auction-related data
/// while utilizing the same `Kiosk` object that the items are stored in.
/// - A Marketplace extension that implements custom events and fees for the
/// default trading functionality.
///
/// ### Notes:
/// - Trading functionality can utilize the `PurchaseCap` to build a custom
/// logic around the purchase flow. However, it should be carefully managed to
/// prevent asset locking.
/// - `kiosk_extension` is a friend module to `kiosk` and has access to its
/// internal functions (such as `place_internal` and `lock_internal` to
/// implement custom authorization scheme for `place` and `lock` respectively).
```

### Extension struct

- `storage` is a `Bag` inside the extension which is accessed by the 3rd-party app.
- `permissions` define the authorization level of the extension regarding the `place` and `lock` operations.
- `is_enabled` is a boolean flag to enable/disable the extension, toggled by the Kiosk Owner.

```rust
/// The Extension struct contains the data used by the extension and the
/// configuration for this extension. Stored under the `ExtensionKey`
/// dynamic field.
public struct Extension has store {
    /// Storage for the extension, an isolated Bag. By putting the extension
    /// into a single dynamic field, we reduce the amount of fields on the
    /// top level (eg items / listings) while giving extension developers
    /// the ability to store any data they want.
    storage: Bag,
    /// Bitmap of permissions that the extension has (can be revoked any
    /// moment). It's all or nothing policy - either the extension has the
    /// required permissions or no permissions at all.
    ///
    /// 1st bit - `place` - allows to place items for sale
    /// 2nd bit - `lock` and `place` - allows to lock items (and place)
    ///
    /// For example:
    /// - `10` - allows to place items and lock them.
    /// - `11` - allows to place items and lock them (`lock` includes `place`).
    /// - `01` - allows to place items, but not lock them.
    /// - `00` - no permissions.
    permissions: u128,
    /// Whether the extension can call protected actions. By default, all
    /// extensions are enabled (on `add` call), however the Kiosk
    /// owner can disable them at any time.
    ///
    /// Disabling the extension does not limit its access to the storage.
    is_enabled: bool,
}
```

A kiosk-owner can install an extension to their `Kiosk`. Notice the first argument,
which is actually a witness to the extension type. This means that an extension works
through a separate module which is owned by the app.

```rust
/// Add an extension to the Kiosk. Can only be performed by the owner. The
/// extension witness is required to allow extensions define their set of
/// permissions in the custom `add` call.
public fun add<Ext: drop>(
    _ext: Ext,
    self: &mut Kiosk,
    cap: &KioskOwnerCap,
    permissions: u128,
    ctx: &mut TxContext
) {
    assert!(self.has_access(cap), ENotOwner);
    df::add(
        self.uid_mut_as_owner(cap),
        ExtensionKey<Ext> {},
        Extension {
            storage: bag::new(ctx),
            permissions,
            is_enabled: true,
        }
    )
}
```

Similarly, the kiosk-owner can remove the extension. However its storage must be empty.

```rust
/// Remove an extension from the Kiosk. Can only be performed by the owner,
/// the extension storage must be empty for the transaction to succeed.
public fun remove<Ext: drop>(
    self: &mut Kiosk, cap: &KioskOwnerCap
) {
    assert!(self.has_access(cap), ENotOwner);
    assert!(is_installed<Ext>(self), EExtensionNotInstalled);

    let Extension {
        storage,
        permissions: _,
        is_enabled: _,
    } = df::remove(self.uid_mut_as_owner(cap), ExtensionKey<Ext> {});

    storage.destroy_empty();
}
```

No matter the storage's status, the kiosk-owner can disable/enable the extension.

```rust
/// Revoke permissions from the extension. While it does not remove the
/// extension completely, it keeps it from performing any protected actions.
/// The storage is still available to the extension (until it's removed).
public fun disable<Ext: drop>(
    self: &mut Kiosk,
    cap: &KioskOwnerCap,
) {
    assert!(self.has_access(cap), ENotOwner);
    assert!(is_installed<Ext>(self), EExtensionNotInstalled);
    extension_mut<Ext>(self).is_enabled = false;
}

/// Re-enable the extension allowing it to call protected actions (eg
/// `place`, `lock`). By default, all added extensions are enabled. Kiosk
/// owner can disable them via `disable` call.
public fun enable<Ext: drop>(
    self: &mut Kiosk,
    cap: &KioskOwnerCap,
) {
    assert!(self.has_access(cap), ENotOwner);
    assert!(is_installed<Ext>(self), EExtensionNotInstalled);
    extension_mut<Ext>(self).is_enabled = true;
}
```

The `storage: Bag` it owned by the app, as it is accessed by the `Ext` witness.

```rust
/// Get immutable access to the extension storage. Can only be performed by
/// the extension as long as the extension is installed.
public fun storage<Ext: drop>(
    _ext: Ext, self: &Kiosk
): &Bag {
    assert!(is_installed<Ext>(self), EExtensionNotInstalled);
    &extension<Ext>(self).storage
}

/// Get mutable access to the extension storage. Can only be performed by
/// the extension as long as the extension is installed. Disabling the
/// extension does not prevent it from accessing the storage.
///
/// Potentially dangerous: extension developer can keep data in a Bag
/// therefore never really allowing the KioskOwner to remove the extension.
/// However, it is the case with any other solution (1) and this way we
/// prevent intentional extension freeze when the owner wants to ruin a
/// trade (2) - eg locking extension while an auction is in progress.
///
/// Extensions should be crafted carefully, and the KioskOwner should be
/// aware of the risks.
public fun storage_mut<Ext: drop>(
    _ext: Ext, self: &mut Kiosk
): &mut Bag {
    assert!(is_installed<Ext>(self), EExtensionNotInstalled);
    &mut extension_mut<Ext>(self).storage
}
```

Depending on the permissions when installed, and the `is_enabled` status, the extension
can perform `place` and `lock` operations.

> ℹ️ This is crucial to the target of this section, which is airdropping to a user's `Kiosk`.

```rust
/// Protected action: place an item into the Kiosk. Can be performed by an
/// authorized extension. The extension must have the `place` permission or
/// a `lock` permission.
///
/// To prevent non-tradable items from being placed into `Kiosk` the method
/// requires a `TransferPolicy` for the placed type to exist.
public fun place<Ext: drop, T: key + store>(
    _ext: Ext, self: &mut Kiosk, item: T, _policy: &TransferPolicy<T>
) {
    assert!(is_installed<Ext>(self), EExtensionNotInstalled);
    assert!(can_place<Ext>(self) || can_lock<Ext>(self), EExtensionNotAllowed);

    self.place_internal(item)
}

/// Protected action: lock an item in the Kiosk. Can be performed by an
/// authorized extension. The extension must have the `lock` permission.
public fun lock<Ext: drop, T: key + store>(
    _ext: Ext, self: &mut Kiosk, item: T, _policy: &TransferPolicy<T>
) {
    assert!(is_installed<Ext>(self), EExtensionNotInstalled);
    assert!(can_lock<Ext>(self), EExtensionNotAllowed);

    self.lock_internal(item)
}
```

## Plan of Action

1. Update our contract to include:
    1. an extension witness,
    2. the interface for a `Kiosk` owner to add it to their Kiosk,
    3. function to mint directly to a user's `Kiosk` in locked state, using the extension.
2. Add our new extension to the seller's `Kiosk`.
3. Mint directly to the seller's `Kiosk` with our new `mint()` function (1.3).

### 1. Update contract

As above we want to update our contract to include:
1. an extension witness,
2. the interface for a `Kiosk` owner to add it to their Kiosk,
3. function to mint directly to a user's `Kiosk` in locked state, using the extension.

<details>
<summary>Solution</summary>

There is a lot of room here for creativity, here is a simple implementation:

#### 1. Create extension module

Create a new move file inside _sources_ folder called _kiosk_extension.move_.

> ℹ️ Notice that we broke the convention of naming our module the same as the file, to differentiate this module from the `sui::kiosk_extension` module.

```rust
module awesome_nft::awesome_extension {
    use sui::kiosk::{Kiosk, KioskOwnerCap};
    use sui::kiosk_extension;
    use sui::transfer_policy::TransferPolicy;

    /// Value that represents the `lock` and `place` permission in the
    /// permissions bitmap.
    const LOCK: u128 = 2;

    /// Extension witness.
    public struct Ext has drop {}

    public fun add(kiosk: &mut Kiosk, cap: &KioskOwnerCap, ctx: &mut TxContext) {
        kiosk_extension::add(Ext {}, kiosk, cap, LOCK, ctx)
    }

    public(package) fun lock<T: key + store>(
        kiosk: &mut Kiosk, item: T, policy: &TransferPolicy<T>
    ) {
        kiosk_extension::lock(Ext {}, kiosk, item, policy)
    }
}
```

The extension witness:

```rust
/// Extension witness.
public struct Ext has drop {}
```

Interface for `Kiosk` owner to add the extension to their `Kiosk`.

> ℹ️ Notice that we do not need to also add the respective `remove` function, as the `Kiosk` owner can directly
call it via `sui::kiosk_extension::remove()`.

```rust
public fun add(kiosk: &mut Kiosk, cap: &KioskOwnerCap, ctx: &mut TxContext) {
    kiosk_extension::add(Ext {}, kiosk, cap, LOCK, ctx)
}
```

`LOCK = 2` which means our extension can lock on top of placing items in the `Kiosk` it is installed.
This constant is used in the above function when adding the extension.

We need lock permission in order to enforce royalties for our `AwesomeNFT`.
```rust
/// Value that represents the `lock` and `place` permission in the
/// permissions bitmap.
const LOCK: u128 = 2;
```

Function to lock an item in the `Kiosk`.

Notice that we expose this function only to our package, as we do not want anyone to be able to use our
extension to lock items.

```rust
/// Package can lock an item to a `Kiosk` with the extension.
public(package) fun lock<T: key + store>(
    kiosk: &mut Kiosk, item: T, policy: &TransferPolicy<T>
) {
    kiosk_extension::lock(Ext {}, kiosk, item, policy)
}
```

> ℹ️ Notice that we enable the package to lock any item in the `Kiosk` using our extension.
Depending on the requirements you might change the structure of which module depends on which and provide a different interface.

#### 2. Update mint function to directly lock inside a Kiosk

Here we use `awesome_extension` module to directly lock the newly minted `AwesomeNFT` inside a `Kiosk` with our extension.
We update our previous `new()` function as below. We also give it the new name `mint_to_kiosk()` to better reflect its function.

> ℹ️ In a real-world scenario, depending on the requirements, you might want to split the operation in two steps, minting and locking.

```rust
/// Creates a new AwesomeNFT and locks it in the Kiosk `kiosk`.
/// Note that `kiosk` should have the extension `awesome_nft::awesome_extension::Ext` installed.
public fun mint_to_kiosk(
    _: &MintCap,
    name: String,
    description: String,
    link: String,
    image_url: String,
    thumbnail_url: String,
    project_url: String,
    creator: String,
    kiosk: &mut Kiosk,
    policy: &TransferPolicy<AwesomeNFT>,
    ctx: &mut TxContext
) {
    awesome_extension::lock(
        kiosk, 
        AwesomeNFT {
            id: object::new(ctx),
            name,
            description,
            link,
            image_url,
            thumbnail_url,
            project_url,
            creator
        },
        policy
    );
}
```

Now that we have included the `awesome_nft` module in our package, go ahead and publish it using _<span>publish.sh</span>_

</details>

### 2. Add extension to seller's `Kiosk`

As we now directly mint to the `Kiosk` we need:
1. a `Kiosk` with our extension.
2. a `TransferPolicy`

For this step we have included _<span>create-seller-kiosk.sh</span>_.

You can either create a new file for adding an extension to the already created `Kiosk`, or modify the existing script to include
the addition of the extension in a single transaction.

> ℹ️ In a real world scenario we should always choose to combine multiple steps in a single Programmable Transaction Block (ptb) for
better user experience.

<details>
<summary>Solution</summary>

Instead of calling `sui::kiosk::default`, we use `sui::kiosk::new`, add the extension using our cap, keep the cap, and share the `Kiosk`.
```bash
#!/bin/bash

# Load variables from .env file
if [ -f .env ]; then
    source .env
else
    echo "No .env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to seller address
sui client switch --address seller

kiosk_type="<sui::kiosk::Kiosk>"
# Create a Kiosk with extension and keep its cap.
kiosk_res=$(sui client ptb --move-call \
    0x2::kiosk::new \
    --assign kiosk_res \
    --assign kiosk kiosk_res.0 \
    --assign cap kiosk_res.1 \
    --move-call \
        $PACKAGE_ID::awesome_extension::add \
        kiosk \
        cap \
    --transfer-objects [cap] @$SELLER_ADDRESS \
    --move-call \
        0x2::transfer::public_share_object \
        $kiosk_type \
        kiosk \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
KIOSK_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | endswith("2::kiosk::Kiosk")).objectId')
KIOSK_CAP_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::kiosk::KioskOwnerCap")).objectId')

# Save the Kiosk's and KioskOwnerCap's ids in a file
cat > .seller.kiosk.env <<-KIOSK_ENV
SELLER_KIOSK_ID=$KIOSK_ID
SELLER_KIOSK_CAP_ID=$KIOSK_CAP_ID

KIOSK_ENV
```

Go ahead and run it!
</details>

### 3. Create the TransferPolicy

We need to create a `TransferPolicy` which enforces royalties for our `AwesomeNFT`.
We have included the script _<span>policy-with-enforced-royalties.sh</span>_ from the previous section.
Go ahead and run it!

### 4. Mint directly to the seller's `Kiosk`

We have included _<span>mint.sh</span>_ from the previous section. Can you edit it to use our new `mint_to_kiosk` function?

<details>
<summary>Solution</summary>

Notice that we have
- Changed the function name.
- Included `TransferPolicy` and `Kiosk` arguments.
- Removed the `--transfer-objects` call.

```bash
#!/bin/bash

# Load variables from .env file
if [ -f .env ] && [ -f .seller.kiosk.env ] && [ -f .transfer_policy.env ]; then
    source .env
    source .seller.kiosk.env
    source .transfer_policy.env
else
    echo "No .env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# admin has the MintCap
sui client switch --address admin

# mint the NFT
mint_res=$(sui client ptb --move-call \
    $PACKAGE_ID::awesome_nft::mint_to_kiosk \
        @$MINT_CAP \
        "'name'" \
        "'description'" \
        "'link'" \
        "'image_url'" \
        "'thumbnail_url'" \
        "'project_url'" \
        "'creator'" \
        @$SELLER_KIOSK_ID \
        @$TRANSFER_POLICY_ID \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse AwesomeNFT's id from the mint response
NFT_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("::awesome_nft::AwesomeNFT")).objectId')

cat > .nft.env <<-NFT_ENV
NFT_ID=$NFT_ID

NFT_ENV
```

Go ahead and run it! Using the `awesome_extension::Ext` extension we are able to airdrop `AwesomeNFT`s directly to seller's `Kiosk`.
If we open the `SELLER_KIOSK_ID` in any explorer we will see that the newly minted `AwesomeNFT` is placed inside it in locked state!

Now the seller can either keep the `AwesomeNFT` or trade it locked with royalties enforced!

</details>

## Well done!

We have successfully implemented a direct airdrop to a user's `Kiosk` using an extension.
Of course the user needs to have the extension installed. Which means accepting the extension to be able to place and lock items inside their `Kiosk`.
Even if they accept to do so, they always have the power to disable the extension.
This goes according to kiosk's philosophy, which is to give the user full control over their assets, along with the ability to trade them in a secure way.

Have we completely enforced royalties though? No! There exists an unconventional/hacky way to handle `Kiosk`s, by transferring the `KioskOwnerCap`s.
As `KioskOwnerCap`s have the `store` ability, they are freely transferable in the Sui blockchain. Theoretically, a user could trade the `Kiosk` itself,
by transferring the `KioskOwnerCap`. This would essentially give ownership of all items inside that `Kiosk` to the new owner of `KioskOwnerCap`.
By doing that the items have changed ownership without checking the `TransferPolicy` rules applied to them!

In the next section we will see how `PersonalKioskCap` solves this issue.

