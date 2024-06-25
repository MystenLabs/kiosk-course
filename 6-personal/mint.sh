#!/bin/bash

# Load variables from .env file
if [ -f .env ] && [ -f .seller.kiosk.env ] && [ -f .transfer_policy.env ]; then
    source .env
    source .seller.kiosk.env
    source .transfer_policy.env
else
    echo "No .env, seller.kiosk.env, or .transfer_policy.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# admin has the MintCap
sui client switch --address admin

# mint the NFT
mint_res=$(sui client ptb --move-call \
    $PACKAGE_ID::awesome_nft::mint_to_kiosk \
        @$MINT_CAP \
        "'name'" \
        "'description'" \
        "'link'" \
        "'image_url'" \
        "'thumbnail_url'" \
        "'project_url'" \
        "'creator'" \
        @$SELLER_KIOSK_ID \
        @$TRANSFER_POLICY_ID \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse AwesomeNFT's id from the mint response
NFT_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("::awesome_nft::AwesomeNFT")).objectId')

cat > .nft.env <<-NFT_ENV
NFT_ID=$NFT_ID

NFT_ENV
