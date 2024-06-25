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

