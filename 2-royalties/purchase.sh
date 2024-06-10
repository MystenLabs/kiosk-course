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
