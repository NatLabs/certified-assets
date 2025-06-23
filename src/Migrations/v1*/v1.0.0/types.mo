import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Nat16 "mo:base/Nat16";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Int "mo:base/Int";

import MerkleTree "mo:ic-certification/MerkleTree";
import CertifiedData "mo:base/CertifiedData";
import SHA256 "mo:sha2/Sha256";
import HttpParser "mo:http-parser";
import HttpTypes "mo:http-types";
import Serde "mo:serde";
import Map "mo:map/Map";
import Vector "mo:vector";
import Itertools "mo:itertools/Iter";
import RevIter "mo:itertools/RevIter";

module T {
    public type Buffer<A> = Buffer.Buffer<A>;
    public type Iter<A> = Iter.Iter<A>;
    public type Map<K, V> = Map.Map<K, V>;
    public type Result<T, E> = Result.Result<T, E>;
    public type Vector<A> = Vector.Vector<A>;

    public let { thash; bhash } = Map;

    /// An immutable record that contains all the information needed to certify a given endpoint.
    public type EndpointRecord = {
        url : Text;
        hash : Blob;
        method : Text;
        query_params : [(Text, Text)];
        request_headers : [HttpTypes.Header];
        status : Nat16;
        response_headers : [HttpTypes.Header];
        no_certification : Bool;
        no_request_certification : Bool;
        is_fallback_path : Bool;
    };

    public type Metadata = {
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

    public type HttpRequest = HttpTypes.Request;
    public type HttpResponse = HttpTypes.Response;
    public type Header = HttpTypes.Header;

    public type CertifiedTree = {
        certificate : Blob;
        tree : Blob;
    };

    public type Settings = {
        unit_test_mode : ?Bool;
    };

    public type InternalSettings = {
        unit_test_mode : Bool;
    };

    public type StableStore = {
        var tree : MerkleTree.Tree;
        metadata_map : MetadataMap;
        settings : InternalSettings;
    };

};
