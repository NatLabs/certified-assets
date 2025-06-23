import Debug "mo:base/Debug";

import v0_5_1_types "../v0*/v0.5.1/types";

import v1_0_0_types "./v1.0.0/types";
import v1_0_0_upgrade "v1.0.0/upgrade";

// the versions are seperated into types and upgrade directories to prevent circular dependencies
module {
    public type StableStore = v1_0_0_types.StableStore;

    public type VersionedStableStore = {
        #v0_5_1 : v0_5_1_types.StableStore;
        #v1_0_0 : v1_0_0_types.StableStore;
    };

    public func upgrade(versions : VersionedStableStore) : VersionedStableStore {
        switch (versions) {
            case (#v0_5_1(v0_5_1)) {
                let v1_0_0 = v1_0_0_upgrade.upgrade_from_v0_5_1(v0_5_1);
                #v1_0_0(v1_0_0);
            };
            case (#v1_0_0(v1_0_0)) { #v1_0_0(v1_0_0) };
        };
    };

    public func get_current_state(asset_versions : VersionedStableStore) : v1_0_0_types.StableStore {
        switch (asset_versions) {
            case (#v1_0_0(stable_store)) { stable_store };
            case (_) Debug.trap(
                "
                Invalid version of stable store (" # debug_show (asset_versions) # ").
                Please call upgrade() on the stable store.
                "
            );
        };
    };

    public func share_version(sstore : v1_0_0_types.StableStore) : VersionedStableStore {
        #v1_0_0(sstore);
    };

};
