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

# Switch to buyer address
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
        @$ADMIN_KIOSK_ID \
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

