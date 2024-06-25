#!/bin/bash

# Load variables from *.env file
if [ -f .env ] && [ -f .rules.env ]; then
    source .env
    source .rules.env
else
    echo "No .env, or .rules.env file found"
    exit 1
fi
if [ -f .transfer_policy.env ]; then
    echo "Transfer policy already created."
    echo "It is advised to not have more than one transfer policy"
    echo "as the purchaser can freely choose which one to use."
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
ROYALTY_BPS=1000_u16  # 10%

# Switch to admin address
sui client switch --address admin

policy_type="<sui::transfer_policy::TransferPolicy<${PACKAGE_ID}::awesome_nft::AwesomeNFT>>"
nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Create a Kiosk, make it personal, and add extension.
policy_res=$(sui client ptb \
    --move-call 0x2::transfer_policy::new \
        $nft_type \
        @$PUBLISHER \
    --assign policy_and_cap \
    --assign policy policy_and_cap.0 \
    --assign cap policy_and_cap.1 \
    --move-call $RULES_PACKAGE_ID::royalty_rule::add \
        $nft_type \
        policy \
        cap \
        $ROYALTY_BPS \
        0 \
    --move-call ${RULES_PACKAGE_ID}::kiosk_lock_rule::add \
        $nft_type \
        policy \
        cap \
    --transfer-objects [cap] @$ADMIN_ADDRESS \
    --move-call \
        0x2::transfer::public_share_object \
        $policy_type \
        policy \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
TRANSFER_POLICY_ID=$(echo "$policy_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicy<")).objectId')
TRANSFER_POLICY_CAP_ID=$(echo "$policy_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicyCap<")).objectId')

# Save the TransferPolicy's and TransferPolicyCap's ids in a file
cat > .transfer_policy.env <<-TRANSFER_POLICY_ENV
TRANSFER_POLICY_ID=$TRANSFER_POLICY_ID
TRANSFER_POLICY_CAP_ID=$TRANSFER_POLICY_CAP_ID

TRANSFER_POLICY_ENV
