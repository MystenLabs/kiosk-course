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
