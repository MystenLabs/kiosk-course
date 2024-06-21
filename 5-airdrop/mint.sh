# Load variables from .env file
if [ -f .env ]; then
    source .env
else
    echo "No .env file found"
    exit 1
fi

GAS_BUDGET=100_000_000  # 0.1 SUI

# admin has the MintCap
sui client switch --address admin

# mint the NFT
mint_res=$(sui client ptb --move-call \
    $PACKAGE_ID::awesome_nft::new \
        @$MINT_CAP \
        "'some_name'" \
        "'some_description'" \
        "'some_link'" \
        "'some_image_url'" \
        "'some_thumbnail_url'" \
        "'some_project_url'" \
        "'me'" \
    --assign nft \
    --transfer-objects [nft] @$ADMIN_ADDRESS \
    --gas-budget $GAS_BUDGET \
    --json)

# Parse AwesomeNFT's id from the mint response
NFT_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("::awesome_nft::AwesomeNFT")).objectId')
echo NFT_ID=$NFT_ID > .nft.env

