module awesome_nft::awesome_extension {
    use sui::kiosk::{Kiosk, KioskOwnerCap};
    use sui::kiosk_extension;
    use sui::transfer_policy::TransferPolicy;
    use kiosk::personal_kiosk;

    const ENotPersonalKiosk: u64 = 0;
    /// Extension witness.

    /// Value that represents the `lock` and `place` permission in the
    /// permissions bitmap.
    const LOCK: u128 = 2;

    public struct Ext has drop {}

    /// Kiosk owner can add the extension to their kiosk.
    public fun add(kiosk: &mut Kiosk, cap: &KioskOwnerCap, ctx: &mut TxContext) {
        assert!(personal_kiosk::is_personal(kiosk), ENotPersonalKiosk);
        kiosk_extension::add(Ext {}, kiosk, cap, LOCK, ctx)
    }

    /// Package can lock an item to a `Kiosk` with the extension.
    public(package) fun lock<T: key + store>(
        kiosk: &mut Kiosk, item: T, policy: &TransferPolicy<T>
    ) {
        kiosk_extension::lock(Ext {}, kiosk, item, policy)
    }
}
