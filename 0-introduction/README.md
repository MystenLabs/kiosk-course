# Introduction

Getting acquainted with the basic contract for minting NFTs, _<span>publish.sh</span>_ and cli-ptbs.

## Contract

The contract is a simple NFT contract that allows minting of NFTs. It is located in the `move` folder and is named `awesome_nft`.

It contains the following structs:
- `MintCap`: A struct that enables the admin and only the admin to mint NFTs.
    ```
    public struct MintCap has key, store {
        id: UID
    }
    ```
- `AwesomeNFT`: A struct that represents an NFT.
    ```
    public struct AwesomeNFT has key, store {
        id: UID,
        name: String,
        description: String,
        link: String,
        image_url: String,
        thumbnail_url: String,
        project_url: String,
        creator: String
    }
    ```
- `AWESOME_NFT`: [One-time-witness](https://move-book.com/programmability/one-time-witness.html) for claiming the [Publisher](https://examples.sui.io/basics/publisher.html) object.
    ```
    public struct AWESOME_NFT has drop {}
    ```

The contract also contains the following functions:
- `init()`: Claims `Publisher` and creates a `MintCap` which are transferred to the contract-publisher.
    ```
    fun init(otw: AWESOME_NFT, ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx);
        transfer::public_transfer(MintCap { id: object::new(ctx) }, ctx.sender());
    }
    ```
- `new()`: Mints a new `AwesomeNFT`, callable only by the owner of the `MintCap`.
    ```
    public fun new(
        _: &MintCap,
        name: String,
        description: String,
        link: String,
        image_url: String,
        thumbnail_url: String,
        project_url: String,
        creator: String,
        ctx: &mut TxContext
    ): AwesomeNFT {
        AwesomeNFT {
            id: object::new(ctx),
            name,
            description,
            link,
            image_url,
            thumbnail_url,
            project_url,
            creator
        }
    }
    ```
- `drop()`: Destroys an `AwesomeNFT`.
    ```
    public fun drop(nft: AwesomeNFT) {
        let AwesomeNFT {
            id,
            name: _,
            description: _,
            link: _,
            image_url: _,
            thumbnail_url: _,
            project_url: _,
            creator: _
        } = nft;
        id.delete();
    }
    ```

Pretty simple isn't it? Where is the kiosk you ask? Well, Move programming language combined with Sui's object-oriented model allows us to create modular and reusable code. The kiosk is a separate module that we will be using in the next sections which can work just fine with any struct that has the `key`, `store` abilities in the Sui blockchain.

## <span>publish.sh</span>

The _<span>publish.sh<span>_ script takes the necessary steps to ensure that you have the necessary roles (admin, seller, buyer) on your keystore and publishes the contract to your current sui environment.
To check your environment run `sui client active-env`. To switch your environment you can use `sui client switch --env <env-name>`.

> ⚠️  Be sure not to use mainnet!

After publishing the contract, the script will also store the `PACKAGE_ID`, `PUBLISHER`, `MINT_CAP`, `ADMIN_ADDRESS`, `SELLER_ADDRESS`, and `BUYER_ADDRESS` values in a new `.env` file.

## <span>mint.sh</span>

_<span>mint.sh</span>_ is supposed to help us mint an NFT. Remember that only the owner of the `MintCap` can mint NFTs.
Let's look at the _<span>mint.sh</span>_ script step by step. 

First we check that the `.env` file exists and load the variables from it:

```bash
# Load variables from .env file
if [ -f .env ]; then
    source .env
else
    echo "No .env file found"
    exit 1
fi
```

Then we set a gas-budget for our programmable transaction calls:
> ℹ️ Note that in more recent versions this step is not needed, as `sui client ptb` (below) will dry-run the transaction and set the gas-budget automatically.

```bash
GAS_BUDGET=100_000_000  # 0.1 SUI
```

Next we make sure we are the owner of the `MintCap`, which should be the admin.

```bash
# admin has the MintCap
sui client switch --address admin
```

Now we can create and call the programmable transaction block (ptb) to mint an NFT.

As we can see we use `--move-call <function> <args>` to call the `${PACKAGE_ID}::awesome_nft::new` function with the necessary arguments.

Then we assign the output of the previous function to a new variable called `nft` and transfer it to the seller using `SELLER_ADDRESS` we stores in the _.env_ above.

`--gas-budget` is set to the previously defined value, and we use `--json` in order to programmatically parse the output of the ptb.

Notice that we need to use single quotes inside double quotes to pass strings as arguments to the Move function, while object arguments need the `@$` prefix.

```bash
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
    --transfer-objects [nft] @$SELLER_ADDRESS \
    --gas-budget $GAS_BUDGET \
    --json)
```

Finally, we parse the output of the ptb and add the newly created NFT id to the _.nft.env_ file, using [jq](https://jqlang.github.io/jq/).
This parsing and storing will come in handy in the next sections.

```bash
# Parse AwesomeNFT's id from the mint response
NFT_ID=$(echo "$mint_res" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("::awesome_nft::AwesomeNFT")).objectId')
echo NFT_ID=$NFT_ID > .nft.env
```
