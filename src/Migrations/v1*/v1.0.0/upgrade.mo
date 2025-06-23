import V0_5_1_types "../../v0*/v0.5.1/types";
import V1_0_0_types "types";

module {

    public func upgrade_from_v0_5_1(v0_5_1 : V0_5_1_types.StableStore) : V1_0_0_types.StableStore {
        let v1_0_0 = {
            v0_5_1 with settings = { unit_test_mode = false };
            var tree = v0_5_1.tree;
        };

        v1_0_0;
    };

};
