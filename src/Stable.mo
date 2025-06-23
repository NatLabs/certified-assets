import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat16 "mo:base/Nat16";
import Result "mo:base/Result";
import Text "mo:base/Text";

import MerkleTree "mo:ic-certification/MerkleTree";
import CertifiedData "mo:base/CertifiedData";
import SHA256 "mo:sha2/Sha256";
import HttpParser "mo:http-parser";
import HttpTypes "mo:http-types";
import Serde "mo:serde";
import Map "mo:map/Map";
import RepIndyHash "mo:rep-indy-hash";
import Vector "mo:vector";
import Itertools "mo:itertools/Iter";
import RevIter "mo:itertools/RevIter";

import Base64 "mo:encoding/Base64";

import Utils "Utils";
import EndpointModule "Endpoint";
import Base "Base";
import Migrations "Migrations";

module Module {

    type Buffer<A> = Buffer.Buffer<A>;
    type Iter<A> = Iter.Iter<A>;
    type Map<K, V> = Map.Map<K, V>;
    type Result<T, E> = Result.Result<T, E>;
    type Vector<A> = Vector.Vector<A>;

    let { thash; bhash } = Map;
    let { CBOR } = Serde;

    type Metadata = {
        endpoint : EndpointRecord;
        encoded_expr_path : Blob;
        full_expr_path : [Blob];
        ic_certificate_expression : Text;
    };

    public type EndpointsMap = Map<Blob, Vector<Metadata>>;

    public type SplitMetadataEndpoints = {
        fallback_endpoints : EndpointsMap;
        endpoints : EndpointsMap;
    };

    public type MetadataMap = Map<Text, SplitMetadataEndpoints>;

    public type VersionedStableStore = Migrations.VersionedStableStore;
    type StableStore = Base.StableStore;

    public let Endpoint = EndpointModule.Endpoint;
    public type Endpoint = EndpointModule.Endpoint;
    public type EndpointRecord = EndpointModule.EndpointRecord;

    public type HttpRequest = HttpTypes.Request;
    public type HttpResponse = HttpTypes.Response;
    public type Header = HttpTypes.Header;

    public type CertifiedTree = {
        certificate : Blob;
        tree : Blob;
    };

    public let IC_CERTIFICATE_EXPRESSION = "ic-certificateexpression";
    public let IC_CERT_BODY = ":ic-cert-body";
    public let IC_CERT_METHOD = ":ic-cert-method";
    public let IC_CERT_QUERY = ":ic-cert-query";
    public let IC_CERT_STATUS = ":ic-cert-status";
    public let IC_IS_FALLBACK = ":ic-is-fallback";

    public type CertifiedAssetErrors = {
        #GetCertifiedDataFailed : Text;
        #NoMatchingEndpointFound : Text;
    };

    public func init_stable_store() : VersionedStableStore {
        Migrations.share_version(Base.init_stable_store());
    };

    public func upgrade(ct : VersionedStableStore) : VersionedStableStore {
        Migrations.upgrade(ct);
    };

    public func certify(ct : VersionedStableStore, endpoint : Endpoint) {
        Base.certify(Migrations.get_current_state(ct), endpoint);
    };

    public func encode_text_expr_path(text_expr_path : [Text]) : Blob {
        Base.encode_text_expr_path(text_expr_path);
    };

    public func get_text_expr_path(url : Text, is_fallback : Bool) : [Text] {
        Base.get_text_expr_path(url, is_fallback);
    };

    public func url_to_encoded_expr_path(url : Text, is_fallback : Bool) : ([Blob], Blob) {
        Base.url_to_encoded_expr_path(url, is_fallback);
    };

    public func get_ic_certificate_expression(
        no_certification : Bool,
        no_request_certification : Bool,
        query_params : [(Text, Text)],
        request_headers : [HttpTypes.Header],
        response_headers : [HttpTypes.Header],
    ) : Text {
        Base.get_ic_certificate_expression(
            no_certification,
            no_request_certification,
            query_params,
            request_headers,
            response_headers,
        );
    };

    public func get_request_hash(
        no_certification : Bool,
        no_request_certification : Bool,
        method : Text,
        query_params : [(Text, Text)],
        request_headers : [HttpTypes.Header],
    ) : Blob {
        Base.get_request_hash(
            no_certification,
            no_request_certification,
            method,
            query_params,
            request_headers,
        );
    };

    public func get_response_hash(
        no_certification : Bool,
        status : Nat16,
        body_hash : Blob,
        response_headers : [HttpTypes.Header],
        ic_certificate_expression : Text,
    ) : Blob {
        Base.get_response_hash(
            no_certification,
            status,
            body_hash,
            response_headers,
            ic_certificate_expression,
        );
    };

    public func certify_record(ct : VersionedStableStore, endpoint_record : EndpointRecord) {
        Base.certify_record(Migrations.get_current_state(ct), endpoint_record);
    };

    /// Remove a certified EndpointModule.
    public func remove(ct : VersionedStableStore, endpoint : Endpoint) {
        Base.remove(Migrations.get_current_state(ct), endpoint);
    };

    public func remove_record(ct : VersionedStableStore, endpoint_record : EndpointRecord) {
        Base.remove_record(Migrations.get_current_state(ct), endpoint_record);
    };

    /// Removes all the certified endpoints that match the given URL.
    public func remove_all(ct : VersionedStableStore, url : Text) {
        Base.remove_all(Migrations.get_current_state(ct), url);
    };

    public func endpoints(ct : VersionedStableStore) : Iter<EndpointRecord> {
        Base.endpoints(Migrations.get_current_state(ct));
    };

    public func endpoints_by_url(ct : VersionedStableStore, url : Text) : Iter<EndpointRecord> {
        Base.endpoints_by_url(Migrations.get_current_state(ct), url);
    };

    /// Clear all certified endpoints.
    public func clear(ct : VersionedStableStore) {
        Base.clear(Migrations.get_current_state(ct));
    };

    /// Modifies a given response by adding the certificate headers.
    public func get_certified_response(ct : VersionedStableStore, req : HttpTypes.Request, res : HttpTypes.Response, opt_response_hash : ?Blob) : Result<HttpTypes.Response, Text> {
        Base.get_certified_response(Migrations.get_current_state(ct), req, res, opt_response_hash);
    };

    /// Get the certificate headers for a given request.
    public func get_certificate(ct : VersionedStableStore, req : HttpTypes.Request, res : HttpTypes.Response, opt_response_hash : ?Blob) : Result<[HttpTypes.Header], Text> {
        Base.get_certificate(Migrations.get_current_state(ct), req, res, opt_response_hash);
    };

    /// Gets the closest fallback path for the given path that has a certificate associated with it.
    public func get_fallback_path(ct : VersionedStableStore, path : Text) : ?Text {
        Base.get_fallback_path(Migrations.get_current_state(ct), path);
    };

    public func get_all_fallback_paths_between_urls(init_start_path : Text, init_end_path : Text) : [Text] {
        Base.get_all_fallback_paths_between_urls(init_start_path, init_end_path);
    };

    public func get_fallback_certificate(ct : VersionedStableStore, req : HttpTypes.Request, fallback_path : Text, res : HttpTypes.Response, opt_response_hash : ?Blob) : Result<[HttpTypes.Header], Text> {
        Base.get_fallback_certificate(Migrations.get_current_state(ct), req, fallback_path, res, opt_response_hash);
    };

    public func get_fallback_response(ct : VersionedStableStore, req : HttpTypes.Request, fallback_path : Text, res : HttpTypes.Response, opt_response_hash : ?Blob) : Result<HttpTypes.Response, Text> {
        Base.get_fallback_response(Migrations.get_current_state(ct), req, fallback_path, res, opt_response_hash);
    };

    /// Retrieves the certificate tree based on the given keys.
    /// If keys are set to `null`, the entire tree is returned.
    public func get_certified_tree(ct : VersionedStableStore, keys : ?[Text]) : Result<CertifiedTree, Text> {
        Base.get_certified_tree(Migrations.get_current_state(ct), keys);
    };

    public func http_req_res_to_endpoint(req : HttpTypes.Request, res : HttpTypes.Response, opt_response_hash : ?Blob) : Endpoint {
        Base.http_req_res_to_endpoint(req, res, opt_response_hash);
    };

    public func get_metadata(ct : VersionedStableStore, req : HttpTypes.Request, res : HttpTypes.Response, opt_response_hash : ?Blob) : ?Metadata {
        Base.get_metadata(Migrations.get_current_state(ct), req, res, opt_response_hash);
    };

    public func get_metadata_from_endpoint(ct : VersionedStableStore, endpoint_record : EndpointRecord) : ?Metadata {
        Base.get_metadata_from_endpoint(Migrations.get_current_state(ct), endpoint_record);
    };

    public type GetMetadataResponse = Base.GetMetadataResponse;

    public func get_metadata_index_from_endpoint(ct : VersionedStableStore, endpoint_record : EndpointRecord) : ?GetMetadataResponse {
        Base.get_metadata_index_from_endpoint(Migrations.get_current_state(ct), endpoint_record);
    };

    public func get_metadata_index_from_vector(endpoint_record : EndpointRecord, metadata_array : Vector<Metadata>) : ?(Vector<Metadata>, Nat) {
        Base.get_metadata_index_from_vector(endpoint_record, metadata_array);
    };

};
