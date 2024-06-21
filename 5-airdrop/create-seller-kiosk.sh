#!/bin/bash

# Load variables from .env file
if [ -f .env ]; then
    source .env
else
    echo "No .env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to seller address
sui client switch --address seller

# Create a Kiosk and keep it
kiosk_res=$(sui client ptb --move-call \
    0x2::kiosk::default \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
KIOSK_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | endswith("2::kiosk::Kiosk")).objectId')
KIOSK_CAP_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::kiosk::KioskOwnerCap")).objectId')

# Save the Kiosk's and KioskOwnerCap's ids in a file
cat > .seller.kiosk.env <<-KIOSK_ENV
SELLER_KIOSK_ID=$KIOSK_ID
SELLER_KIOSK_CAP_ID=$KIOSK_CAP_ID

KIOSK_ENV
