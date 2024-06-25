/// Module: awesome_nft
module awesome_nft::awesome_nft {
    use std::string::String;

    use sui::kiosk::Kiosk;
    use sui::package;
    use sui::transfer_policy::TransferPolicy;

    use awesome_nft::awesome_extension;

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

    /// Creates a new AwesomeNFT and locks it in the Kiosk `kiosk`.
    /// Note that `kiosk` should have the extension `awesome_nft::awesome_extension::Ext` installed.
    public fun mint_to_kiosk(
        _: &MintCap,
        name: String,
        description: String,
        link: String,
        image_url: String,
        thumbnail_url: String,
        project_url: String,
        creator: String,
        kiosk: &mut Kiosk,
        policy: &TransferPolicy<AwesomeNFT>,
        ctx: &mut TxContext
    ) {
        awesome_extension::lock(
            kiosk, 
            AwesomeNFT {
                id: object::new(ctx),
                name,
                description,
                link,
                image_url,
                thumbnail_url,
                project_url,
                creator
            },
            policy
        );
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
        id.delete();
    }
}
