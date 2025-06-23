import Debug "mo:base/Debug";

import v0 "./v0*";
import v1 "./v1*";

module {

    public type VersionedStableStore = {
        #v0 : v0.VersionedStableStore;
        #v1 : v1.VersionedStableStore;
    };

    /// Major Version Upgrades
    ///
    /// In most cases it would not be possible to upgrade from one major version to another,
    /// because the internal structure of the stable stores are not compatible and it would require
    /// a complete migration of the data which could potentially exceed the instruction limit of the canister.
    /// As a result, this function will trap.
    ///
    /// In the rare cases the internal structure don't differ that much and we can perform the upgrade from the
    /// previous major version, we will do so here.
    public func upgrade(versions : VersionedStableStore) : VersionedStableStore {
        switch (versions) {
            case (#v0(_v0)) {
                let latest_v0_version = switch (v0.upgrade(_v0)) {
                    case (#v0_5_1(v0_5_1)) { v0_5_1 };
                };

                #v1(v1.upgrade(#v0_5_1(latest_v0_version)));
            };
            case (#v1(v1)) { #v1(v1) };
        };
    };

    public func get_current_state(asset_versions : VersionedStableStore) : v1.StableStore {
        switch (asset_versions) {
            case (#v1(stable_store)) v1.get_current_state(stable_store);
            case (_) Debug.trap(
                "
                Invalid version of stable store (" # debug_show (asset_versions) # ").
                Please call upgrade() on the stable store.
                "
            );
        };
    };

    public func share_version(sstore : v1.StableStore) : VersionedStableStore {
        #v1(v1.share_version(sstore));
    };

};
