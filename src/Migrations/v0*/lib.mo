import Debug "mo:base/Debug";

import v0_5_1_types "./v0.5.1/types"

// the versions are seperated into types and upgrade directories to prevent circular dependencies
module {
    public type StableStore = v0_5_1_types.StableStore;

    public type VersionedStableStore = {
        #v0_5_1 : v0_5_1_types.StableStore;
    };

    public func upgrade(versions : VersionedStableStore) : VersionedStableStore {
        switch (versions) {
            case (#v0_5_1(v0_5_1)) { #v0_5_1(v0_5_1) };
        };
    };

    public func get_current_state(asset_versions : VersionedStableStore) : v0_5_1_types.StableStore {
        switch (asset_versions) {
            case (#v0_5_1(stable_store)) { stable_store };
            case (_) Debug.trap(
                "
                Invalid version of stable store (" # debug_show (asset_versions) # ").
                Please call upgrade() on the stable store.
                "
            );
        };
    };

    public func share_version(sstore : v0_5_1_types.StableStore) : VersionedStableStore {
        #v0_5_1(sstore);
    };

};
