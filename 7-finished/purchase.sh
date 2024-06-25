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

