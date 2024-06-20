# Enforce creator royalties

In the previous step we added royalties to the `TransferPolicy`, in order for the creator to receive a percentage on top of the sale price, when an `AwesomeNFT` is traded inside the kiosk ecosystem.

However, we can see that anyone can skip using kiosk and trade the NFT directly, without enforcing the royalty rule. 

More specifically we airdropped the NFT to the seller, who did not have any obligation to list it through their `Kiosk`. On top of that, even if the admin would directly sell their item through their `Kiosk`, the buyer after purchasing the NFT, could again trade it outside the kiosk ecosystem, skipping the royalty rule.

In this step we will enforce the royalty rule by adding a lock rule to the `TransferPolicy`.

## Lock rule

In the common kiosk rules in the [Kiosk](https://github.com/MystenLabs/apps/tree/main/kiosk) package (do not confuse with the `sui::kiosk` module), there exists a module called `kiosk_lock_rule`. Let's take a look at the `kiosk_lock_rule` module.

```rust
/// This module defines a Rule which forces buyers to put the purchased
/// item into the Kiosk and lock it. The most common use case for the
/// Rule is making sure an item never leaves Kiosks and has policies
/// enforced on every transfer.
///
/// Configuration:
/// - None
///
/// Use cases:
/// - Enforcing policies on every trade
/// - Making sure an item never leaves the Kiosk / certain ecosystem
///
/// Notes:
/// - "locking" mechanic disallows the `kiosk::take` function and forces
/// the owner to use `list` or `list_with_purchase_cap` methods if they
/// wish to move the item somewhere else.
```

So the `kiosk_lock_rule` works by enforcing the buyer/purchaser of an item from a `Kiosk`, to also `lock()` the item in their own `Kiosk`.
Locking the item after every `purchase()` disables the `kiosk::take()` function, so in a way, the item will always reside inside a `Kiosk`.

Note that this does not mean that the item/NFT is unavailable to be used in other contracts inside Sui, as there exist the following functions that are still enabled for a locked item, at least, as long as the corresponding `KioskOwnerCap` is provided.
- `kiosk::borrow()` for immutably borrowing the item.
- `kiosk::borrow_mut()` for mutably borrowing the item.
- `kiosk::borrow_val()` for borrowing the item by value using the Hot Potato pattern.

Now let's look at how lock rule is implemented:

Again a simple witness struct identifying the rule.
```rust
/// The type identifier for the Rule.
struct Rule has drop {}
```

No extra configuration needed, so the `Config` struct is empty.
```rust
/// An empty configuration for the Rule.
struct Config has store, drop {}
```

The creator using the `TransferPolicyCap` can add the rule to the `TransferPolicy`.
```rust
/// Creator: Adds a `kiosk_lock_rule` Rule to the `TransferPolicy` forcing
/// buyers to lock the item in a Kiosk on purchase.
public fun add<T>(policy: &mut TransferPolicy<T>, cap: &TransferPolicyCap<T>) {
    policy::add_rule(Rule {}, policy, cap, Config {})
}
```

To prove the rule, the purchaser needs to verify that the item is locked in a `Kiosk`.
This `Kiosk` should be their `Kiosk`, as in order to `kiosk::lock()` an item, one needs `KioskOwnerCap`.
```rust
/// Buyer: Prove the item was locked in the Kiosk to get the receipt and
/// unblock the transfer request confirmation.
public fun prove<T>(request: &mut TransferRequest<T>, kiosk: &Kiosk) {
    let item = policy::item(request);
    assert!(kiosk::has_item(kiosk, item) && kiosk::is_locked(kiosk, item), ENotInKiosk);
    policy::add_receipt(Rule {}, request)
}
```

Pretty straightforward, isn't it? Let's try and enforce royalties by adding the lock rule to the `TransferPolicy`.

## Plan of Action

In this section we copied, with minor edits, scripts from the previous section, that are repeated in this use-case.

In order to enforce royalties, the admin will also be the seller of the NFT, for ensuring the item will always be in a `Kiosk`.

> ℹ️ In later sections, we will see how airdrop can be done in a way that the item will be sold from the seller's `Kiosk`.

More specifically:
- _<span>mint.sh</span>_, now mints an `AwesomeNFT` and transfers it to the admin (not the seller as previously).
- _<span>create-admin-kiosk.sh</span>_, similar to _<span>create-seller-kiosk.sh</span>_, but for the admin.
- _<span>place-and-list.sh</span>_, uses admin keypair instead of seller.
- _<span>policy-with-royalties.sh</span>_, copied from the previous section, but you will need to edit it to add the lock rule (step 1).
- _<span>purchase.sh</span>_, copied from the previous section, replacing seller with admin where applicable, but you will need to include verification of the `kiosk_lock_rule` too (step 4).

### 0. Publish

By running the _<span>publish.sh</span>_ script, you can publish the contract to your current sui environment and store the necessary information in a new `.env` file.
Notice that in this case, this will also publish the _Kiosk_ package and store its id (same with the _awesome_nft_) in the _.rules.env_ file.

### 1. Admin edits the `TransferPolicy` to enforce royalties - lock rule.

As above open _<span>policy-with-royalties.sh</span>_ and add the lock rule to the `TransferPolicy`.

<details>
<summary>Solution</summary>

Addition of this snippet:
```bash
    --move-call ${RULES_PACKAGE_ID}::kiosk_lock_rule::add \
        $nft_type \
        policy \
        cap \
```

Whole script:
```bash
#!/bin/bash

# Load variables from *.env file
if [ -f .env ] && [ -f .rules.env ]; then
    source .env
    source .rules.env
else
    echo "No .env, or .rules.env file found"
    exit 1
fi
if [ -f .transfer_policy.env ]; then
    echo "Transfer policy already created."
    echo "It is advised to not have more than one transfer policy"
    echo "as the purchaser can freely choose which one to use."
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
ROYALTY_BPS=1000_u16  # 10%

# Switch to OWNER address
sui client switch --address admin

policy_type="<sui::transfer_policy::TransferPolicy<${PACKAGE_ID}::awesome_nft::AwesomeNFT>>"
nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Create a Kiosk, make it personal, and add extension.
policy_res=$(sui client ptb \
    --move-call 0x2::transfer_policy::new \
        $nft_type \
        @$PUBLISHER \
    --assign policy_and_cap \
    --assign policy policy_and_cap.0 \
    --assign cap policy_and_cap.1 \
    --move-call $RULES_PACKAGE_ID::royalty_rule::add \
        $nft_type \
        policy \
        cap \
        $ROYALTY_BPS \
        0 \
    --move-call ${RULES_PACKAGE_ID}::kiosk_lock_rule::add \
        $nft_type \
        policy \
        cap \
    --transfer-objects [cap] @$ADMIN_ADDRESS \
    --move-call \
        0x2::transfer::public_share_object \
        $policy_type \
        policy \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
TRANSFER_POLICY_ID=$(echo "$policy_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicy<")).objectId')
TRANSFER_POLICY_CAP_ID=$(echo "$policy_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicyCap<")).objectId')

# Save the TransferPolicy's and TransferPolicyCap's ids in a file
cat > .transfer_policy.env <<-TRANSFER_POLICY_ENV
TRANSFER_POLICY_ID=$TRANSFER_POLICY_ID
TRANSFER_POLICY_CAP_ID=$TRANSFER_POLICY_CAP_ID

TRANSFER_POLICY_ENV
```
</details>

### 2. Admin creates their own `Kiosk`

As above, we already have a script for this, _<span>create-admin-kiosk.sh</span>_. Go ahead and run it!

### 3. Admin mints and lists an NFT in their own `Kiosk`

Again, we already have scripts of these steps, _<span>mint.sh</span>_ and _<span>place-and-list.sh</span>_. Run them!

> ℹ️ Could this be more efficient? Sui's Programmable Transaction Blocks can be used to combine these steps into one script. This reduces risk for error, while also gas-cost! Feel free to do that.

### 4. Buyer purchases NFT from the admin.

Now the buyer in addition to purchasing and paying royalties, also needs to lock their newly purchased NFT in their Kiosk.


<details>
<summary>Solution</summary>

#### 1. Create a kiosk for buyer: Simply copy the _<span>create-admin-kiosk.sh</span>_ script and replace the below:
1. `sui client switch --address admin` with `sui client switch --address buyer`.
2.   
```bash
cat > .admin.kiosk.env <<-KIOSK_ENV
ADMIN_KIOSK_ID=$KIOSK_ID
ADMIN_KIOSK_CAP_ID=$KIOSK_CAP_ID

KIOSK_ENV
```
with
```bash
cat > .buyer.kiosk.env <<-KIOSK_ENV
BUYER_KIOSK_ID=$KIOSK_ID
BUYER_KIOSK_CAP_ID=$KIOSK_CAP_ID

KIOSK_ENV
```
#### 2. Purchase the NFT:

1. Include .buyer.kiosk.env previously created:
```bash
# Load variables from *.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .admin.kiosk.env ] && [ -f .buyer.kiosk.env ] && [ -f .transfer_policy.env ] && [ -f .rules.env ]; then
    source .env
    source .nft.env
    source .admin.kiosk.env
    source .buyer.kiosk.env
    source .transfer_policy.env
    source .rules.env
else
    echo "No .env, .nft.env, .admin.kiosk.env, .buyer.kiosk.env, .transfer_policy.env, or .rules.env file found"
    exit 1
fi
```

2. Insertion of this snippet:
```bash
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
```

Whole file:
```bash
#!/bin/bash

# Load variables from *.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .admin.kiosk.env ] && [ -f .buyer.kiosk.env ] && [ -f .transfer_policy.env ] && [ -f .rules.env ]; then
    source .env
    source .nft.env
    source .admin.kiosk.env
    source .buyer.kiosk.env
    source .transfer_policy.env
    source .rules.env
else
    echo "No .env, .nft.env, .admin.kiosk.env, .buyer.kiosk.env, .transfer_policy.env, or .rules.env file found"
    exit 1
fi

GAS_BUDGET=5_600_000_000  # 5.6 SUI

# Switch to admin address
sui client switch --address buyer

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Split the gas coin into 2 new coins, 5 SUI for purchase and 0.5 SUI for royalties.
# Then normally use kiosk::purchase with the 5 SUI coin.
# Then use royalty_rule::pay with the 0.5 SUI coin.
# Lastly lock the item in our Kiosk as buyer,
# before confirming the request with transfer_policy::confirm_request.
sui client ptb \
    --split-coins gas [5_000_000_000, 500_000_000] \
    --assign payment \
    --move-call \
    0x2::kiosk::purchase \
        $nft_type \
        @$SELLER_KIOSK_ID \
        @$NFT_ID \
        payment.0 \
    --assign purchase \
    --assign nft purchase.0 \
    --assign request purchase.1 \
    --move-call ${RULES_PACKAGE_ID}::royalty_rule::pay \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        request \
        payment.1 \
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

We have successfully applied `kiosk_lock_rule` to ensure that our NFT will always reside inside a `Kiosk` and will only be traded with royalties applied!

In the next section, we will look into how to "almost-airdrop" items to specific owners by using `PurchaseCap` and its functions: `list_with_purchase_cap()` and `purchase_with_cap()`.
