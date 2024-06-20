# Purchase with PurchaseCap

In the previous section, we saw how we can enforce royalties by using the `kiosk_lock_rule` alongside the `royalty_rule`.

In order to actually lock the item inside `Kiosk`s, we had to list the item directly after minting using our own `Kiosk`, ie. the admin's `Kiosk`.

In this section, we will see how we can send an item to a specific-user without them having to pay for it.

More specifically, we will use exclusive listing to enable an item to be purchasable only by a specific address.

In this way one can say we simulate an airdrop, with the difference that the item needs to be claimed by the receiving part.

Let's take a look at the way how `list_with_purchase_cap()`, `PurchaseCap` and `purchase_with_cap()` function to enable exclusive listing.

## List with Purchase Cap

The `list_with_purchase_cap()` function is used to list an item with a minimum price and returns a `PurchaseCap`.
We will see how `PurchaseCap` is used in `purchase_with_cap()` function below.

Apart from checking the `Kiosk` ownership, we see that the following checks need to pass:
1. The items is inside the `Kiosk` - ie. the item is placed inside the `Kiosk`.
2. The item is not already listed.

```rust
/// Creates a `PurchaseCap` which gives the right to purchase an item
/// for any price equal or higher than the `min_price`.
public fun list_with_purchase_cap<T: key + store>(
    self: &mut Kiosk, cap: &KioskOwnerCap, id: ID, min_price: u64, ctx: &mut TxContext
): PurchaseCap<T> {
    assert!(self.has_access(cap), ENotOwner);
    assert!(self.has_item_with_type<T>(id), EItemNotFound);
    assert!(!self.is_listed(id), EAlreadyListed);

    df::add(&mut self.id, Listing { id, is_exclusive: true }, min_price);

    PurchaseCap<T> {
        min_price,
        item_id: id,
        id: object::new(ctx),
        kiosk_id: object::id(self),
    }
}
```

If we compare it with the `list()` function we can see that the main difference is that we swap the check and addition of 
the `Listing` dynamic field regarding the `is_exclusive` field. More specifically:

**`list()`**
```rust
assert!(!self.is_listed_exclusively(id), EListedExclusively);

df::add(&mut self.id, Listing { id, is_exclusive: false }, price);
```

**`list_with_purchase_cap()`**
```rust
assert!(!self.is_listed(id), EAlreadyListed);

df::add(&mut self.id, Listing { id, is_exclusive: true }, min_price);
```

## PurchaseCap

The `PurchaseCap` includes the `kiosk_id` of the `Kiosk` that listed the item with `item_id`, along with its `min_price`.

```rust
/// A capability which locks an item and gives a permission to
/// purchase it from a `Kiosk` for any price no less than `min_price`.
///
/// Allows exclusive listing: only bearer of the `PurchaseCap` can
/// purchase the asset. However, the capability should be used
/// carefully as losing it would lock the asset in the `Kiosk`.
///
/// The main application for the `PurchaseCap` is building extensions
/// on top of the `Kiosk`.
public struct PurchaseCap<phantom T: key + store> has key, store {
    id: UID,
    /// ID of the `Kiosk` the cap belongs to.
    kiosk_id: ID,
    /// ID of the listed item.
    item_id: ID,
    /// Minimum price for which the item can be purchased.
    min_price: u64
}
```

## Purchase with Purchase Cap

The `purchase_with_cap()` works similar to `purchase()`, but it takes a `PurchaseCap` as an argument, which is deleted.
We see that along with the item, an `ActionRequest` is returned, ensuring that the `TransferPolicy` rules are still followed.

Similar to `purchase()` the `Listing` dynamic-field is removed and the `profits` are updated with the `payment` `Coin`.

Asserts are made to ensure that the correct `PurchaseCap` is used for the respective exclusive listing.

```rust
/// Unpack the `PurchaseCap` and call `purchase`. Sets the payment amount
/// as the price for the listing making sure it's no less than `min_amount`.
public fun purchase_with_cap<T: key + store>(
    self: &mut Kiosk, purchase_cap: PurchaseCap<T>, payment: Coin<SUI>
): (T, TransferRequest<T>) {
    let PurchaseCap { id, item_id, kiosk_id, min_price } = purchase_cap;
    id.delete();

    let id = item_id;
    let paid = payment.value();
    assert!(paid >= min_price, EIncorrectAmount);
    assert!(object::id(self) == kiosk_id, EWrongKiosk);

    df::remove<Listing, u64>(&mut self.id, Listing { id, is_exclusive: true });

    coin::put(&mut self.profits, payment);
    self.item_count = self.item_count - 1;
    df::remove_if_exists<Lock, bool>(&mut self.id, Lock { id });
    let item = dof::remove<Item, T>(&mut self.id, Item { id });

    (item, transfer_policy::new_request(id, paid, object::id(self)))
}
```

## Plan of Action

Now that we saw how we can list an item exclusively, let's see how we can use it in practice.

We will
1. List exclusively our newly minted NFT for the buyer to claim with 0 price.
2. Send the `PurchaseCap` to the buyer to enable them claiming.
3. The buyer can now claim the NFT by using `purchase_with_cap()`, but still following the `TransferPolicy` rules.

### 0. Publish

By running the _<span>publish.sh</span>_ script, you can publish the contract to your current sui environment and store the necessary information in a new `.env` file.
Notice that in this case, this will also publish the _Kiosk_ package and store its id (same with the _awesome_nft_) in the _.rules.env_ file.

### 1. Admin creates the `TransferPolicy` with the royalty and lock rules

We have included this file from the previous section: _<span>policy-with-enforced-royalties.sh</span>_. Go ahead and run it!

### 2. Admin mints an NFT and keeps it.

We have included this file from the previous section: _<span>mint.sh</span>_. Go ahead and run it!

### 3. Admin creates their own `Kiosk`.

As above, we already have a script for this, _<span>create-admin-kiosk.sh</span>_. Go ahead and run it!

### 4. Admin lists the NFT exclusively

We have included the file which simply lists an NFT: _<span>place-and-list.sh</span>_.
Can you edit it to list the NFT exclusively?

Make sure you store the `PURCHASE_CAP_ID` in a file to use it for purchasing.

<details>
<summary>Solution</summary>

Instead of `place_and_list` we first use `place` and then `list_with_purchase_cap`.
Lastly we transfer the `PurchaseCap` to the buyer.

```bash
#!/bin/bash

# Load variables from .env, .nft.env and .seller.kiosk.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .admin.kiosk.env ]; then
    source .env
    source .nft.env
    source .admin.kiosk.env
else
    echo "No .env, .nft.env or .admin.kiosk.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to admin address
sui client switch --address admin

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Place and list NFT for sale
list_res=$(sui client ptb \
    --move-call 0x2::kiosk::place \
        $nft_type \
        @$ADMIN_KIOSK_ID \
        @$ADMIN_KIOSK_CAP_ID \
        @$NFT_ID \
    --move-call 0x2::kiosk::list_with_purchase_cap \
        $nft_type \
        @$ADMIN_KIOSK_ID \
        @$ADMIN_KIOSK_CAP_ID \
        @$NFT_ID \
        0 \
    --assign purchase_cap \
    --transfer-objects [purchase_cap] @$BUYER_ADDRESS \
    --gas-budget $GAS_BUDGET \
    --json)

PURCHASE_CAP_ID=$(echo "$list_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::kiosk::PurchaseCap<")).objectId')
echo PURCHASE_CAP_ID=$PURCHASE_CAP_ID > .purchase_cap.env
```
</details>

### 4. Buyer claims the NFT

We have included the file which purchases an NFT from the previous section: _<span>purchase.sh</span>_.

Can you edit it to purchase the NFT with the `PurchaseCap` at 0 price?

<details>
<summary>Solution</summary>

#### 1. Buyer still needs to resolve a `TransferRequest`, so we need to have a buyer `Kiosk` to resolve the `kiosk_lock_rule`.

We already have a script for this, _<span>create-buyer-kiosk.sh</span>_. Go ahead and run it!

#### 2. `purchase_with_cap` and resolve the `TransferRequest`

As the listing price is 0, we can restore gas-budget to 
```bash
GAS_BUDGET=100_000_000  # 0.1 SUI
```

Even with the listing price being 0, we still need to pass the payment objects for it.
```bash
--move-call 0x2::coin::zero \
    $sui_type \
--assign payment \
--move-call 0x2::coin::zero \
    $sui_type \
--assign royalties_payment \
```

In `purchase_with_cap`, instead of using the `NFT_ID` we only need the `PURCHASE_CAP_ID` to purchase the NFT.
```bash
--move-call 0x2::kiosk::purchase_with_cap \
    $nft_type \
    @$ADMIN_KIOSK_ID \
    @$PURCHASE_CAP_ID \
    payment \
--assign purchase \
--assign nft purchase.0 \
--assign request purchase.1 \
```

Whole script:
```bash
#!/bin/bash

# Load variables from *.env files
if [ -f .env ] && [ -f .purchase_cap.env ] && [ -f .admin.kiosk.env ] && [ -f .buyer.kiosk.env ] && [ -f .transfer_policy.env ] && [ -f .rules.env ]; then
    source .env
    source .purchase_cap.env
    source .admin.kiosk.env
    source .buyer.kiosk.env
    source .transfer_policy.env
    source .rules.env
else
    echo "No .env, .purchase_cap.env, .admin.kiosk.env, .buyer.kiosk.env, .transfer_policy.env, or .rules.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to admin address
sui client switch --address buyer

sui_type="<0x2::sui::SUI>"
nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Create 2 new zero coins, for purchase and for royalties.
# Then use kiosk::purchase_with_cap.
# Then use royalty_rule::pay.
# Lastly lock the item in our Kiosk as buyer,
# before confirming the request with transfer_policy::confirm_request.
sui client ptb \
    --move-call 0x2::coin::zero \
        $sui_type \
    --assign payment \
    --move-call 0x2::coin::zero \
        $sui_type \
    --assign royalties_payment \
    --move-call 0x2::kiosk::purchase_with_cap \
        $nft_type \
        @$ADMIN_KIOSK_ID \
        @$PURCHASE_CAP_ID \
        payment \
    --assign purchase \
    --assign nft purchase.0 \
    --assign request purchase.1 \
    --move-call ${RULES_PACKAGE_ID}::royalty_rule::pay \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        request \
        royalties_payment \
    --move-call 0x2::kiosk::lock \
        $nft_type \
        @$BUYER_KIOSK_ID \
        @$BUYER_KIOSK_CAP_ID \
        @$TRANSFER_POLICY_ID \
        nft \
    --move-call ${RULES_PACKAGE_ID}::kiosk_lock_rule::prove \
        $nft_type \
        request \
        @$BUYER_KIOSK_ID \
    --move-call \
    0x2::transfer_policy::confirm_request \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        request \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

## Well done!

We have now seen how we can list an item exclusively and claim it using the `PurchaseCap`.

Notice as in the documentation, if we send the `PurchaseCap` to an address that will not use it, or an invalid address,
the item will be locked inside the `Kiosk` indefinitely.

This of course is important to consider. The seller would need to make sure that the buyer would indeed claim the item.

In the next section we will see how we can instead airdrop an item directly to a user's `Kiosk` using `kiosk_extension`.

