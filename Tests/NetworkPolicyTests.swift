import XCTest
@testable import Lumen

final class NetworkPolicyTests: XCTestCase {

    // MARK: own-host default-allow

    func test_allowsOwnHostExact() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: nil)
        XCTAssertTrue(policy.allows(url: URL(string: "https://acme.com/api")!))
    }

    func test_allowsOwnHostSubdomain() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: nil)
        XCTAssertTrue(policy.allows(url: URL(string: "https://api.acme.com/v1")!))
        XCTAssertTrue(policy.allows(url: URL(string: "https://stream.cdn.acme.com/socket")!))
    }

    func test_allowsOwnHostAnyPort() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: nil)
        XCTAssertTrue(policy.allows(url: URL(string: "https://acme.com:8443/api")!))
    }

    func test_allowsOwnHostAcrossSchemes() {
        // wss/ws/http to own host — allowed (for WS upgrade from the same origin).
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: nil)
        XCTAssertTrue(policy.allows(url: URL(string: "wss://acme.com/ws")!))
        XCTAssertTrue(policy.allows(url: URL(string: "ws://acme.com/ws")!))
    }

    // MARK: cross-origin denied by default

    func test_blocksCrossOriginByDefault() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: nil)
        XCTAssertFalse(policy.allows(url: URL(string: "https://evil.com/")!))
        XCTAssertFalse(policy.allows(url: URL(string: "https://acmexevil.com/")!))  // suffix collision
    }

    func test_doesNotAllowReverseSubdomain() {
        // App `https://api.acme.com` must NOT have access to `acme.com`.
        let origin = Origin(scheme: "https", host: "api.acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: nil)
        XCTAssertFalse(policy.allows(url: URL(string: "https://acme.com/")!))
    }

    // MARK: manifest connect entries

    func test_manifestExactHost() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: ["api.partner.com"])
        XCTAssertTrue(policy.allows(url: URL(string: "https://api.partner.com/x")!))
        // Exact means no subdomains — sub.api.partner.com is not allowed.
        XCTAssertFalse(policy.allows(url: URL(string: "https://sub.api.partner.com/")!))
    }

    func test_manifestSubdomainWildcard() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: ["*.cdn.io"])
        XCTAssertTrue(policy.allows(url: URL(string: "https://a.cdn.io/x")!))
        XCTAssertTrue(policy.allows(url: URL(string: "https://deep.a.cdn.io/x")!))
        // Bare cdn.io does NOT match — needs a separate entry, as in CSP.
        XCTAssertFalse(policy.allows(url: URL(string: "https://cdn.io/x")!))
        XCTAssertFalse(policy.allows(url: URL(string: "https://evilcdn.io/x")!))
    }

    func test_manifestAllowAll() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: ["*"])
        XCTAssertTrue(policy.allowAll)
        XCTAssertTrue(policy.allows(url: URL(string: "https://random.example.org/")!))
    }

    // MARK: scheme guard

    func test_blocksNonNetworkSchemes() {
        let origin = Origin(scheme: "https", host: "acme.com")
        let policy = NetworkPolicy(origin: origin, manifestConnect: ["*"])
        XCTAssertFalse(policy.allows(url: URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(policy.allows(url: URL(string: "data:text/plain;base64,QQ==")!))
    }

    // MARK: lumen scheme — system origin allow-all

    func test_lumenOriginAllowsAll() {
        let origin = Origin(scheme: "lumen", host: "home")
        let policy = NetworkPolicy(origin: origin, manifestConnect: nil)
        XCTAssertTrue(policy.allows(url: URL(string: "https://anywhere.com/x")!))
    }
}
