/// Module: awesome_nft
module awesome_nft::awesome_nft {
    use std::string::String;

    use sui::package;

    public struct MintCap has key, store {
        id: UID
    }

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

    public struct AWESOME_NFT has drop {}

    fun init(otw: AWESOME_NFT, ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx);

        transfer::public_transfer(MintCap { id: object::new(ctx) }, ctx.sender());
    }

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

        object::delete(id);
    }
}
