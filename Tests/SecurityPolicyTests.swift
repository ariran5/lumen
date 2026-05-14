import XCTest
@testable import Lumen

/// Block 4 — HTTPS-only gate в BundleLoader.
/// `SecurityPolicy.denyReason` решает можно ли вообще пробовать грузить
/// fast-app с этого URL. Тесты покрывают: ok / deny / local exceptions /
/// Developer Mode override.
final class SecurityPolicyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SecurityPolicy.isDeveloperMode = false
    }

    override func tearDown() {
        SecurityPolicy.isDeveloperMode = false
        super.tearDown()
    }

    // MARK: - HTTPS / lumen — always ok

    func testHTTPSIsAllowed() {
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "https://app.example.com")!))
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "https://app.example.com/sub/path")!))
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "https://app.example.com:8443")!))
    }

    func testLumenSchemeIsAllowed() {
        // lumen://history и др. — system fast-apps
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "lumen://history")!))
    }

    // MARK: - HTTP — denied by default

    func testHTTPOnPublicHostIsDenied() {
        XCTAssertNotNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://example.com")!))
        XCTAssertNotNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://untrusted.io/path")!))
    }

    // MARK: - Local dev exceptions

    func testLocalhostIsAllowedOverHTTP() {
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://localhost:8080")!))
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://localhost")!))
    }

    func testLoopbackIPv4IsAllowed() {
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://127.0.0.1:3000")!))
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://127.5.5.5")!))
    }

    func testDotLocalIsAllowed() {
        // mDNS/Bonjour — Macbook на той же сети часто доступен как
        // `macbook.local`.
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://my-mac.local:8080")!))
    }

    func testRFC1918PrivateRangesAreAllowed() {
        // Типичный сценарий: iPhone в той же wifi грузит с ноута
        // 192.168.0.107:8089
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://192.168.0.107:8089")!))
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://10.0.0.42")!))
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://172.20.0.1")!))
    }

    func testPublicLookalikesAreStillDenied() {
        // 8.8.8.8, 172.15.x.x (не в 172.16-31), 172.32.x.x — публичные.
        XCTAssertNotNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://8.8.8.8")!))
        XCTAssertNotNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://172.15.0.1")!))
        XCTAssertNotNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://172.32.0.1")!))
        // 169.254.x.x — link-local, не RFC1918; пока не разрешаем.
        XCTAssertNotNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://169.254.1.1")!))
    }

    // MARK: - Developer Mode

    func testDeveloperModeOverridesAllChecks() {
        XCTAssertNotNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://example.com")!))
        SecurityPolicy.isDeveloperMode = true
        XCTAssertNil(SecurityPolicy.denyReason(forBundleURL: URL(string: "http://example.com")!),
                     "Developer Mode allows any http URL")
        SecurityPolicy.isDeveloperMode = false
    }
}
