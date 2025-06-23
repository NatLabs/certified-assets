import Debug "mo:base/Debug";
import Iter "mo:base/Iter";

import { suite; test } "mo:test";
import CertifiedAssets "../src/Stable";
import Fuzz "mo:fuzz";

import CertifiedAssets_v0_5_1 "mo:certified-assets-v0_5_1";

suite(
    "Migration Tests",
    func() {
        test(
            "Upgrade from v0.5.1 to v1.0.0",
            func() {

                let certs_v0_5_1 = CertifiedAssets_v0_5_1.init_stable_store();

                let endpoint_v0_5_1 = CertifiedAssets_v0_5_1.Endpoint(
                    "/index.html",
                    ?Blob.fromText("Hello, World!"),
                );

                CertifiedAssets_v0_5_1.certify(certs_v0_5_1, endpoint_v0_5_1);

                let certs_v1_0_0 = CertifiedAssets.upgrade(certs_v0_5_1);

            },
        );

    },
);
