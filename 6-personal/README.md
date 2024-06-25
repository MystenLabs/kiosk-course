# Personal Kiosk

As we mentioned previously, a user could treat a `Kiosk` as a container which is traded, thus trading all the items inside it, by transferring their `KioskOwnerCap`,
thus avoiding fulfilling the contained items' transfer rules.

Personal Kiosk is a feature that can work on top of a `Kiosk` to ensure that the `KioskOwnerCap` will not be transferable,
and the `Kiosk` will be treated as a personal non-transferable container.

Let's take a look on the function of it. Personal Kiosk is implemented side by side with the kiosk rules package [here](https://github.com/MystenLabs/apps/blob/main/kiosk/sources/extensions/personal_kiosk.move).

## `kiosk::personal_kiosk`

### PersonalKioskCap

`personal_kiosk`'s solution is to simply wrap the `KioskOwnerCap` in a new struct, `PersonalKioskCap`, which is a `key`-only resource.
```rust
/// This module provides a wrapper for the KioskOwnerCap that makes the Kiosk
/// non-transferable and "owned".
///
module kiosk::personal_kiosk {

// ...


/// A key-only wrapper for the KioskOwnerCap. Makes sure that the Kiosk can
/// not be traded altogether with its contents.
struct PersonalKioskCap has key {
    id: UID,
    cap: Option<KioskOwnerCap>
}
```

Having a struct `key`-only means that it can only [be transferred by the same module](https://move-book.com/storage/transfer-restrictions.html).
If we search for any usages of the `sui::transfer::transfer()` function inside the module we only find the bellow one.
This means that only the transaction sender can keep the `PersonalKioskCap` in their account.

```rust
/// Transfer the `PersonalKioskCap` to the transaction sender.
public fun transfer_to_sender(self: PersonalKioskCap, ctx: &mut TxContext) {
    transfer::transfer(self, sender(ctx));
}
```

Let's look how a `PersonalKioskCap` is created.
1. The function needs a mutable reference to the `Kiosk` and a `KioskOwnerCap` to wrap.
2. First `kiosk.owner` field is updated to point to the transaction sender.
3. Then a `OwnerMarker` is added to the `Kiosk` as dynamic field to mark the owner.
    1. `OwnerMarker`, contrary to `kiosk.owner` is immutable after creation and will always point to the correct owner.
    1. This is also used to verify that this is indeed a personal kiosk which we will see later.
4. Lastly, after emitting an event we simply wrap the `KioskOwnerCap` in a `PersonalKioskCap` and return it.

```rust
/// Wrap the KioskOwnerCap making the Kiosk "owned" and non-transferable.
/// The `PersonalKioskCap` is returned to allow chaining within a PTB, but
/// the value must be consumed by the `transfer_to_sender` call in any case.
public fun new(
    kiosk: &mut Kiosk, cap: KioskOwnerCap, ctx: &mut TxContext
): PersonalKioskCap {
    assert!(kiosk::has_access(kiosk, &cap), EWrongKiosk);

    let owner = sender(ctx);

    // set the owner property of the Kiosk
    kiosk::set_owner(kiosk, &cap, ctx);

    // add the owner marker to the Kiosk; uses `_as_owner` to always pass,
    // even if Kiosk "allow_extensions" is set to false
    df::add(
        kiosk::uid_mut_as_owner(kiosk, &cap),
        OwnerMarker {},
        owner
    );

    sui::event::emit(NewPersonalKiosk {
        kiosk_id: object::id(kiosk)
    });

    // wrap the Cap in the `PersonalKioskCap`
    PersonalKioskCap {
        id: object::new(ctx),
        cap: option::some(cap)
    }
}
```

### Personal Kiosk verification

The function `personal_kiosk::is_personal()` checks the existence of the `OwnerMarker` in the `Kiosk` to verify that it is indeed a personal kiosk.

```rust
/// Check if the Kiosk is "personal".
public fun is_personal(kiosk: &Kiosk): bool {
    df::exists_(kiosk::uid(kiosk), OwnerMarker {})
}
```

### KioskOwnerCap accessibility

The owner of the `Kiosk` would of course need access the `KioskOwnerCap` to be able to interact (place, lock, list, add_extension, etc.) with the `Kiosk`.
The below functions enable borrowing, mutably borrowing and borrowing by value via hot-potato the `KioskOwnerCap` from the `PersonalKioskCap` object.

> ℹ️ Borrowing by value is the reason the `KioskOwnerCap` is wrapped in an `Option` inside the `PersonalKioskCap` struct.

```rust
/// Borrow the `KioskOwnerCap` from the `PersonalKioskCap` object.
public fun borrow(self: &PersonalKioskCap): &KioskOwnerCap {
    option::borrow(&self.cap)
}

/// Mutably borrow the `KioskOwnerCap` from the `PersonalKioskCap` object.
public fun borrow_mut(self: &mut PersonalKioskCap): &mut KioskOwnerCap {
    option::borrow_mut(&mut self.cap)
}

/// Borrow the `KioskOwnerCap` from the `PersonalKioskCap` object; `Borrow`
/// hot-potato makes sure that the Cap is returned via `return_val` call.
public fun borrow_val(
    self: &mut PersonalKioskCap
): (KioskOwnerCap, Borrow) {
    let cap = option::extract(&mut self.cap);
    let id = object::id(&cap);

    (cap, Borrow {
        owned_id: object::id(self),
        cap_id: id
    })
}

/// Return the Cap to the PersonalKioskCap object.
public fun return_val(
    self: &mut PersonalKioskCap, cap: KioskOwnerCap, borrow: Borrow
) {
    let Borrow { owned_id, cap_id } = borrow;
    assert!(object::id(self) == owned_id, EIncorrectOwnedObject);
    assert!(object::id(&cap) == cap_id, EIncorrectCapObject);

    option::fill(&mut self.cap, cap)
}
```

## Usage

In order to ensure that our NFT collection is tradable only inside personal `Kiosk`s we can use the `personal_kiosk_rule` module [here](https://github.com/MystenLabs/apps/blob/main/kiosk/sources/rules/personal_kiosk_rule.move).

A regular rule which is added to the `Transferpolicy` that checks that the `Kiosk` is personal, so that the `KioskOwnerCap` is not transferable.

As in our case the use case for personal kiosk is strong royalty enforcement by combining this rule with the `kiosk_lock_rule`.

```rust
/// Description:
/// This module defines a Rule which checks that the Kiosk is "personal" meaning
/// that the owner cannot change. By default, `KioskOwnerCap` can be transferred
/// and owned by an application therefore the owner of the Kiosk is not fixed.
///
/// Configuration:
/// - None
///
/// Use cases:
/// - Strong royalty enforcement - personal Kiosks cannot be transferred with
/// the assets inside which means that the item will never change the owner.
///
/// Notes:
/// - Combination of `kiosk_lock_rule` and `personal_kiosk_rule` can be used to
/// enforce policies on every trade (item can be transferred only through a
/// trade + Kiosk is fixed to the owner).
///
module kiosk::personal_kiosk_rule {
```

The rule witness:

```rust
/// The Rule checking that the Kiosk is an owned one.
struct Rule has drop {}
```

The add function simply adds our `Rule` to the `TransferPolicy`.

```rust
/// Add the "owned" rule to the KioskOwnerCap.
public fun add<T>(policy: &mut TransferPolicy<T>, cap: &TransferPolicyCap<T>) {
    policy::add_rule(Rule {}, policy, cap, true)
}
```

The prove function uses `personal_kiosk::is_personal()` to verify that the item is placed in a personal `Kiosk`.

```rust
/// Make sure that the destination Kiosk has the Owner key. Item is already
/// placed by the time this check is performed - otherwise fails.
public fun prove<T>(kiosk: &Kiosk, request: &mut TransferRequest<T>) {
    assert!(kiosk::has_item(kiosk, policy::item(request)), EItemNotInKiosk);
    assert!(personal_kiosk::is_personal(kiosk), EKioskNotOwned);

    policy::add_receipt(Rule {}, request)
}
```

## Plan of Action

Now that we have a good understanding on how personal `Kiosk` works, let's put it into action:
1. Ensure that the `Kiosk` we airdrop to is personal.
2. Make personal `Kiosk`s for the seller and the buyer.
3. Add the `personal_kiosk` rule to the `TransferPolicy` of our NFTs.
4. Airdrop to seller's personal `Kiosk`.
5. Seller uses `PersonalKioskCap` to list the NFT.
6. Buyer purchases NFT and resolves `TransferRequest`

> ⚠️ In this section we need to depend on the _kiosk_ package to import `personal_kiosk` module.
> We depend in a non-published version of the package for easier development in whichever environment we are working on.
For depending on the published _kiosk_ rules for testnet and mainnet follow [these instructions](https://github.com/MystenLabs/apps/blob/main/kiosk/README.md).

### 1. Ensure that the `Kiosk` we airdrop to is personal

We have included the contract with the airdrop functionality from the previous section.

Although there are multiple solutions to this, we will choose to require a `PersonalKioskCap` to be passed to the `awesome_extension::add()` function,
as it will simplify step 2.

<details>
<summary>Solution</summary>

We first need to import `personal_kiosk:PersonalKioskCap` instead of `KioskOwnerCap`.
```rust
use kiosk::personal_kiosk::PersonalKioskCap;
```

Then we can use `personal_kiosk::borrow()` function to get a reference of `KioskOwnerCap` for adding the extension to the `Kiosk`.
```rust
/// Personal Kiosk owner can add the extension to their kiosk.
public fun add(kiosk: &mut Kiosk, cap: &PersonalKioskCap, ctx: &mut TxContext) {
    kiosk_extension::add(Ext {}, kiosk, cap.borrow(), LOCK, ctx)
}
```

Whole file:

```rust
module awesome_nft::awesome_extension {
    use sui::kiosk::Kiosk;
    use sui::kiosk_extension;
    use sui::transfer_policy::TransferPolicy;

    use kiosk::personal_kiosk::PersonalKioskCap;

    /// Value that represents the `lock` and `place` permission in the
    /// permissions bitmap.
    const LOCK: u128 = 2;

    /// Extension witness.
    public struct Ext has drop {}

    /// Personal Kiosk owner can add the extension to their kiosk.
    public fun add(kiosk: &mut Kiosk, cap: &PersonalKioskCap, ctx: &mut TxContext) {
        kiosk_extension::add(Ext {}, kiosk, cap.borrow(), LOCK, ctx)
    }

    /// Package can lock an item to a `Kiosk` with the extension.
    public(package) fun lock<T: key + store>(
        kiosk: &mut Kiosk, item: T, policy: &TransferPolicy<T>
    ) {
        kiosk_extension::lock(Ext {}, kiosk, item, policy)
    }
}
```

Note that another solution would be to require a `PersonalKioskCap` to be passed to the `add()` function.

Go ahead and use _<span>publish.sh</span> script to publish a new package.

</details>

### 2. Make personal `Kiosk`s for the seller and the buyer

We have included _<span>create-seller-kiosk.sh</span>_ from the previous section. Can you edit the script to create a personal `Kiosk` instead?

Buyer `Kiosk` should be the same script but using 
1. `sui client switch --address buyer` instead of `sui client switch --address seller`.
2. _.buyer.kiosk.env_ instead of _.seller.kiosk.env_.
2. `BUYER_KIOSK_ID` and `BUYER_PERSONAL_CAP_ID` instead of `SELLER_KIOSK_ID` and `SELLER_PERSONAL_CAP_ID`.

Be sure to save the `PersonalKioskCap` `ID` in the .seller.kiosk.env and .buyer.kiosk.env files.

<details>
<summary>Solution</summary>

First we make sure we also load the `RULES_PACKAGE_ID` from the `.rules.env` file.
```bash
# Load variables from .env file
if [ -f .env ] && [ -f .rules.env ]; then
    source .env
    source .rules.env
else
```

Directly after `0x2::kiosk::new` we call the `personal_kiosk::new` function.
```bash
--move-call $RULES_PACKAGE_ID::personal_kiosk::new \
    kiosk \
    cap \
```

Now we use `pcap` instead of `cap` for adding the `awesome_extension::Ext` extension.
```bash
--move-call $PACKAGE_ID::awesome_extension::add \
    kiosk \
    pcap \
--assign pcap \
```

Then we need to handle the ownership of `PersonalKioskCap`.
As we discussed above there only exists the `personal_kiosk::transfer_to_sender()` function for transferring it to the sender.
```bash
--move-call $RULES_PACKAGE_ID::personal_kiosk::transfer_to_sender \
    pcap \
```

Lastly we update the `jq` parsing to store the `PersonalKioskCap` `ID` instead:
```bash
KIOSK_ID=...
PERSONAL_CAP_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("::personal_kiosk::PersonalKioskCap")).objectId')

# Save the Kiosk's and KioskOwnerCap's ids in a file
cat > .seller.kiosk.env <<-KIOSK_ENV
SELLER_KIOSK_ID=$KIOSK_ID
SELLER_PERSONAL_CAP_ID=$PERSONAL_CAP_ID

KIOSK_ENV
```

Whole file:
```bash
#!/bin/bash

# Load variables from .env file
if [ -f .env ] && [ -f .rules.env ]; then
    source .env
    source .rules.env
else
    echo "No .env, or .rules.env file found"
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
    --move-call $RULES_PACKAGE_ID::personal_kiosk::new \
        kiosk \
        cap \
    --assign pcap \
    --move-call $PACKAGE_ID::awesome_extension::add \
        kiosk \
        pcap \
    --move-call $RULES_PACKAGE_ID::personal_kiosk::transfer_to_sender \
        pcap \
    --move-call 0x2::transfer::public_share_object \
        $kiosk_type \
        kiosk \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
KIOSK_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | endswith("2::kiosk::Kiosk")).objectId')
PERSONAL_CAP_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("::personal_kiosk::PersonalKioskCap")).objectId')

# Save the Kiosk's and KioskOwnerCap's ids in a file
cat > .seller.kiosk.env <<-KIOSK_ENV
SELLER_KIOSK_ID=$KIOSK_ID
SELLER_PERSONAL_CAP_ID=$PERSONAL_CAP_ID

KIOSK_ENV
```
</details>

### 3. Add the `personal_kiosk` rule to the `TransferPolicy` of our NFTs

We have included _<span>policy-with-enforced-royalties.sh</span>_ script from the previous section.
Can you edit the script to add the `personal_kiosk_rule` to the `TransferPolicy`?

<details>
<summary>Solution</summary>

Simply add the following lines

```bash
--move-call ${RULES_PACKAGE_ID}::personal_kiosk_rule::add \
    $nft_type \
    policy \
    cap \
```

Whole file:
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

# Switch to admin address
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
    --move-call ${RULES_PACKAGE_ID}::personal_kiosk_rule::add \
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

### 4. Airdrop to seller's personal `Kiosk`

Now that we have our enforced policy setup we can airdrop to the seller's personal `Kiosk`.

We have included _<span>mint.sh</span>_ script from the previous section. Go ahead and use it to mint an `AwesomeNFT` and airdrop it to the seller's personal `Kiosk`.

### 5. Seller uses `PersonalKioskCap` to list the NFT

As the seller, we need to write a ptb that will list the NFT in the seller's personal `Kiosk`.
We have included _<span>list.sh</span>_ which simply lists the NFT in the seller's `Kiosk`,
but has the variable `kiosk_owner_cap` which is not yet defined. Can you edit the script to use our `PersonalKioskCap` in order to list the item?

> ⚠️ As of 2024 July, references (`&T`) cannot be used as a transaction block result. This means that we need to borrow the `KioskOwnerCap` by value.

<details>
<summary>Solution</summary>

```bash
#!/bin/bash

# Load variables from *.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .seller.kiosk.env ] && [ -f .transfer_policy.env ] && [ -f .rules.env ]; then
    source .env
    source .nft.env
    source .seller.kiosk.env
    source .transfer_policy.env
    source .rules.env
else
    echo "No .env, .nft.env, .seller.kiosk.env, .transfer_policy.env, or .rules.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
LISTING_PRICE=5_000_000_000  # 5 SUI

# Switch to seller address
sui client switch --address seller

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
sui client ptb \
    --move-call \
    $RULES_PACKAGE_ID::personal_kiosk::borrow_val \
        @$SELLER_PERSONAL_CAP_ID \
    --assign borrow_val_res \
    --assign kiosk_owner_cap borrow_val_res.0 \
    --assign potato borrow_val_res.1 \
    --move-call \
    0x2::kiosk::list \
        $nft_type \
        @$SELLER_KIOSK_ID \
        kiosk_owner_cap \
        @$NFT_ID \
        $LISTING_PRICE \
    --move-call \
    $RULES_PACKAGE_ID::personal_kiosk::return_val \
        @$SELLER_PERSONAL_CAP_ID \
        kiosk_owner_cap \
        potato \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

### 6. Buyer purchases NFT and resolves `TransferRequest`

We have included _<span>purchase.sh</span>_ script from the solution of section 3. Can you edit it to use the buyer's personal `Kiosk` instead?

<details>
<summary>Solution</summary>

In order to resolve the lock rule, we need to lock the item into our `Kiosk`. To lock the item we need to borrow the `KioskOwnerCap` by value.

After `0x2::kiosk::purchase()` we
1. borrow `KioskOwnerCap` by value using `personal_kiosk::borrow_val()`.
2. lock the item into the buyer's personal `Kiosk`.
3. return the `KioskOwnerCap` using `personal_kiosk::return_val()`.
```bash
--move-call $RULES_PACKAGE_ID::personal_kiosk::borrow_val \
    @$BUYER_PERSONAL_CAP_ID \
--assign borrow_val \
--assign kiosk_owner_cap borrow_val.0 \
--assign potato borrow_val.1 \
--move-call 0x2::kiosk::lock \
    $nft_type \
    @$BUYER_KIOSK_ID \
    kiosk_owner_cap \
    @$TRANSFER_POLICY_ID \
    nft \
--move-call $RULES_PACKAGE_ID::personal_kiosk::return_val \
    @$BUYER_PERSONAL_CAP_ID \
    kiosk_owner_cap \
    potato \
```

We also need to prove the `personal_kiosk::personal_kiosk_rule`.
```bash
--move-call $RULES_PACKAGE_ID::personal_kiosk_rule::prove \
    $nft_type \
    @$BUYER_KIOSK_ID \
    request \
```

Whole file:
```bash
#!/bin/bash

# Load variables from *.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .seller.kiosk.env ] && [ -f .transfer_policy.env ] && [ -f .rules.env ] && [ -f .buyer.kiosk.env ]; then
    source .env
    source .nft.env
    source .seller.kiosk.env
    source .transfer_policy.env
    source .rules.env
    source .buyer.kiosk.env
else
    echo "No .env, .nft.env, .seller.kiosk.env, .transfer_policy.env, .rules.env, or .buyer.kiosk.env file found"
    exit 1
fi

GAS_BUDGET=5_600_000_000  # 5.6 SUI

# Switch to admin address
sui client switch --address buyer

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Split the gas coin into 2 new coins, 5 SUI for purchase and 0.5 SUI for royalties.
# Then normally use kiosk::purchase with the 5 SUI coin.
# Then lock it inside buyer's personal kiosk.
# Then use royalty_rule::pay with the 0.5 SUI coin.
# Then prove personal and lock rules.
# before confirming the request with transfer_policy::confirm_request.
sui client ptb \
    --split-coins gas [5_000_000_000, 500_000_000] \
    --assign payment \
    --move-call 0x2::kiosk::purchase \
        $nft_type \
        @$SELLER_KIOSK_ID \
        @$NFT_ID \
        payment.0 \
    --assign purchase \
    --assign nft purchase.0 \
    --assign request purchase.1 \
    --move-call $RULES_PACKAGE_ID::personal_kiosk::borrow_val \
        @$BUYER_PERSONAL_CAP_ID \
    --assign borrow_val \
    --assign kiosk_owner_cap borrow_val.0 \
    --assign potato borrow_val.1 \
    --move-call 0x2::kiosk::lock \
        $nft_type \
        @$BUYER_KIOSK_ID \
        kiosk_owner_cap \
        @$TRANSFER_POLICY_ID \
        nft \
    --move-call $RULES_PACKAGE_ID::personal_kiosk::return_val \
        @$BUYER_PERSONAL_CAP_ID \
        kiosk_owner_cap \
        potato \
    --move-call ${RULES_PACKAGE_ID}::royalty_rule::pay \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        request \
        payment.1 \
    --move-call $RULES_PACKAGE_ID::personal_kiosk_rule::prove \
        $nft_type \
        @$BUYER_KIOSK_ID \
        request \
    --move-call $RULES_PACKAGE_ID::kiosk_lock_rule::prove \
        $nft_type \
        request \
        @$BUYER_KIOSK_ID \
    --move-call 0x2::transfer_policy::confirm_request \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        request \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>


## Well done!

You have successfully setup the trading environment for trading `AwesomeNFT`s with fully enforced royalties!
You have also came across very useful Sui and Move patterns that can help you develop composable and secure packages!

You can find the solutions of this section in one place in _7-finished_ directory.

