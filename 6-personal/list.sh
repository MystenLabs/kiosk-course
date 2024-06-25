#!/bin/bash

# Load variables from *.env files
if [ -f .env ] && [ -f .nft.env ] && [ -f .seller.kiosk.env ] && [ -f .rules.env ]; then
    source .env
    source .nft.env
    source .seller.kiosk.env
    source .rules.env
else
    echo "No .env, .nft.env, .seller.kiosk.env, or .rules.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
LISTING_PRICE=5_000_000_000  # 5 SUI

# Switch to seller address
sui client switch --address seller


## THE BELOW DOES NOT WORK YET AS `kiosk_owner_cap` is not defined.
nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
sui client ptb \
    --move-call 0x2::kiosk::list \
        $nft_type \
        @$SELLER_KIOSK_ID \
        kiosk_owner_cap \
        @$NFT_ID \
        $LISTING_PRICE \
    --gas-budget $GAS_BUDGET \
    --summary

