#!/bin/bash

# check dependencies are available.
for i in jq curl sui; do
  if ! command -V ${i} 2>/dev/null; then
    echo "${i} is not installed"
    exit 1
  fi
done
cwd=$(pwd)
script_dir=$(dirname "$0")

MOVE_PACKAGE_PATH=${cwd}/${script_dir}/move/awesome_nft
GAS_BUDGET=900000000 # 0.9 SUI (Usually it is less than 0.5 SUI)

network_alias=$(sui client active-env)
envs_json=$(sui client envs --json)
NETWORK=$(echo $envs_json | jq -r --arg alias $network_alias '.[0][] | select(.alias == $alias).rpc')
addresses=$(sui client addresses --json)

echo "Checking if admin, buyer, and seller addresses are available"
has_admin=$(echo "$addresses" | jq -r '.addresses | map(contains(["admin"])) | any')
if [ "$has_admin" = "false" ]; then
    echo "Did not find 'admin' in the addresses. Creating one."
    sui client new-address ed25519 admin
fi
has_seller=$(echo "$addresses" | jq -r '.addresses | map(contains(["seller"])) | any')
if [ "$has_seller" = "false" ]; then
    echo "Did not find 'seller' in the addresses. Creating one."
    sui client new-address ed25519 seller
fi
has_buyer=$(echo "$addresses" | jq -r '.addresses | map(contains(["buyer"])) | any')
if [ "$has_buyer" = "false" ]; then
    echo "Did not find 'buyer' in the addresses. Creating one."
    sui client new-address ed25519 buyer
fi

echo "Switching to admin address"
sui client switch --address admin

echo "Checking if enough gas is available"
gas=$(sui client gas --json)
AVAILABLE=$(echo "$gas" | jq --argjson min_gas $GAS_BUDGET '.[] | select(.mistBalance > $min_gas).gasCoinId')
if [ -z "$AVAILABLE" ]; then
    echo "Not enough gas to deploy contract, requesting from faucet for all addresses"
    sui client faucet --address admin
    sui client faucet --address seller
    sui client faucet --address buyer
    # If network_alias is localnet wait 2 sec
    if [ "$network_alias" == "localnet" ]; then
        sleep 2
    else
        echo "Please try again after some time."
        exit 1
    fi
fi

echo "Publishing"
echo "sui client publish --skip-fetch-latest-git-deps --with-unpublished-dependencies --gas-budget ${GAS_BUDGET} --json ${MOVE_PACKAGE_PATH}"
publish_res=$(sui client publish --skip-fetch-latest-git-deps --with-unpublished-dependencies --gas-budget ${GAS_BUDGET} --json ${MOVE_PACKAGE_PATH})
echo ${publish_res} >.publish.res.json

# Check if the command succeeded (exit status 0)
if [[ "$publish_res" =~ "error" ]]; then
  # If yes, print the error message and exit the script
  echo "Error during move contract publishing.  Details : $publish_res"
  exit 1
fi

# Parse PACKAGE_ID, PUBLISHER, MINT_CAP from the publish response
published_objs=$(echo "$publish_res" | jq -r '.objectChanges[] | select(.type == "published")')
PACKAGE_ID=$(echo "$published_objs" | jq -r '.packageId')

new_objs=$(echo "$publish_res" | jq -r '.objectChanges[] | select(.type == "created")')
PUBLISHER=$(echo "$new_objs" | jq -r 'select(.objectType | contains("2::package::Publisher")).objectId')
MINT_CAP=$(echo "$new_objs" | jq -r 'select(.objectType | contains("::awesome_nft::MintCap")).objectId')

suffix=""
if [ $# -eq 0 ]; then
  suffix=".localnet"
fi

cat >./.env<<-_ENV
SUI_FULLNODE_URL=$NETWORK
PACKAGE_ID=$PACKAGE_ID
PUBLISHER=$PUBLISHER
MINT_CAP=$MINT_CAP
ADMIN_ADDRESS=$(echo "$addresses" | jq -r '.addresses[] | select(.[0] == "admin") | .[1]')
SELLER_ADDRESS=$(echo "$addresses" | jq -r '.addresses[] | select(.[0] == "seller") | .[1]')
BUYER_ADDRESS=$(echo "$addresses" | jq -r '.addresses[] | select(.[0] == "buyer") | .[1]')

_ENV

cat >./.rules.env<<-RULES_ENV
RULES_PACKAGE_ID=$PACKAGE_ID

RULES_ENV

echo "Contract Deployment finished!"

