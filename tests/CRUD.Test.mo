// @testmode wasi
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Text "mo:base/Text";
import Order "mo:base/Order";

import { suite; test } "mo:test";
import CertifiedAssets "../src/Stable";
import Fuzz "mo:fuzz";
import Set "mo:map/Set";
import Itertools "mo:itertools/Iter";

let fuzz = Fuzz.fromSeed(0x1234567890abcdef);
let certs = CertifiedAssets.init_stable_store(?{ unit_test_mode = ?true });

func new_endpoint(url : Text, body : Blob, is_fallback : Bool) : CertifiedAssets.Endpoint {
    CertifiedAssets.Endpoint(
        url,
        ?body,
    ).no_request_certification().is_fallback_path(is_fallback);
};

func certify(endpoint : CertifiedAssets.Endpoint) {
    CertifiedAssets.certify(certs, endpoint);
};

func get_certified_metadata_from_record(endpoint : CertifiedAssets.EndpointRecord) : ?CertifiedAssets.Metadata {
    CertifiedAssets.get_metadata_from_endpoint(certs, endpoint);
};

func get_certified_metadata(endpoint : CertifiedAssets.Endpoint) : ?CertifiedAssets.Metadata {
    CertifiedAssets.get_metadata_from_endpoint(certs, endpoint.build());
};

// func verify_expr_path(ct : CertifiedAssets.StableStore, (url, is_fallback) : (Text, Bool), expr_path : [Text]) : Bool {

//     let endpoint = get_endpoint(url, is_fallback);

//     let ?metadata = CertifiedAssets.get_metadata_from_endpoint(ct, endpoint.build()) else return false;

//     return metadata.encoded_expr_path == CertifiedAssets.encode_text_expr_path(expr_path);

// };

suite(
    "CertifiedAssets CRUD Tests",
    func() {

        test(
            "Create and delete a certified endpoint",
            func() {

                let endpoint1 = new_endpoint("/index.html", fuzz.blob.randomBlob(100), false);
                let endpoint2 = new_endpoint("/about.html", fuzz.blob.randomBlob(100), false);
                let endpoint3 = new_endpoint("/contact.html", fuzz.blob.randomBlob(100), true);

                certify(endpoint1);
                certify(endpoint2);
                certify(endpoint3);

                ignore do ? {
                    assert get_certified_metadata(endpoint1)!.endpoint == (endpoint1.build());
                    assert get_certified_metadata(endpoint2)!.endpoint == (endpoint2.build());
                    assert get_certified_metadata(endpoint3)!.endpoint == (endpoint3.build());
                };

                CertifiedAssets.remove(certs, endpoint1);
                CertifiedAssets.remove(certs, endpoint2);
                CertifiedAssets.remove(certs, endpoint3);

                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint1.build()) == null;
                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint2.build()) == null;
                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint3.build()) == null;

                // Ensure that removing a non-existent endpoint does not cause an error
                CertifiedAssets.remove(certs, endpoint1);
                CertifiedAssets.remove(certs, endpoint2);
                CertifiedAssets.remove(certs, endpoint3);

            },
        );

        test(
            "Delete endpoints with the same URL but different data",
            func() {

                let endpoint1 = new_endpoint("/assets/images/logo.png", "", false);
                let endpoint2 = new_endpoint("/assets/images/logo.png", "", true);
                let endpoint3 = new_endpoint("/assets/images/logo.png", "", false);
                let endpoint4 = new_endpoint("/assets/images/logo.png", "", true);

                certify(endpoint1);
                certify(endpoint2);
                certify(endpoint3);
                certify(endpoint4);

                ignore do ? {
                    assert get_certified_metadata(endpoint1)!.endpoint == (endpoint1.build());
                    assert get_certified_metadata(endpoint2)!.endpoint == (endpoint2.build());
                    assert get_certified_metadata(endpoint3)!.endpoint == (endpoint3.build());
                    assert get_certified_metadata(endpoint4)!.endpoint == (endpoint4.build());
                };

                CertifiedAssets.remove(certs, endpoint1);
                CertifiedAssets.remove(certs, endpoint2);

                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint1.build()) == null;
                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint2.build()) == null;

                ignore do ? {
                    assert get_certified_metadata(endpoint3)!.endpoint == (endpoint3.build());
                    assert get_certified_metadata(endpoint4)!.endpoint == (endpoint4.build());
                };

                CertifiedAssets.remove(certs, endpoint3);
                CertifiedAssets.remove(certs, endpoint4);
                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint3.build()) == null;
                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint4.build()) == null;

            },
        );

        // this test is important because the other endpoint fields are hashed
        // and the query, request or response headers are stored in the endpoints metadata
        // to be matched with the http request. The endpoint that matches the request best
        // is the one that should be returned.
        test(
            "Delete endpoints with the same data but different query, request or response headers",
            func() {

                let endpoint1 = new_endpoint("/assets/images/logo.png", "", false).response_header("Cache-Control", "no-cache");
                let endpoint2 = new_endpoint("/assets/images/logo.png", "", false).response_header("Cache-Control", "no-cache").response_header("Content-Type", "image/png");

                CertifiedAssets.certify(certs, endpoint1);
                CertifiedAssets.certify(certs, endpoint2);

                ignore do ? {
                    assert get_certified_metadata(endpoint1)!.endpoint == (endpoint1.build());
                    assert get_certified_metadata(endpoint2)!.endpoint == (endpoint2.build());
                };

                CertifiedAssets.remove(certs, endpoint1);

                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint1.build()) == null;

                ignore do ? {
                    assert get_certified_metadata(endpoint1)!.endpoint == (endpoint2.build());
                };

                CertifiedAssets.remove(certs, endpoint2);
                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint1.build()) == null;

                // Certify in reverse order so that the delete works correctly
                CertifiedAssets.certify(certs, endpoint2);
                CertifiedAssets.certify(certs, endpoint1);

                ignore do ? {
                    assert get_certified_metadata(endpoint1)!.endpoint == (endpoint1.build());
                    assert get_certified_metadata(endpoint2)!.endpoint == (endpoint2.build());
                };

                CertifiedAssets.remove(certs, endpoint1);

                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint1.build()) == null;
                ignore do ? {
                    assert get_certified_metadata(endpoint2)!.endpoint == (endpoint2.build());
                };
                CertifiedAssets.remove(certs, endpoint2);
                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint2.build()) == null;

            }

        );

        // this test is important because the other endpoint fields are hashed
        // and the query, request or response headers are stored in the endpoints metadata
        // to be matched with the http request. The endpoint that matches the request best
        // is the one that should be returned.
        test(
            "Delete endpoints with the same data but different query, request or response headers",
            func() {

                var endpoints = Array.tabulate(
                    1000,
                    func(i : Nat) : CertifiedAssets.EndpointRecord {

                        let endpoint = new_endpoint("/assets/images/logo.png", "", fuzz.bool.random());

                        if (fuzz.bool.random()) {
                            ignore endpoint.response_header(
                                "Cache-Control",
                                if (i % 2 == 0) "no-cache" else "max-age=3600",
                            );
                        };

                        if (fuzz.bool.random()) {
                            ignore endpoint.response_header(
                                "Content-Type",
                                fuzz.array.randomValue(["image/png", "image/jpeg", "image/gif"]),
                            );
                        };

                        if (fuzz.bool.random()) {
                            ignore endpoint.query_param(
                                "version",
                                fuzz.array.randomValue(["1.0", "2.0", "3.0"]),
                            );
                        };

                        if (fuzz.bool.random()) {
                            ignore endpoint.query_param(
                                "lang",
                                fuzz.array.randomValue(["en", "fr", "de"]),
                            );
                        };

                        endpoint.build()

                    },
                );

                func get_unique_endpoint_key(endpoint : CertifiedAssets.EndpointRecord) : Text {

                    let tuple_key_cmp = func(a : (Text, Text), b : (Text, Text)) : Order.Order {
                        Text.compare(a.0, b.0);
                    };

                    let response_headers = Array.sort(endpoint.response_headers, tuple_key_cmp);
                    let query_params = Array.sort(endpoint.query_params, tuple_key_cmp);

                    debug_show (response_headers, query_params, endpoint.is_fallback_path);
                };

                let hash_utils = (
                    func(endpoint : CertifiedAssets.EndpointRecord) : Nat32 {
                        Set.hashText(get_unique_endpoint_key(endpoint));
                    },
                    func(a : CertifiedAssets.EndpointRecord, b : CertifiedAssets.EndpointRecord) : Bool {
                        get_unique_endpoint_key(a) == get_unique_endpoint_key(b);
                    },
                );

                // deduplicate endpoints
                let set = Set.fromIter<CertifiedAssets.EndpointRecord>(endpoints.vals(), hash_utils);
                endpoints := Set.toArray(set);
                Debug.print("Unique endpoints: " # debug_show (endpoints.size()));

                // certify endpoint
                for (endpoint in endpoints.vals()) {
                    CertifiedAssets.certify_record(certs, endpoint);
                };

                for ((i, endpoint) in Itertools.enumerate(endpoints.vals())) {

                    Debug.print("Endpoint " # debug_show i # ": " # debug_show endpoint);
                    ignore do ? {
                        let endpoint2 = get_certified_metadata_from_record(endpoint)!.endpoint;
                        Debug.print("Retrieved metadata for endpoint " # debug_show i # ": " # debug_show endpoint2);
                        assert endpoint2 == endpoint;
                    };

                    CertifiedAssets.remove_record(certs, endpoint);

                    ignore do ? {
                        let retrieved_metadata = CertifiedAssets.get_metadata_from_endpoint(certs, endpoint);
                        Debug.print("Retrieved metadata for endpoint " # debug_show i # ": " # debug_show retrieved_metadata);

                        assert retrieved_metadata == null or retrieved_metadata!.endpoint != endpoint;
                    };
                };

            }

        );

    },
);
