import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat16 "mo:base/Nat16";
import Result "mo:base/Result";
import Text "mo:base/Text";

import CertTree "mo:ic-certification/CertTree";
import MerkleTree "mo:ic-certification/MerkleTree";
import CanisterSigs "mo:ic-certification/CanisterSigs";
import CertifiedData "mo:base/CertifiedData";
import SHA256 "mo:sha2/Sha256";
import HttpParser "mo:http-parser";
import HttpTypes "mo:http-types";
import { CBOR } "mo:serde";
import Map "mo:map/Map";
import RepIndyHash "mo:rep-indy-hash";
import Vector "mo:vector";
import Itertools "mo:itertools/Iter";

import Base64 "mo:encoding/Base64";

import Utils "Utils";
import EndpointModule "Endpoint";

module Module {

    type Buffer<A> = Buffer.Buffer<A>;
    type Iter<A> = Iter.Iter<A>;
    type Map<K, V> = Map.Map<K, V>;
    type Result<T, E> = Result.Result<T, E>;
    type Vector<A> = Vector.Vector<A>;

    let { thash; bhash } = Map;

    type Metadata = {
        endpoint : EndpointRecord;
        encoded_expr_path : Blob;
        full_expr_path : [Blob];
        ic_certificate_expression : Text;
    };

    public type MetadataMap = Map<Text, Map<Blob, Vector<Metadata>>>;

    public type StableStore = {
        var tree : MerkleTree.Tree;
        metadata_map : MetadataMap;
    };

    public let Endpoint = EndpointModule.Endpoint;
    public type Endpoint = EndpointModule.Endpoint;
    public type EndpointRecord = EndpointModule.EndpointRecord;

    /// Create a new stable CertifiedAssets instance on the heap.
    /// This instance is stable and will not be cleared on canister upgrade.
    ///
    /// ```motoko
    /// let cert_store = CertifiedAssets.init_stable_store();
    /// let certs = CertifiedAssets.CertifiedAssets(?cert_store);
    /// ```

    public func init_stable_store() : StableStore {
        {
            var tree = MerkleTree.empty();
            metadata_map = Map.new();
        };
    };

    /// The implementation of the IC's Response Verification version 2.
    ///
    /// The module provides a way to store the certified data on the heap or in stable persistent memory.
    /// - heap - creates a new instance of the class that will be cleared on canister upgrade.
    /// ```motoko
    /// let certs = CertifiedAssets.CertifiedAssets(null);
    /// ```
    ///
    /// - stable heap - creates a new stable instance of the class that will persist on canister upgrade.
    /// ```motoko
    /// let cert_store = CertifiedAssets.init_stable_store();
    /// let certs = CertifiedAssets.CertifiedAssets(?cert_store);
    /// ```
    ///
    /// If your instance is stable, it is advised to `clear()` all the certified endpoints and
    /// re-certify them on canister upgrade if the data has changed.
    ///
    public class CertifiedAssets(stable_store : ?StableStore) = self {

        let internal : StableStore = switch (stable_store) {
            case (?(stable_store)) stable_store;
            case (null) Module.init_stable_store();
        };

        let metadata_map : MetadataMap = internal.metadata_map;

        public func certify(endpoint : Endpoint) = Module.certify(internal, endpoint);

        /// Remove a certified EndpointModule.
        public func remove(endpoint : Endpoint) = Module.remove(internal, endpoint);

        /// Removes all the certified endpoints that match the given URL.
        public func remove_all(url : Text) = Module.remove_all(internal, url);

        /// Get all certified endpoints.
        public func endpoints() : Iter<EndpointRecord> = Module.endpoints(internal);

        /// Clear all certified endpoints.
        public func clear() = Module.clear(internal);

        /// Modifies a given response by adding the certificate headers.
        /// This only works if the endpoint has already been certified.
        public func get_certified_response(req : HttpTypes.Request, res : HttpTypes.Response, response_hash: ?Blob) : Result<HttpTypes.Response, Text> {
            Module.get_certified_response(internal, req, res, response_hash);
        };

        /// Get the certificate for a given request.
        ///
        /// This function returns the certificate headers for a predefined response.
        /// This only works if the endpoint has already been certified.
        ///
        /// ```motoko
        /// public func http_request(req : HttpTypes.Request) : HttpTypes.Response {
        ///     let res : HttpTypes.Response = {
        ///         status_code = 200;
        ///         headers = [("Content-Type", "text/plain")];
        ///         body = "Hello, World!";
        ///         ...
        ///     };
        ///
        ///     let #ok(certificate_headers) = cert.get_certificate(req, res, null);
        ///     return { res with headers = Array.append(res.headers, certificate_headers};
        /// };
        /// ```
        public func get_certificate(req : HttpTypes.Request, res : HttpTypes.Response, response_hash : ?Blob) : Result<[HttpTypes.Header], Text> {
            Module.get_certificate(internal, req, res, response_hash);
        };

        /// Retrieves the encoded certificate and tree based on the given keys.
        /// If keys are set to `null`, the entire tree is returned.
        public func get_certified_tree(keys : ?[Text]) : Result<CertifiedTree, Text> {
            Module.get_certified_tree(internal, keys);
        };
    };

    let IC_CERTIFICATE_EXPRESSION = "ic-certificateexpression";
    let IC_CERT_BODY = ":ic-cert-body";
    let IC_CERT_METHOD = ":ic-cert-method";
    let IC_CERT_QUERY = ":ic-cert-query";
    let IC_CERT_STATUS = ":ic-cert-status";

    public func certify(ct : StableStore, endpoint : Endpoint) {
        let endpoint_record = endpoint.build();
        // Debug.print("certifying endpoint: " # debug_show (endpoint_record.url));
        MerkleTreeOps.put(ct, ["http_assets", Text.encodeUtf8(endpoint_record.url)], endpoint_record.hash);

        let paths = if (endpoint_record.url == "") [""] else Iter.toArray(
            Text.split(endpoint_record.url, #text "/")
        );
        
        // Debug.print("url: " # debug_show endpoint_record.url);
        // Debug.print("paths: " # debug_show paths);
        let text_expr_path = Array.tabulate(
            paths.size() + 2,
            func(i : Nat) : Text {
                if (i == 0) return "http_expr";
                if (i < paths.size() + 1) return paths[i - 1];

                // if (Text.endsWith(endpoint_record.url, #text ".html")) return "<$>";

                return if (endpoint_record.is_fallback_path) "<*>" else "<$>";
            },
        );

        // encode the segments to cbor for the expr_path field for the certificate
        let candid_expr_path = to_candid (text_expr_path);
        let cbor_res = CBOR.encode(candid_expr_path, [], null);
        let encoded_expr_path = switch (cbor_res) {
            case (#ok(encoded_expr_path)) encoded_expr_path;
            case (#err(errMsg)) Debug.trap("Internal Error: Report bug in NatLabs/certified-assets repo.\n\t" # errMsg);
        };

        let expr_path = Array.map(text_expr_path, Text.encodeUtf8);

        let extract_field = func((field, _) : (Text, Text)) : Text = field;
        let certified_query_params = endpoint_record.query_params;
        let certified_request_headers = endpoint_record.request_headers;
        let certified_response_headers = endpoint_record.response_headers;
        let no_certification = endpoint_record.no_certification;
        let no_request_certification = endpoint_record.no_request_certification;

        let query_params_fields = Array.map(endpoint_record.query_params, extract_field);
        let request_headers_fields = Array.map(endpoint_record.request_headers, extract_field);
        let response_headers_fields = Array.map(endpoint_record.response_headers, extract_field);

        let fields = Buffer.Buffer<Text>(8);

        var ic_certificate_expression = switch (no_certification, no_request_certification) {
            case (true, _) {
                "
                    default_certification (
                        ValidationArgs {
                            no_certification: Empty { }
                        }
                    )
                ";
            };
            case (false, true) {
                "
                    default_certification (
                        ValidationArgs {
                            certification: Certification {
                                no_request_certification: Empty { },
                                response_certification: ResponseCertification {
                                    certified_response_headers: ResponseHeaderList {
                                        headers: " # debug_show response_headers_fields # "
                                    }
                                }
                            }
                        }
                    )
                ";
            };
            case (false, false) {
                "
                    default_certification (
                        ValidationArgs {
                            certification: Certification {
                                request_certification: RequestCertification {
                                    certified_request_headers: " # debug_show request_headers_fields # ",
                                    certified_query_parameters: " # debug_show query_params_fields # "
                                },
                                response_certification: ResponseCertification {
                                    certified_response_headers: ResponseHeaderList {
                                        headers: " # debug_show response_headers_fields # "
                                    }
                                }
                            }
                        }
                    )
                ";
            };
        };

        ic_certificate_expression := Text.join(" ", Text.tokens(ic_certificate_expression, #predicate(func(c : Char) : Bool = c == ' ' or c == '\n')));

        let expr_hash = SHA256.fromBlob(#sha256, Text.encodeUtf8(ic_certificate_expression));

        var request_hash : Blob = "";

        if (not no_request_certification and not no_certification) {

            let buffer = Buffer.Buffer<(Text, RepIndyHash.Value)>(8);

            for ((name, value) in certified_request_headers.vals()) {
                if (value.size() != 0) {
                    buffer.add((Text.toLowercase(name), #Text(value)));
                };
            };

            let method = endpoint_record.method;
            buffer.add((IC_CERT_METHOD, #Text(method)));

            let query_params = Array.tabulate(
                certified_query_params.size(),
                func(i : Nat) : Text {
                    let (name, value) = certified_query_params[i];
                    (name # "=" # value);
                },
            );

            let concatenated_query_params = Text.join("&", query_params.vals());
            // Debug.print("concatenated_query_params: " # debug_show concatenated_query_params);
            let hashed_query_params = SHA256.fromBlob(#sha256, Text.encodeUtf8(concatenated_query_params));
            buffer.add((IC_CERT_QUERY, #Blob(hashed_query_params)));

            let rep_val = #Map(Buffer.toArray(buffer));
            let request_header_hash = RepIndyHash.hash_val(rep_val);

            let request_body_hash : Blob = SHA256.fromBlob(#sha256, ""); // the body is empty because this is expected to be either a GET, HEAD or OPTIONS requests
            // Debug.print("request rep val: " # debug_show rep_val);
            request_hash := SHA256.fromArray(#sha256, Array.append(request_header_hash, Blob.toArray(request_body_hash)));
        };

        var response_hash : Blob = "";

        if (not no_certification) {

            let buffer = Buffer.Buffer<(Text, RepIndyHash.Value)>(8);

            for ((name, value) in certified_response_headers.vals()) {
                if (value.size() != 0 and Text.toLowercase(name) != "ic-certificate") {
                    buffer.add((Text.toLowercase(name), #Text(value)));
                };
            };

            buffer.add(IC_CERTIFICATE_EXPRESSION, #Text(ic_certificate_expression));

            let status = endpoint_record.status;
            buffer.add((IC_CERT_STATUS, #Nat(Nat16.toNat(status))));

            let rep_val = #Map(Buffer.toArray(buffer));
            let response_headers_hash = RepIndyHash.hash_val(rep_val);

            let headers_and_body_hash = Array.append(
                response_headers_hash,
                Blob.toArray(endpoint_record.hash),
            );

            response_hash := SHA256.fromArray(#sha256, headers_and_body_hash);
        };

        // Debug.print("request_hash: " # debug_show request_hash);
        // Debug.print("response_hash: " # debug_show response_hash);

        assert (not no_certification) or (no_certification and ((request_hash == "") and (response_hash == "")));

        let full_expr_path = Array.append(expr_path, [expr_hash, request_hash, response_hash]);

        MerkleTreeOps.put(ct, full_expr_path, "");

        MerkleTreeOps.setCertifiedData(ct);

        let metadata : Metadata = {
            endpoint = endpoint_record;
            encoded_expr_path;
            full_expr_path;
            ic_certificate_expression;
        };

        let buffer = Buffer.Buffer<(Text, RepIndyHash.Value)>(3);

        // this is not an official field, but it is used internally to uniquely identify the http request
        buffer.add((IC_CERT_BODY, #Blob(endpoint_record.hash)));

        if (not no_request_certification and not no_certification) {
            buffer.add((IC_CERT_METHOD, #Text(endpoint_record.method)));
        };

        if (not no_certification) {
            buffer.add((IC_CERT_STATUS, #Nat(Nat16.toNat(endpoint_record.status))));
        };

        // Debug.print("buffer for unique_http_hash: " # debug_show Buffer.toArray(buffer));
        let unique_http_hash = Blob.fromArray(RepIndyHash.hash_val(#Map(Buffer.toArray(buffer))));

        let opt_nested_map = Map.get(ct.metadata_map, thash, endpoint_record.url);

        let (nested_map, opt_vector) = switch (opt_nested_map) {
            case (?nested_map) {
                (nested_map, Map.get(nested_map, bhash, unique_http_hash));
            };
            case (null) {
                let nested_map = Map.new<Blob, Vector<Metadata>>();
                ignore Map.put(ct.metadata_map, thash, endpoint_record.url, nested_map);
                (nested_map, null);
            };
        };

        switch (opt_vector) {
            case (null) {
                let vector = Vector.new<Metadata>();
                Vector.add(vector, metadata);
                ignore Map.put(nested_map, bhash, unique_http_hash, vector);
            };
            case (?(vector)) {
                Vector.add(vector, metadata);
            };
        };
    };

    /// Remove a certified EndpointModule.
    public func remove(ct : StableStore, endpoint : Endpoint) {
        let endpoint_record = endpoint.build();
        MerkleTreeOps.delete(ct, ["http_assets", Text.encodeUtf8(endpoint_record.url)]);

        let ?metadata = get_metadata_from_endpoint(ct, endpoint_record) else return;
        MerkleTreeOps.delete(ct, metadata.full_expr_path);

        MerkleTreeOps.setCertifiedData(ct);
    };

    /// Removes all the certified endpoints that match the given URL.
    public func remove_all(ct : StableStore, url : Text) {
        let endpoint = Endpoint(url, null).build();
        MerkleTreeOps.delete(ct, ["http_assets", Text.encodeUtf8(endpoint.url)]);

        let ?nested_map = Map.remove(ct.metadata_map, thash, endpoint.url) else return;

        for ((_, vector) in Map.entries(nested_map)) {
            for (metadata in Vector.vals(vector)) {
                MerkleTreeOps.delete(ct, metadata.full_expr_path);
            };
        };

        MerkleTreeOps.setCertifiedData(ct);
    };

    public func endpoints(ct : StableStore) : Iter<EndpointRecord> {
        Itertools.flatten(
            Iter.map(
                Map.vals(ct.metadata_map),
                func(nested_map : Map<Blob, Vector<Metadata>>) : Iter<EndpointRecord> {
                    Itertools.flatten(
                        Iter.map(
                            Map.vals(nested_map),
                            func(vector : Vector<Metadata>) : Iter<EndpointRecord> {
                                Iter.map(
                                    Vector.vals(vector),
                                    func(metadata : Metadata) : EndpointRecord {
                                        metadata.endpoint;
                                    },
                                );
                            },
                        )
                    );
                },
            )
        );
    };

    /// Clear all certified endpoints.
    public func clear(ct : StableStore) {
        MerkleTreeOps.delete(ct, ["http_assets"]);
        MerkleTreeOps.delete(ct, ["http_expr"]);

        Map.clear(ct.metadata_map);
        MerkleTreeOps.setCertifiedData(ct);
    };

    /// Modifies a given response by adding the certificate headers.
    public func get_certified_response(ct : StableStore, req : HttpTypes.Request, res : HttpTypes.Response, response_hash: ?Blob) : Result<HttpTypes.Response, Text> {
        let headers_res = get_certificate(ct, req, res, response_hash);
        let #ok(headers) = headers_res else return Utils.send_error(headers_res);

        #ok({ res with headers = Array.append(res.headers, headers) });
    };

    /// Get the certificate headers for a given request.
    public func get_certificate(ct : StableStore, req : HttpTypes.Request, res : HttpTypes.Response, response_hash: ?Blob) : Result<[HttpTypes.Header], Text> {
        if (req.certificate_version == ?2) v2(ct, req, res, response_hash) else v1(ct, req);
    };

    public type CertifiedTree = {
        certificate : Blob;
        tree : Blob;
    };

    // /// Get the sha256 hash of the given data.
    // public func get_hash(ct: StableStore, endpoint: Endpoint): ?Blob {

    // };

    /// Retrieves the certificate tree based on the given keys.
    /// If keys are set to `null`, the entire tree is returned.
    public func get_certified_tree(ct : StableStore, keys : ?[Text]) : Result<CertifiedTree, Text> {
        let ?certificate = CertifiedData.getCertificate() else {
            return #err("CertifiedData.getCertificate() failed: no data certificate available. \nTry calling this as a query call, if you are calling it as an update call.");
        };

        let vec = Vector.new<[Blob]>();

        let keys_iter : Iter<Text> = switch (keys) {
            case (?keys) keys.vals();
            case (null) Map.keys(ct.metadata_map);
        };

        label for_loop for (key in keys_iter) {
            // v1 certification
            Vector.add(vec, ["http_assets", Text.encodeUtf8(key)] : [Blob]);

            let nested_map = switch (Map.get(ct.metadata_map, thash, key)) {
                case (?nested_map) nested_map;
                case (null) continue for_loop;
            };

            for (vector in Map.vals(nested_map)) {
                for (metadata in Vector.vals(vector)) {
                    // v2 certification
                    Vector.add(vec, metadata.full_expr_path);
                };
            };
        };

        let witness = MerkleTreeOps.reveals(ct, Vector.vals(vec));
        let tree = MerkleTreeOps.encodeWitness(witness);

        #ok({ certificate; tree });
    };

    func v1(ct : StableStore, req : HttpTypes.Request) : Result<[HttpTypes.Header], Text> {
        let url = HttpParser.URL(req.url, HttpParser.Headers([]));
        let url_path = url.path.original;

        let result = get_certified_tree(ct, ?[url_path]);
        let #ok({ certificate; tree }) = result else return Utils.send_error(result);

        return #ok([(
            "ic-certificate",
            "certificate=:" # base64(certificate) # ":, " # "tree=:" # base64(tree) # ":",
        )]);
    };

    func v2(ct : StableStore, req : HttpTypes.Request, res : HttpTypes.Response, response_hash: ?Blob) : Result<[HttpTypes.Header], Text> {
        let url = HttpParser.URL(req.url, HttpParser.Headers([]));
        let url_path = url.path.original;

        let ?metadata = get_metadata(ct, req, res, response_hash) else return #err("no metadata found for this url");
        // Debug.print("metadata: " # debug_show (metadata));

        let witness = MerkleTreeOps.reveal(ct, metadata.full_expr_path);
        let encoded_witness = MerkleTreeOps.encodeWitness(witness);

        let ?certificate = CertifiedData.getCertificate() else {
            return #err("CertifiedData.getCertificate failed. Call this as a query call!");
        };

        let ic_certificate_fields = [
            "certificate=:" # base64(certificate) # ":",
            "tree=:" # base64(encoded_witness) # ":",
            "version=2",
            "expr_path=:" # base64(metadata.encoded_expr_path) # ":",
        ];

        return #ok([
            ("ic-certificate", Text.join(", ", ic_certificate_fields.vals())),
            (IC_CERTIFICATE_EXPRESSION, metadata.ic_certificate_expression),
        ]);
    };

    func get_metadata(ct : StableStore, req : HttpTypes.Request, res : HttpTypes.Response, response_hash: ?Blob) : ?Metadata {
        let url = HttpParser.URL(req.url, HttpParser.Headers([]));

        let endpoint = switch(response_hash){
            case (?response_hash) {
                Endpoint(req.url, null)
                    .method(req.method)
                    .query_params(Iter.toArray(url.queryObj.trieMap.entries()))
                    .request_headers(req.headers)
                    .response_headers(res.headers)
                    .status(res.status_code)
                    .hash(response_hash);
            };
            case (null) {
                Endpoint(req.url, ?res.body)
                    .method(req.method)
                    .query_params(Iter.toArray(url.queryObj.trieMap.entries()))
                    .request_headers(req.headers)
                    .response_headers(res.headers)
                    .status(res.status_code);
            };
        };

        get_metadata_from_endpoint(ct, endpoint.build());
    };

    func get_metadata_from_endpoint(ct : StableStore, endpoint_record : EndpointRecord) : ?Metadata {
        // Debug.print("Starting get_metadata_from_endpoint" # debug_show (endpoint_record.url));

        let nested_map = switch (Map.get(ct.metadata_map, thash, endpoint_record.url)) {
            case (?nested_map) nested_map;
            case (null) return null;
        };

        // Debug.print("found nested map: " # debug_show Map.toArray(nested_map));

        let buffer = Buffer.Buffer<(Text, RepIndyHash.Value)>(3);
        // first check for no certification hash (occurs when only the body is certified)
        buffer.add((IC_CERT_BODY, #Blob(endpoint_record.hash)));

        let no_certification_hash = Blob.fromArray(RepIndyHash.hash_val(#Map(Buffer.toArray(buffer))));

        var metadata_array : [Metadata] = switch (Map.get(nested_map, bhash, no_certification_hash)) {
            case (?vec) Vector.toArray(vec);
            case (null) [];
        };

        // if empty, check for only response certification
        if (metadata_array.size() == 0) {
            buffer.add((IC_CERT_STATUS, #Nat(Nat16.toNat(endpoint_record.status))));
            let no_request_certification_hash = Blob.fromArray(RepIndyHash.hash_val(#Map(Buffer.toArray(buffer))));

            switch (Map.get(nested_map, bhash, no_request_certification_hash)) {
                case (?vec) {
                    metadata_array := Array.append(Vector.toArray(vec), metadata_array);
                };
                case (null) {};
            };
        };

        // if empty, check for full certification
        if (metadata_array.size() == 0) {
            buffer.add((IC_CERT_METHOD, #Text(endpoint_record.method)));
            let unique_http_hash = Blob.fromArray(RepIndyHash.hash_val(#Map(Buffer.toArray(buffer))));

            switch (Map.get(nested_map, bhash, unique_http_hash)) {
                case (?vec) {
                    metadata_array := Array.append(Vector.toArray(vec), metadata_array);
                };
                case (null) {};
            };
        };

        func array_contains_all<A>(haystack : [A], needles : [A], eq : (A, A) -> Bool) : Bool {
            var contains_all = true;

            label loop1 for (x in needles.vals()) {
                var found_match = false;

                label loop2 for (y in haystack.vals()) {
                    if (eq(x, y)) {
                        found_match := true;
                        break loop2;
                    };
                };

                contains_all := contains_all and found_match;

                if (not contains_all) return false;
            };

            contains_all;
        };

        // Debug.print("endpoint query_params: " # debug_show (endpoint_record.query_params));
        // Debug.print("endpoint response_headers: " # debug_show (endpoint_record.response_headers));
        // Debug.print("endpoint request_headers: " # debug_show (endpoint_record.request_headers));

        // Debug.print("metadata_array: " # debug_show (metadata_array));

        for (metadata in metadata_array.vals()) {
            var check = true;

            func equal_tuples(a : (Text, Text), b : (Text, Text)) : Bool {
                a.0 == b.0 and a.1 == b.1
            };

            check := check and array_contains_all(endpoint_record.request_headers, metadata.endpoint.request_headers, equal_tuples);
            check := check and array_contains_all(endpoint_record.response_headers, metadata.endpoint.response_headers, equal_tuples);
            check := check and array_contains_all(endpoint_record.query_params, metadata.endpoint.query_params, equal_tuples);

            if (check) return ?metadata;
        };

        return null;
    };

    func base64(data : Blob) : Text {
        let res = Base64.StdEncoding.encode(Blob.toArray(data));
        let ?utf8 = Text.decodeUtf8(Blob.fromArray(res)) else Debug.trap("base64 encoding failed");
        utf8;
    };

    module MerkleTreeOps {
        type Path = MerkleTree.Path;
        type Value = MerkleTree.Value;
        type Key = MerkleTree.Key;
        type Hash = MerkleTree.Hash;
        type Witness = MerkleTree.Witness;

        public func put(ct : StableStore, ks : Path, v : Value) {
            ct.tree := MerkleTree.put(ct.tree, ks, v);
        };

        public func delete(ct : StableStore, ks : Path) {
            ct.tree := MerkleTree.delete(ct.tree, ks);
        };

        public func lookup(ct : StableStore, ks : Path) : ?Value {
            MerkleTree.lookup(ct.tree, ks);
        };

        public func labelsAt(ct : StableStore, ks : Path) : Iter.Iter<Key> {
            MerkleTree.labelsAt(ct.tree, ks);
        };

        public func treeHash(ct : StableStore) : Hash {
            MerkleTree.treeHash(ct.tree);
        };

        public func setCertifiedData(ct : StableStore) {
            CertifiedData.set(MerkleTreeOps.treeHash(ct));
        };

        public func reveal(ct : StableStore, path : Path) : Witness {
            MerkleTree.reveal(ct.tree, path);
        };

        public func reveals(ct : StableStore, paths : Iter.Iter<Path>) : Witness {
            MerkleTree.reveals(ct.tree, paths);
        };

        public func encodeWitness(w : Witness) : Blob {
            MerkleTree.encodeWitness(w);
        };
    };

};
