# Kiosk Course

Welcome to the Kiosk course! This course will teach you how kiosk works as part of the Sui-framework.

## Prerequisites

Before starting this course, you should have a basic understanding of the Sui's object-oriented model and the Move programming language. If you are not familiar with these topics, we recommend you to read the following resources:
- [Sui's object-oriented model](https://docs.sui.io/concepts/object-model) with its sub-sections
- [Transactions](https://docs.sui.io/concepts/transactions) and [Programmable Transaction Blocks](https://docs.sui.io/concepts/transactions/prog-txn-blocks)
- [Move book](https://move-book.com/index.html) and [Move by Example](https://examples.sui.io/)

## What is Kiosk?

Kiosk is a library under the sui-framework that provides a common interface for trading NFTs on the Sui blockchain.

It consists of three components with the first two playing a crucial role in the trading of NFTs:
- [kiosk](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/kiosk.move): Defines the `Kiosk` shared object owned by a Sui address, the owner. Under it, objects owned by the owner are placed and can be listed for trading. The ownership of the `Kiosk` is affirmed by the `KioskOwnerCap`.
- [transfer_policy](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/transfer_policy.move): Provides a common interface for NFT-collectors to apply rules on the transfer of NFTs. This is facilitated by the `TransferPolicy<T>` shared object where `T` is the type of the NFT. Rules need to be proven by resolving the `TransferRequest<T>` [Hot Potato](https://examples.sui.io/patterns/hot-potato.html), which is created on NFT purchase. Using the [Witness](https://move-book.com/programmability/witness-pattern.html) pattern, the creator of the NFT collection can add rules to this `TransferPolicy<T>`, that the `TransferRequest<T>` needs to confirm in order to be resolved.
- Lastly there is also the [kiosk_extension](https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/kiosk/kiosk_extension.move) module which enables creators to create extensions for `Kiosk`s, that its owner will need to install. This is useful for adding new features to the `Kiosk` such as KYC, airdrops, etc.

Please take a moment to read the thorough documentation inside the above modules. If not everything is clear, worry not! This course will guide you through the process of using kiosk for trading NFTs on the Sui blockchain step by step.

## Course Structure

During our course there will be three main actors:
- The **admin** who creates an NFT collection and adds rules on trading.
- The **seller** who lists NFTs for sale.
- The **buyer** who purchases NFTs from the Seller's `Kiosk`.

This course is divided into six (plus intro) sections, each with a specific target/goal, covering multiple aspects of the kiosk functionality.
Each section has a corresponding folder with a README file that explains the goal of the section and the steps to achieve it.

### 0. Introduction

Getting acquainted with the basic contract for minting NFTs, _<span>publish.sh</span>_ and cli-ptbs.

### 1. Common use of kiosk for trading.

1. Admin creates an empty `TransferPolicy`.
2. Admin airdrops NFT to seller.
3. Seller creates a `Kiosk`.
4. Seller lists airdropped NFT for sale.
5. Buyer purchases NFT from the seller.
6. Seller withdraws the profits from the `Kiosk`.

### 2. Royalties on NFT trading.

1. Admin edits the `TransferPolicy` to add royalties.
2. Admin airdrops NFT to seller.
3. Seller lists NFT for sale.
4. Buyer purchases NFT from the seller.
5. Buyer needs to resolve the royalty rule by paying royalties.
6. Admin withdraws the royalties from the `TransferPolicy`.

### 3. Enforced royalties.

1. Admin edits the `TransferPolicy` to enforce royalties - lock rule.
2. Admin airdrops NFT to seller.
3. Seller lists NFT for sale.
4. Buyer purchases NFT from the seller.
5. Buyer needs to resolve the royalty and lock rules.

### 4. Exclusive listing with `PurchaseCap`.

1. Admin creates their own `Kiosk`
2. Admin lists with `PurchaseCap` an NFT for sale to buyer with 0 price.
3. Buyer uses `PurchaseCap` to purchase the NFT at 0 price.

### 5. Airdrop inside `Kiosk`.

1. Update contract to include an airdrop extension that can lock newly minted NFTs.
2. Seller adds the extension to their `Kiosk`.
3. Admin airdrops an NFT to seller's `Kiosk`.
4. Seller and buyer trade the NFT.

### 6. Disable trading of `Kiosk`s

1. Admin adds personal kiosk rule to the `TransferPolicy`.
2. Seller adds airdrop extension to their `Kiosk`.
3. Seller and buyer create their own `Kiosk`s and make them personal.
4. Admin airdrops an NFT to seller's `Kiosk`.
5. Seller and buyer trade the NFT and resolve all rules.

