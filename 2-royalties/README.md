# Creator royalties

Well begun is half done. We have minted and traded an `AwesomeNFT`.
As you can see we have included all the scripts from the previous sections in this directory.
More specifically,
- _<span>mint.sh</span>_: Admin airdrops an NFT to seller, and stores the `NFT_ID` in the `.nft.env` file.
- _<span>new-policy.sh</span>_: Admin creates a new policy, and stores the `TRANSFER_POLICY_ID` and `TRANSFER_POLICY_CAP_ID` in the _.transfer_policy.env_ file.
- _<span>create-seller-kiosk.sh</span>_: Seller creates a new kiosk for the seller and stores the kiosk-id and owner-cap-id in the _.seller.kiosk.env_ file.
- _<span>place-and-list.sh</span>_: Seller places and lists the NFT for sale.
- _<span>purchase.sh</span>_: Buyer purchases the NFT from the seller.
- _<span>kiosk-withdraw</span>_: Seller withdraws the funds from their kiosk.

In this section, we will be adding creator royalties to the trading of `AwesomeNFT`s.

## TransferPolicy

If you have been paying attention, you might remember the below:

> ```
> // - TransferPolicy - is a highly customizable primitive, which provides an
> // interface for the type owner to set custom transfer rules for every
> // deal performed in the `Kiosk` or a similar system that integrates with TP.
> ``
> The type-owner, ie. the creator of the asset, can set custom transfer rules for every deal, ie. trade happening in the Kiosk.

Let's revisit the `TransferPolicy` and its function:

### Rules

```
/// - Type owner (creator) can set any Rules as long as the ecosystem supports
/// them. All of the Rules need to be resolved within a single transaction (eg
/// pay royalty and pay fixed commission). Once required actions are performed,
/// the `TransferRequest` can be "confirmed" via `confirm_request` call.
```

The creator can add rules to the `TransferPolicy` that the `TransferRequest` needs to confirm in the same transaction-block.
`confirm_request` is the function that checks the two in order to resolve the `TransferRequest`.

So it seems that `TransferPolicy` and `TransferRequest` are closely related. Let's take a look at them:

#### TransferPolicy

```rust
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

#### TransferRequest

```rust
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

#### Rules & Receipts

```rust
/// Set of types of attached rules - used to verify `receipts` when
/// a `TransferRequest` is received in `confirm_request` function.
///
/// Additionally provides a way to look up currently attached Rules.
rules: VecSet<TypeName>
```

```rust
/// Collected Receipts. Used to verify that all of the rules
/// were followed and `TransferRequest` can be confirmed.
receipts: VecSet<TypeName>
```

So it seems that the creator adds rules to the `TransferPolicy` and that the buyer collects receipts into `TransferRequest` to verify that all rules were followed.

Let's take a look at how a rule is added to the `TransferPolicy`:


```rust
/// Add a custom Rule to the `TransferPolicy`. Once set, `TransferRequest` must
/// receive a confirmation of the rule executed so the hot potato can be unpacked.
///
/// - T: the type to which TransferPolicy<T> is applied.
/// - Rule: the witness type for the Custom rule
/// - Config: a custom configuration for the rule
///
/// Config requires `drop` to allow creators to remove any policy at any moment,
/// even if graceful unpacking has not been implemented in a "rule module".
public fun add_rule<T, Rule: drop, Config: store + drop>(
    _: Rule, policy: &mut TransferPolicy<T>, cap: &TransferPolicyCap<T>, cfg: Config
) {
    assert!(object::id(policy) == cap.policy_id, ENotOwner);
    assert!(!has_rule<T, Rule>(policy), ERuleAlreadySet);
    df::add(&mut policy.id, RuleKey<Rule> {}, cfg);
    policy.rules.insert(type_name::get<Rule>())
}
```

So the `Rule` is actually a Witness type and the `Config` is a custom configuration living under `TransferPolicy` used to verify the rule execution.
This means that the module where the `Rule` is defined can only add rules to a `TransferPolicy` along with the `Config`, that is required to verify the rule execution.

Let's take a look at the `confirm_request` function:

```rust
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

Here we see that the `TransferPolicy` rules are iterated and a respective `receipt` inside the `TransferRequest` is checked to verify that all rules were followed.

Let's also see how a receipt is added to the `TransferRequest`:

```rust
/// Adds a `Receipt` to the `TransferRequest`, unblocking the request and
/// confirming that the policy requirements are satisfied.
public fun add_receipt<T, Rule: drop>(
    _: Rule, request: &mut TransferRequest<T>
) {
    request.receipts.insert(type_name::get<Rule>())
}
```

Pretty simple, the module that defines the `Rule` can also add a receipt to the `TransferRequest`.

## Creator Royalties

So, if we needed to add creator royalties, we would need to create a module with two main functions:
- `add_rule` to add the rule to the `TransferPolicy`
- `prove_rule` to add the receipt to the `TransferRequest`

The rule would need to have a `Config` for calculating the correct royalties that need to be paid to the creator;
while the `prove_rule` would use this `Config` to calculate and check the royalties thus adding the receipt to the `TransferRequest`.

Luckily for us, there are some frequently used rules that are already implemented in the [Kiosk package](https://github.com/MystenLabs/apps/tree/main/kiosk).

> ⚠️ Do not confuse with _sui::kiosk_, the _Kiosk_ package is a separate package that is commonly used side by side with _sui::kiosk_ and defines common rules that can be used in a `TransferPolicy`.

If you check the _move_ directory in this section you will actually find the _Kiosk_ package with the _royalty_rule.move_ file/module.
This package is cloned from the official [repo](https://github.com/MystenLabs/apps/tree/main/kiosk), but its _Move.toml_ file is edited to behave as unpublished.
This way we can use it in localnet/devnet setup, as we also updated _<span>./publish.sh</span>_ (`--with-unpublished-dependencies`) and _awesome_nft/Move.toml_ to also publish the _Kiosk_ package.
Note though, that you should only use this setup in a development/testing environment, and you should point to the correct _Kiosk_ package in a production environment.

Let's take a look at the _royalty_rule.move_ module:

```rust
/// Description:
/// This module defines a Rule which requires a payment on a purchase.
/// The payment amount can be either a fixed amount (min_amount) or a
/// percentage of the purchase price (amount_bp). Or both: the higher
/// of the two is used.
///
/// Configuration:
/// - amount_bp - the percentage of the purchase price to be paid as a
/// fee, denominated in basis points (100_00 = 100%, 1 = 0.01%).
/// - min_amount - the minimum amount to be paid as a fee if the relative
/// amount is lower than this setting.
///
/// Use cases:
/// - Percentage-based Royalty fee for the creator of the NFT.
/// - Fixed commission fee on a trade.
/// - A mix of both: the higher of the two is used.
///
/// Notes:
/// - To use it as a fixed commission set the `amount_bp` to 0 and use the
/// `min_amount` to set the fixed amount.
/// - To use it as a percentage-based fee set the `min_amount` to 0 and use
/// the `amount_bp` to set the percentage.
/// - To use it as a mix of both set the `min_amount` to the min amount
/// acceptable and the `amount_bp` to the percentage of the purchase price.
/// The higher of the two will be used.
```

This is exactly what we need! The rule adds creator royalties as a percentage of the purchase price or a fixed amount, selecting the higher of the two.

The `Rule witness:
```rust
/// The "Rule" witness to authorize the policy.
struct Rule has drop {}
```
Pretty simple. Just a struct with a `drop` ability that we only create in this module.

The rule configuration (`Config`):
```rust
/// Configuration for the Rule. The `amount_bp` is the percentage
/// of the transfer amount to be paid as a royalty fee. The `min_amount`
/// is the minimum amount to be paid if the percentage based fee is
/// lower than the `min_amount` setting.
///
/// Adding a mininum amount is useful to enforce a fixed fee even if
/// the transfer amount is very small or 0.
struct Config has store, drop {
    amount_bp: u16,
    min_amount: u64
}
```

The `Config` needs the `amount_bp` and `min_amount` to calculate the correct royalties.

Now the `add` function for adding the `Rule` to our `TransferPolicy`:
```rust
/// Creator action: Add the Royalty Rule for the `T`.
/// Pass in the `TransferPolicy`, `TransferPolicyCap` and the configuration
/// for the policy: `amount_bp` and `min_amount`.
public fun add<T: key + store>(
    policy: &mut TransferPolicy<T>,
    cap: &TransferPolicyCap<T>,
    amount_bp: u16,
    min_amount: u64
) {
    assert!(amount_bp <= MAX_BPS, EIncorrectArgument);
    policy::add_rule(Rule {}, policy, cap, Config { amount_bp, min_amount })
}
```

Just a call to the `policy::add_rule` with the `Rule` and `Config`, after some basic assertion.

And the function `pay` which has a two-fold purpose:
1. Pay the royalty fee to the `TransferPolicy` and thus the creator.
2. Add the receipt to the `TransferRequest` to confirm the rule execution.
```rust
/// Buyer action: Pay the royalty fee for the transfer.
public fun pay<T: key + store>(
    policy: &mut TransferPolicy<T>,
    request: &mut TransferRequest<T>,
    payment: Coin<SUI>
) {
    let paid = policy::paid(request);
    let amount = fee_amount(policy, paid);

    assert!(coin::value(&payment) == amount, EInsufficientAmount);

    policy::add_to_balance(Rule {}, policy, payment);
    policy::add_receipt(Rule {}, request)
}
```

There is also the helper function `fee_amount` that calculates the correct royalties to be paid.
As stated this function can be dry-runned to check the exact amount that needs to be paid to the creator.

So, let's add the creator royalties to our `AwesomeNFT` trading!

## Plan of Action

#### 0. Publish

By running the _<span>publish.sh</span>_ script, you can publish the contract to your current sui environment and store the necessary information in a new `.env` file.
Notice that in this case, this will also publish the _Kiosk_ package and store its id (same with the _awesome_nft_) in the _.rules.env_ file.

#### 1. `TransferPolicy` with 10% royalties

<details>
<summary>Solution 1</summary>
Edit an existing `TransferPolicy` and add the `royalty_rule` to it.

After running the _<span>new-policy.sh</span>_, we will add the `royalty_rule` to the existing `TransferPolicy`.

```bash
#!/bin/bash

# Load variables from .env, .transfer_policy.env, and rules.env files
if [ -f .env ] && [ -f .transfer_policy.env ] && [ -f .rules.env ]; then
    source .env
    source .transfer_policy.env
    source .rules.env
else
    echo "No .env, .transfer_policy.env, or .rules.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
ROYALTY_BPS=1000  # 10%
MIN_AMOUNT=10_000_000  # 0.01 SUI

# Switch to admin address
sui client switch --address admin

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Add royalty rule to the TransferPolicy
sui client ptb \
    --assign bps 1000_u16 \
    --move-call \
    ${RULES_PACKAGE_ID}::royalty_rule::add \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        @$TRANSFER_POLICY_CAP_ID \
        bps \
        $MIN_AMOUNT \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

<details>
<summary>Solution 2</summary>
Instead of creating a "default" `TransferPolicy` in the _<span>new-policy.sh</span>_, we will create a new policy with the `royalty_rule` added.

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

> ⚠️ What would happen if we keep the old `TransferPolicy` and also create one with the `royalty_rule`? The buyer would be free to choose which one to use, and skip the royalties. This is why we have a preliminary check in the script to see if a _.transfer_policy.env_ already exists.
</details>

#### 2. Mint and list an `AwesomeNFT`.

This step is already implemented during the previous sections.

1. Run _<span>mint.sh</span>_ to mint an `AwesomeNFT` to the seller.
2. Run _<span>create-seller-kiosk.sh</span>_ to create a kiosk for the seller.
3. Run _<span>place-and-list.sh</span>_ to place and list the `AwesomeNFT` for sale.

#### 3. Purchase the `AwesomeNFT`.

Now we need to update the _<span>purchase.sh</span>_ script to include the payment of the royalties to the creator.

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
    echo "No .env, .nft.env, .seller.kiosk.env, .transfer_policy.env or .rules.env file found"
    exit 1
fi

GAS_BUDGET=5_600_000_000  # 5.6 SUI

# Switch to admin address
sui client switch --address buyer

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Split the gas coin into 2 new coins, 5 SUI for purchase and 0.5 SUI for royalties.
# Then normally use kiosk::purchase with the 5 SUI coin.
# Then use royalty_rule::pay with the 0.5 SUI coin,
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
    --transfer-objects [nft] @$BUYER_ADDRESS \
    --move-call \
    ${RULES_PACKAGE_ID}::royalty_rule::pay \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        request \
        payment.1 \
    --move-call \
    0x2::transfer_policy::confirm_request \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        request \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

#### 4. Withdraw the creator profits from royalties

<details>
<summary>Solution</summary>

```bash
#!/bin/bash

# Load variables from .env, .nft.env and .seller.kiosk.env files
if [ -f .env ] && [ -f .transfer_policy.env ]; then
    source .env
    source .transfer_policy.env
else
    echo "No .env, or .transfer_policy.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to seller address
sui client switch --address admin

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Withdraw royalties from the transfer policy
sui client ptb \
    --move-call \
    0x2::transfer_policy::withdraw \
        $nft_type \
        @$TRANSFER_POLICY_ID \
        @$TRANSFER_POLICY_CAP_ID \
        none \
    --assign royalties \
    --transfer-objects \
        [royalties] \
        @$ADMIN_ADDRESS \
    --gas-budget $GAS_BUDGET \
    --summary
```
</details>

## Well done!

We have successfully added creator royalties to the trading of `AwesomeNFT`s. The creator will now receive 10% of the purchase price as royalties.

However, note that the seller receives the AwesomeNFT directly in their wallet and is able to trade it without the royalties being paid to the creator. To do this they simply need to create another contract which will put the `AwesomeNFT` in a shared-object which can be unwrapped as long as a specific amount is paid to them.
In the next sections, we will see how a creator can enforce royalties and lock the NFTs into traders' Kiosks.

