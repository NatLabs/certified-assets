// @testmode wasi
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";

import { suite; test } "mo:test";
import CertifiedAssets "../src/Stable";
import Fuzz "mo:fuzz";
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
            "Deduplicates endpoints with the same data",
            func() {
                let endpoint1 = new_endpoint("/assets/images/logo.png", "", false).response_header("Cache-Control", "max-age=3600");

                certify(endpoint1);
                certify(endpoint1);
                certify(endpoint1);

                ignore do ? {
                    assert get_certified_metadata(endpoint1)!.endpoint == (endpoint1.build());
                };

                CertifiedAssets.remove(certs, endpoint1);

                assert CertifiedAssets.get_metadata_from_endpoint(certs, endpoint1.build()) == null;

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

                let cache_control_values = ["no-cache", "max-age=3600"];
                let content_type_values = ["image/png", "image/jpeg", "image/gif"];
                let version_values = ["1.0", "2.0", "3.0"];
                let lang_values = ["en", "fr", "de"];
                let is_fallback_values = [false, true];

                let endpoints = Buffer.Buffer<CertifiedAssets.EndpointRecord>(500);

                // Generate all unique combinations
                for (is_fallback in is_fallback_values.vals()) {
                    for (has_cache_control in [false, true].vals()) {
                        for (cache_control in (if (has_cache_control) cache_control_values else [""]).vals()) {
                            for (has_content_type in [false, true].vals()) {
                                for (content_type in (if (has_content_type) content_type_values else [""]).vals()) {
                                    for (has_version in [false, true].vals()) {
                                        for (version in (if (has_version) version_values else [""]).vals()) {
                                            for (has_lang in [false, true].vals()) {
                                                for (lang in (if (has_lang) lang_values else [""]).vals()) {

                                                    let endpoint = new_endpoint("/assets/images/logo.png", "", is_fallback);

                                                    if (has_cache_control) {
                                                        ignore endpoint.response_header("Cache-Control", cache_control);
                                                    };

                                                    if (has_content_type) {
                                                        ignore endpoint.response_header("Content-Type", content_type);
                                                    };

                                                    if (has_version) {
                                                        ignore endpoint.query_param("version", version);
                                                    };

                                                    if (has_lang) {
                                                        ignore endpoint.query_param("lang", lang);
                                                    };

                                                    endpoints.add(endpoint.build());

                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };

                // Debug.print("Total unique endpoints: " # debug_show (endpoints.size()));

                // certify all endpoint
                for (endpoint in endpoints.vals()) {
                    CertifiedAssets.certify_record(certs, endpoint);
                };

                for ((i, endpoint) in Itertools.enumerate(endpoints.vals())) {

                    // Debug.print("Endpoint " # debug_show i # ": " # debug_show endpoint);
                    ignore do ? {
                        let endpoint2 = get_certified_metadata_from_record(endpoint)!.endpoint;
                        // Debug.print("Retrieved metadata for endpoint " # debug_show i # ": " # debug_show endpoint2);
                        assert endpoint2 == endpoint;
                    };

                    CertifiedAssets.remove_record(certs, endpoint);

                    ignore do ? {
                        let retrieved_metadata = CertifiedAssets.get_metadata_from_endpoint(certs, endpoint);
                        // Debug.print("Retrieved metadata for endpoint " # debug_show i # ": " # debug_show retrieved_metadata);

                        assert retrieved_metadata == null or retrieved_metadata!.endpoint != endpoint;
                    };
                };

            }

        );

    },
);
