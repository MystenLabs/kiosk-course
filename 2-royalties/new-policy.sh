#!/bin/bash
if [ -f .env ]; then
    source .env
else
    echo "No .env file found"
    exit 1
fi
if [ -f .transfer_policy.env ]; then
    echo "Transfer policy already created."
    echo "It is advised to not have more than one transfer policy"
    echo "as the purchaser can freely choose which one to use."
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# Switch to admin address
sui client switch --address admin

nft_type="<${PACKAGE_ID}::awesome_nft::AwesomeNFT>"
# Create a TransferPolicy and keep its TransferPolicyCap
mint_res=$(sui client ptb --move-call \
    0x2::transfer_policy::default \
        $nft_type \
        @$PUBLISHER \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse Kiosk's and KioskOwnerCap's ids from the response
TRANSFER_POLICY_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicy<")).objectId')
TRANSFER_POLICY_CAP_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("2::transfer_policy::TransferPolicyCap<")).objectId')

# Save the TransferPolicy's and TransferPolicyCap's ids in a file
cat > .transfer_policy.env <<-TRANSFER_POLICY_ENV
TRANSFER_POLICY_ID=$TRANSFER_POLICY_ID
TRANSFER_POLICY_CAP_ID=$TRANSFER_POLICY_CAP_ID

TRANSFER_POLICY_ENV
