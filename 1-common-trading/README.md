# Common use of kiosk for trading.

Now that we have seen how to mint an NFT, let's see how we can trade it.

Taking a look at the [kiosk module](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/kiosk.move)
we are greeted with a [docstring](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/kiosk.move#L4C1-L82C72)

Let's go through the important parts step by step:

### Principles and Philosophy

Even though `Kiosk` is a shared object, it is only its owner who can manage the assets in it.

```
/// - Kiosk provides guarantees of "true ownership"; - just like single owner
/// objects, assets stored in the Kiosk can only be managed by the Kiosk owner.
/// Only the owner can `place`, `take`, `list`, perform any other actions on
/// assets in the Kiosk.
```

The default flow for trading is `list` + `purchase`, but we can implement any other trading logic on top of it using `list_with_purchase_cap` and `purchase_with_cap`.
The later will be demonstrated in a next section.

> ℹ️ Take a note of `list` + `purchase` flow, as this is the default trading logic we will be using in this section.

```
/// - Kiosk aims to be generic - allowing for a small set of default behaviors
/// and not imposing any restrictions on how the assets can be traded. The only
/// default scenario is a `list` + `purchase` flow; any other trading logic can
/// be implemented on top using the `list_with_purchase_cap` (and a matching
/// `purchase_with_cap`) flow.
```

Every time a transaction happens, and more specifically, on `purchase`, a `TransferRequest` is created.

> ℹ️ Note that the `TransferRequest` enables asset creators to control how their assets are traded.

```
/// - For every transaction happening with a third party a `TransferRequest` is
/// created - this way creators are fully in control of the trading experience.
```

### Asset states

The basic state of an asset inside a Kiosk. Every asset inside a Kiosk is `placed`.

```
/// - `placed` -  An asset is `place`d into the Kiosk and can be `take`n out by
/// the Kiosk owner; it's freely tradable and modifiable via the `borrow_mut`
/// and `borrow_val` functions.
```

Asset's in a `locked` state are locked inside the Kiosk. One needs to `list` or `list_with_purchase_cap` to be able to move it out of the Kiosk.

```
/// - `locked` - Similar to `placed` except that `take` is disabled and the only
/// way to move the asset out of the Kiosk is to `list` it or
/// `list_with_purchase_cap` therefore performing a trade (issuing a
/// `TransferRequest`). The check on the `lock` function makes sure that the
/// `TransferPolicy` exists to not lock the item in a `Kiosk` forever.
```

`listed` means that the Kiosk owner has set the item as available for `purchase`. The item can not be taken or modified while it is `listed`.

```
/// - `listed` - A `place`d or a `lock`ed item can be `list`ed for a fixed price
/// allowing anyone to `purchase` it from the Kiosk. While listed, an item can
/// not be taken or modified. However, an immutable borrow via `borrow` call is
/// still available. The `delist` function returns the asset to the previous
/// state.
```

We will cover `listed_exclusively` state in a later section.

```
/// - `listed_exclusively` - ...
```

### Using multiple Transfer Policies for different "tracks":

This is a very important part of the kiosk ecosystem. We see that in order to trade an asset, a `TransferRequest` needs to be resolved using a `TransferPolicy`. This is where the creator of the asset can set (or not) rules for trading.

> ℹ️ We need a `TransferPolicy` in order to trade an asset.

While the default scenario implies that there should be a single `TransferPolicy<T>` for `T`, it is possible to have multiple, each one having its own set of rules. Note that in case of multiple **available** TransferPolicies, the buyer can use any of them to resolve the `TransferRequest`.

> ℹ️ In a way, multiple TransferPolicies function as an OR condition on resolving the `TransferRequest`.

```
/// Every `purchase` or `purchase_with_purchase_cap` creates a `TransferRequest`
/// hot potato which must be resolved in a matching `TransferPolicy` for the
/// transaction to pass. While the default scenario implies that there should be
/// a single `TransferPolicy<T>` for `T`; it is possible to have multiple, each
/// one having its own set of rules.
```

Let's go take a look into the [transfer_policy module](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/transfer_policy.move) as it is an essential part of using Kiosks for trading.

Again, we are greeted by a thorough [docstring](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/transfer_policy.move#L4C1-L23C25)

The type-owner, ie. the creator of the asset, can set custom transfer rules for every deal, ie. trade happening in the Kiosk.

```
/// - TransferPolicy - is a highly customizable primitive, which provides an
/// interface for the type owner to set custom transfer rules for every
/// deal performed in the `Kiosk` or a similar system that integrates with TP.
```

We need at least one `TransferPolicy` for the asset to be tradable in a Kiosk, in order to be able to resolve the `TransferRequest` hot-potato.

```
/// - Once a `TransferPolicy<T>` is created for and shared (or frozen), the
/// type `T` becomes tradable in `Kiosk`s. On every purchase operation, a
/// `TransferRequest` is created and needs to be confirmed by the `TransferPolicy`
/// hot potato or transaction will fail.
```

The creator can add rules to the `TransferPolicy` that the `TransferRequest` needs to confirm in the same transaction-block.
`confirm_request` is the function that checks the two in order to resolve the `TransferRequest`.

> ℹ️ Take a note on the `confirm_request` function, as this is the function we will be using to resolve the `TransferRequest`.

```
/// - Type owner (creator) can set any Rules as long as the ecosystem supports
/// them. All of the Rules need to be resolved within a single transaction (eg
/// pay royalty and pay fixed commission). Once required actions are performed,
/// the `TransferRequest` can be "confirmed" via `confirm_request` call.
```

`TransferPolicy` also acts as a control-center for the creator to control trades of their assets and collect possible profits such as royalties.
A change on the `TransferPolicy` is instantly reflected on the trading of their assets.

```
/// - `TransferPolicy` aims to be the main interface for creators to control trades
/// of their types and collect profits if a fee is required on sales. Custom
/// policies can be removed at any moment, and the change will affect all instances
/// of the type at once.
```

## Summary

Summarizing the above we have a pretty good idea of how a basic trading flow in a Kiosk works:

1. a `TransferPolicy` is needed for the asset to be tradable in a Kiosk.
2. the seller needs to `list` an asset for sale.
3. the buyer needs to `purchase` the asset which creates a `TransferRequest`.
4. the buyer needs to `confirm_request` the `TransferRequest` using the `TransferPolicy`.

## Code

Below we present the code inside the above modules that is relevant for this section.
Please take a moment to read through the code and try to understand it.
The code is thoroughly documented and should be easy to follow.

### `kiosk::Kiosk`

```
/// An object which allows selling collectibles within "kiosk" ecosystem.
/// By default gives the functionality to list an item openly - for anyone
/// to purchase providing the guarantees for creators that every transfer
/// needs to be approved via the `TransferPolicy`.
public struct Kiosk has key, store {
    id: UID,
    /// Balance of the Kiosk - all profits from sales go here.
    profits: Balance<SUI>,
    /// Always point to `sender` of the transaction.
    /// Can be changed by calling `set_owner` with Cap.
    owner: address,
    /// Number of items stored in a Kiosk. Used to allow unpacking
    /// an empty Kiosk if it was wrapped or has a single owner.
    item_count: u32,
    /// [DEPRECATED] Please, don't use the `allow_extensions` and the matching
    /// `set_allow_extensions` function - it is a legacy feature that is being
    /// replaced by the `kiosk_extension` module and its Extensions API.
    ///
    /// Exposes `uid_mut` publicly when set to `true`, set to `false` by default.
    allow_extensions: bool
}
```

### `kiosk::KioskOwnerCap`

```
/// A Capability granting the bearer a right to `place` and `take` items
/// from the `Kiosk` as well as to `list` them and `list_with_purchase_cap`.
public struct KioskOwnerCap has key, store {
    id: UID,
    `for`: ID
}
```

### `transfer_policy::TransferPolicy`

```
/// A unique capability that allows the owner of the `T` to authorize
/// transfers. Can only be created with the `Publisher` object. Although
/// there's no limitation to how many policies can be created, for most
/// of the cases there's no need to create more than one since any of the
/// policies can be used to confirm the `TransferRequest`.
public struct TransferPolicy<phantom T> has key, store {
    id: UID,
    /// The Balance of the `TransferPolicy` which collects `SUI`.
    /// By default, transfer policy does not collect anything , and it's
    /// a matter of an implementation of a specific rule - whether to add
    /// to balance and how much.
    balance: Balance<SUI>,
    /// Set of types of attached rules - used to verify `receipts` when
    /// a `TransferRequest` is received in `confirm_request` function.
    ///
    /// Additionally provides a way to look up currently attached Rules.
    rules: VecSet<TypeName>
}
```

### `transfer_policy::TransferPolicyCap`

```
/// A Capability granting the owner permission to add/remove rules as well
/// as to `withdraw` and `destroy_and_withdraw` the `TransferPolicy`.
public struct TransferPolicyCap<phantom T> has key, store {
    id: UID,
    policy_id: ID
}
```

### `transfer_policy::TransferRequest`

```
/// A "Hot Potato" forcing the buyer to get a transfer permission
/// from the item type (`T`) owner on purchase attempt.
public struct TransferRequest<phantom T> {
    /// The ID of the transferred item. Although the `T` has no
    /// constraints, the main use case for this module is to work
    /// with Objects.
    item: ID,
    /// Amount of SUI paid for the item. Can be used to
    /// calculate the fee / transfer policy enforcement.
    paid: u64,
    /// The ID of the Kiosk / Safe the object is being sold from.
    /// Can be used by the TransferPolicy implementors.
    from: ID,
    /// Collected Receipts. Used to verify that all of the rules
    /// were followed and `TransferRequest` can be confirmed.
    receipts: VecSet<TypeName>
}
```

### `transfer_policy::new()`

```
/// Register a type in the Kiosk system and receive a `TransferPolicy` and
/// a `TransferPolicyCap` for the type. The `TransferPolicy` is required to
/// confirm kiosk deals for the `T`. If there's no `TransferPolicy`
/// available for use, the type can not be traded in kiosks.
public fun new<T>(
    pub: &Publisher, ctx: &mut TxContext
): (TransferPolicy<T>, TransferPolicyCap<T>) {
    assert!(package::from_package<T>(pub), 0);
    let id = object::new(ctx);
    let policy_id = id.to_inner();

    event::emit(TransferPolicyCreated<T> { id: policy_id });

    (
        TransferPolicy { id, rules: vec_set::empty(), balance: balance::zero() },
        TransferPolicyCap { id: object::new(ctx), policy_id }
    )
}
```

### `transfer_policy::default()`

```
/// Initialize the Transfer Policy in the default scenario: Create and share
/// the `TransferPolicy`, transfer `TransferPolicyCap` to the transaction
/// sender.
entry fun default<T>(pub: &Publisher, ctx: &mut TxContext) {
    let (policy, cap) = new<T>(pub, ctx);
    sui::transfer::share_object(policy);
    sui::transfer::transfer(cap, ctx.sender());
}
```

### `kiosk::new()`

```
/// Creates a new `Kiosk` with a matching `KioskOwnerCap`.
public fun new(ctx: &mut TxContext): (Kiosk, KioskOwnerCap) {
    let kiosk = Kiosk {
        id: object::new(ctx),
        profits: balance::zero(),
        owner: ctx.sender(),
        item_count: 0,
        allow_extensions: false
    };

    let cap = KioskOwnerCap {
        id: object::new(ctx),
        `for`: object::id(&kiosk)
    };

    (kiosk, cap)
}
```

### `kiosk::default()`

```
/// Creates a new Kiosk in a default configuration: sender receives the
/// `KioskOwnerCap` and becomes the Owner, the `Kiosk` is shared.
entry fun default(ctx: &mut TxContext) {
    let (kiosk, cap) = new(ctx);
    sui::transfer::transfer(cap, ctx.sender());
    sui::transfer::share_object(kiosk);
}
```

### `kiosk::place()`

```
/// Place any object into a Kiosk.
/// Performs an authorization check to make sure only owner can do that.
public fun place<T: key + store>(
    self: &mut Kiosk, cap: &KioskOwnerCap, item: T
) {
    assert!(self.has_access(cap), ENotOwner);
    self.place_internal(item)
}
```

### `kiosk::list()`

Notice that to `list` an item, it first needs to be `placed` in the Kiosk.

```
/// List the item by setting a price and making it available for purchase.
/// Performs an authorization check to make sure only owner can sell.
public fun list<T: key + store>(
    self: &mut Kiosk, cap: &KioskOwnerCap, id: ID, price: u64
) {
    assert!(self.has_access(cap), ENotOwner);
    assert!(self.has_item_with_type<T>(id), EItemNotFound);
    assert!(!self.is_listed_exclusively(id), EListedExclusively);

    df::add(&mut self.id, Listing { id, is_exclusive: false }, price);
    event::emit(ItemListed<T> { kiosk: object::id(self), id, price })
}
```

### `kiosk::place_and_list()`

```
/// Calls `place` and `list` together - simplifies the flow.
public fun place_and_list<T: key + store>(
    self: &mut Kiosk, cap: &KioskOwnerCap, item: T, price: u64
) {
    let id = object::id(&item);
    self.place(cap, item);
    self.list<T>(cap, id, price)
}
```

### `kiosk::purchase()`

```
/// Make a trade: pay the owner of the item and request a Transfer to the `target`
/// kiosk (to prevent item being taken by the approving party).
///
/// Received `TransferRequest` needs to be handled by the publisher of the T,
/// if they have a method implemented that allows a trade, it is possible to
/// request their approval (by calling some function) so that the trade can be
/// finalized.
public fun purchase<T: key + store>(
    self: &mut Kiosk, id: ID, payment: Coin<SUI>
): (T, TransferRequest<T>) {
    let price = df::remove<Listing, u64>(&mut self.id, Listing { id, is_exclusive: false });
    let inner = dof::remove<Item, T>(&mut self.id, Item { id });

    self.item_count = self.item_count - 1;
    assert!(price == payment.value(), EIncorrectAmount);
    df::remove_if_exists<Lock, bool>(&mut self.id, Lock { id });
    coin::put(&mut self.profits, payment);

    event::emit(ItemPurchased<T> { kiosk: object::id(self), id, price });

    (inner, transfer_policy::new_request(id, price, object::id(self)))
}
```

### `transfer_policy::confirm_request()`

```
/// Allow a `TransferRequest` for the type `T`. The call is protected
/// by the type constraint, as only the publisher of the `T` can get
/// `TransferPolicy<T>`.
///
/// Note: unless there's a policy for `T` to allow transfers,
/// Kiosk trades will not be possible.
public fun confirm_request<T>(
    self: &TransferPolicy<T>, request: TransferRequest<T>
): (ID, u64, ID) {
    let TransferRequest { item, paid, from, receipts } = request;
    let mut completed = receipts.into_keys();
    let mut total = completed.length();

    assert!(total == self.rules.size(), EPolicyNotSatisfied);

    while (total > 0) {
        let rule_type = completed.pop_back();
        assert!(self.rules.contains(&rule_type), EIllegalRule);
        total = total - 1;
    };

    (item, paid, from)
}
```

### `kiosk::withdraw()`

```
/// Withdraw profits from the Kiosk.
public fun withdraw(
    self: &mut Kiosk, cap: &KioskOwnerCap, amount: Option<u64>, ctx: &mut TxContext
): Coin<SUI> {
    assert!(self.has_access(cap), ENotOwner);

    let amount = if (amount.is_some()) {
        let amt = amount.destroy_some();
        assert!(amt <= self.profits.value(), ENotEnough);
        amt
    } else {
        self.profits.value()
    };

    coin::take(&mut self.profits, amount, ctx)
}
```

## Plan of action

Remember the summary above? Let's put it into action.

> ℹ️ Below we solve the tasks using bash scripts. You are advised to look at _<span>mint.sh</span>_ and try to write the scripts yourself before looking at the solution.
Notice though that due to syntax particularities of `sui cli ptb`s, and how they play on bash & terminal, it is okay to take a look when you are stuck, and then try to write the script yourself.
As you get more familiar with it, you should be able to write the scripts without looking at the solution. Also, feel free to use already written scripts as a reference for future scripts.
Lastly, try to run every script in the terminal and take a look at the items created or mutated in your favorite explorer. You can use https://explorer.polymedia.app/ in case you are using localnet environment.

#### 0. Publish

By running the _<span>publish.sh</span>_ script, you can publish the contract to your current sui environment and store the necessary information in a new `.env` file.

#### 1. Enable the trading of AwesomeNFT through the kiosk ecosystem.

Be sure to save any important information that you might need later on for trading.

<details>
    <summary>Solution</summary>
    Create a `TransferPolicy` using the `Publisher` of the <i>awesome_nft</i> package.

```bash
#!/bin/bash
if [ -f .env ]; then
    source .env
else
    echo "No .env file found"
    exit 1
fi
if [ -f .transfer_policy.env ]; then
    echo "Transfer policy already created."
    echo "It is advised to not have more than one transfer policy"
    echo "as the purchaser can freely choose which one to use."
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to admin address
sui client switch --address admin

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Create a TransferPolicy and keep its TransferPolicyCap
mint_res=$(sui client ptb --move-call \
    0x2::transfer_policy::default \
        $nft_type \
        @$PUBLISHER \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
TRANSFER_POLICY_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicy<")).objectId')
TRANSFER_POLICY_CAP_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicyCap<")).objectId')

# Save the TransferPolicy's and TransferPolicyCap's ids in a file
cat > .transfer_policy.env <<-TRANSFER_POLICY_ENV
TRANSFER_POLICY_ID=$TRANSFER_POLICY_ID
TRANSFER_POLICY_CAP_ID=$TRANSFER_POLICY_CAP_ID

TRANSFER_POLICY_ENV
```

> ⚠️ Note that this step should be taken only once per asset type! Having multiple TransferPolicies for the same asset type, enables the buyer to choose which one to use. In this section there is no such risk, as we enable trading without any restrictions, but keep this in mind for future trading scenarios.
</details>

#### 2. Create a Kiosk for selling the AwesomeNFT.

Be sure to save any important information that you might need later on for trading.

<details>
    <summary>Solution</summary>
    Seller creates a <code>Kiosk</code> and keeps its <code>KioskOwnerCap</code>. <code>kiosk::default()</code> function is super handy for this.

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

# Create a Kiosk and keep it
kiosk_res=$(sui client ptb --move-call \
    0x2::kiosk::default \
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
</details>


#### 3. Airdrop the AwesomeNFT to the seller.

This is already done for you, in the previous section. You can use _<span>mint.sh</span>_ to mint an NFT and airdrop it to the seller.
This will also store the newly minted NFT's id in the _.nft.env_ file.

#### 4. List the AwesomeNFT for sale.

<details>
    <summary>Solution</summary>
    Seller places and lists the AwesomeNFT for sale. <code>kiosk::place_and_list()</code> function is super handy for this.

```bash
#!/bin/bash

# Load variables from .env, .nft.env and .seller.kiosk.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .seller.kiosk.env ]; then
    source .env
    source .nft.env
    source .seller.kiosk.env
else
    echo "No .env, .nft.env or .seller.kiosk.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
LISTING_PRICE=5_000_000_000  # 5 SUI

# Switch to seller address
sui client switch --address seller

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Place and list NFT for sale
sui client ptb --move-call \
    0x2::kiosk::place_and_list \
        $nft_type \
        @$SELLER_KIOSK_ID \
        @$SELLER_KIOSK_CAP_ID \
        @$NFT_ID \
        $LISTING_PRICE \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

#### 5. Purchase the AwesomeNFT.

<details>
    <summary>Solution</summary>
    Buyer puchases the AwesomeNFT by id from the seller's Kiosk. After that the buyer needs to confirm the request. Note that the <code>TransferPolicy</code> is empty, so no extra steps are needed before calling <code>confirm_request</code>.

```bash
#!/bin/bash

# Load variables from *.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .seller.kiosk.env ] && [ -f .transfer_policy.env ]; then
    source .env
    source .nft.env
    source .seller.kiosk.env
    source .transfer_policy.env
else
    echo "No .env, .nft.env or .seller.kiosk.env file found"
    exit 1
fi

GAS_BUDGET=5_100_000_000  # 5.1 SUI

# Switch to admin address
sui client switch --address buyer

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Purchase and resolve TransferRequest
sui client ptb \
    --split-coins gas [5_000_000_000] \
    --assign payment \
    --move-call \
    0x2::kiosk::purchase \
        $nft_type \
        @$SELLER_KIOSK_ID \
        @$NFT_ID \
        payment \
    --assign purchase \
    --transfer-objects [purchase.0] @$BUYER_ADDRESS \
    --move-call \
    0x2::transfer_policy::confirm_request \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        purchase.1 \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

#### 6. Withdraw the profits from the Kiosk.

<details>
    <summary>Solution</summary>
    Seller withdraws the profits from the Kiosk.

```bash
#!/bin/bash

# Load variables from .env, .nft.env and .seller.kiosk.env files
if [ -f .env ] && [ -f .seller.kiosk.env ]; then
    source .env
    source .seller.kiosk.env
else
    echo "No .env, .seller.kiosk.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
WITHDRAW_AMOUNT=5_000_000_000  # 5 SUI

# Switch to seller address
sui client switch --address seller

# Withdraw profits from the kiosk
sui client ptb \
    --move-call \
    0x2::kiosk::withdraw \
        @$SELLER_KIOSK_ID \
        @$SELLER_KIOSK_CAP_ID \
        some\($WITHDRAW_AMOUNT\) \
    --assign profits \
    --transfer-objects \
        [profits] \
        @$SELLER_ADDRESS \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

## Well done!

You have successfully traded an NFT using the kiosk ecosystem. You have learned how to create a `TransferPolicy`, a `Kiosk`, list an item for sale, purchase an item, and withdraw profits from the Kiosk.

In the [next section](../2-royalties/README.md), we will explore how to pay royalties to the creator when trading via kiosk.

