#!/bin/bash

# Load variables from .env, .nft.env and .seller.kiosk.env files
if [ -f .env ] && [ -f .seller.kiosk.env ]; then
    source .env
    source .seller.kiosk.env
else
    echo "No .env, .seller.kiosk.env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI
WITHDRAW_AMOUNT=5_000_000_000  # 5 SUI

# Switch to seller address
sui client switch --address seller

# Withdraw profits from the kiosk
sui client ptb \
    --move-call \
    0x2::kiosk::withdraw \
        @$SELLER_KIOSK_ID \
        @$SELLER_KIOSK_CAP_ID \
        some\($WITHDRAW_AMOUNT\) \
    --assign profits \
    --transfer-objects \
        [profits] \
        @$SELLER_ADDRESS \
    --gas-budget $GAS_BUDGET \
    --summary
