#!/bin/bash

# Load variables from .env file
if [ -f .env ] && [ -f .rules.env ]; then
    source .env
    source .rules.env
else
    echo "No .env, or .rules.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to seller address
sui client switch --address seller

kiosk_type="<sui::kiosk::Kiosk>"
# Create a Kiosk with extension and keep its cap.
kiosk_res=$(sui client ptb --move-call \
    0x2::kiosk::new \
    --assign kiosk_res \
    --assign kiosk kiosk_res.0 \
    --assign cap kiosk_res.1 \
    --move-call $RULES_PACKAGE_ID::personal_kiosk::new \
        kiosk \
        cap \
    --assign pcap \
    --move-call $PACKAGE_ID::awesome_extension::add \
        kiosk \
        pcap \
    --move-call $RULES_PACKAGE_ID::personal_kiosk::transfer_to_sender \
        pcap \
    --move-call 0x2::transfer::public_share_object \
        $kiosk_type \
        kiosk \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
KIOSK_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | endswith("2::kiosk::Kiosk")).objectId')
PERSONAL_CAP_ID=$(echo "$kiosk_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("::personal_kiosk::PersonalKioskCap")).objectId')

# Save the Kiosk's and KioskOwnerCap's ids in a file
cat > .seller.kiosk.env <<-KIOSK_ENV
SELLER_KIOSK_ID=$KIOSK_ID
SELLER_PERSONAL_CAP_ID=$PERSONAL_CAP_ID

KIOSK_ENV
