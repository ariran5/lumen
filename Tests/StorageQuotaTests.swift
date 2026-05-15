import XCTest
@testable import Lumen

/// Block 5 — per-origin storage quota tracking + enforcement in `lumen.storage`.
/// Covered: quota parser, usage tracking, denyReason logic.
final class StorageQuotaTests: XCTestCase {

    private let testOrigin = Origin(scheme: "https", host: "quota.test.example")

    private var prefix: String { "lumen.storage.\(testOrigin.shortHash)." }

    override func setUp() {
        super.setUp()
        wipePrefix(prefix)
    }
    override func tearDown() {
        wipePrefix(prefix)
        super.tearDown()
    }

    private func wipePrefix(_ p: String) {
        for k in UserDefaults.standard.dictionaryRepresentation().keys
            where k.hasPrefix(p) {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    // MARK: - Parser

    func testParseAcceptsCommonSuffixes() {
        XCTAssertEqual(StorageQuota.parse("100MB"), 100 * 1024 * 1024)
        XCTAssertEqual(StorageQuota.parse("1GB"), 1024 * 1024 * 1024)
        XCTAssertEqual(StorageQuota.parse("512KB"), 512 * 1024)
        XCTAssertEqual(StorageQuota.parse("256B"), 256)
        // case insensitive + whitespace
        XCTAssertEqual(StorageQuota.parse("  100 mb"), 100 * 1024 * 1024)
        XCTAssertEqual(StorageQuota.parse("2gb"), 1 * 1024 * 1024 * 1024,
                       "2GB capped to hardMax = 1GB")
    }

    func testParseAcceptsRawBytes() {
        XCTAssertEqual(StorageQuota.parse("1024"), 1024)
        XCTAssertEqual(StorageQuota.parse("0"), 0)
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(StorageQuota.parse(nil))
        XCTAssertNil(StorageQuota.parse(""))
        XCTAssertNil(StorageQuota.parse("hello"))
        XCTAssertNil(StorageQuota.parse("100XYZ"))
        XCTAssertNil(StorageQuota.parse("-100MB"))
    }

    func testParseCapsToHardMax() {
        XCTAssertEqual(StorageQuota.parse("100GB"), StorageQuota.hardMaxBytes,
                       "ridiculous values get capped at hardMax")
        XCTAssertEqual(StorageQuota.parse("999999999999"), StorageQuota.hardMaxBytes)
    }

    // MARK: - Usage tracking

    func testUsageStartsAtZeroForFreshOrigin() {
        XCTAssertEqual(StorageQuota.currentUsage(prefix: prefix), 0)
    }

    func testUsageSumsKeyAndValueBytes() {
        let key = prefix + "k"          // 1 byte after prefix
        let value = "hello"             // 5 bytes
        UserDefaults.standard.set(value, forKey: key)
        let expected = key.utf8.count + value.utf8.count
        XCTAssertEqual(StorageQuota.currentUsage(prefix: prefix), expected)
    }

    func testUsageSumsAcrossMultipleEntries() {
        UserDefaults.standard.set("a", forKey: prefix + "k1")
        UserDefaults.standard.set("bb", forKey: prefix + "k2")
        UserDefaults.standard.set("ccc", forKey: prefix + "k3")

        let expected =
            (prefix + "k1").utf8.count + 1 +
            (prefix + "k2").utf8.count + 2 +
            (prefix + "k3").utf8.count + 3
        XCTAssertEqual(StorageQuota.currentUsage(prefix: prefix), expected)
    }

    func testUsageDoesNotLeakAcrossPrefixes() {
        UserDefaults.standard.set("evil", forKey: "other.prefix.k")
        defer { UserDefaults.standard.removeObject(forKey: "other.prefix.k") }
        XCTAssertEqual(StorageQuota.currentUsage(prefix: prefix), 0,
                       "currentUsage filters strictly by prefix")
    }

    // MARK: - denyReason

    func testDenyReasonAllowsWithinLimit() {
        let key = prefix + "k"
        let value = "value"
        XCTAssertNil(StorageQuota.denyReason(prefix: prefix,
                                             keyWithPrefix: key,
                                             newValue: value,
                                             limit: 1024))
    }

    func testDenyReasonRejectsWhenOverLimit() {
        let key = prefix + "k"
        let bigValue = String(repeating: "x", count: 2000)
        XCTAssertNotNil(StorageQuota.denyReason(prefix: prefix,
                                                 keyWithPrefix: key,
                                                 newValue: bigValue,
                                                 limit: 1024))
    }

    func testDenyReasonAccountsForOverwritingExistingKey() {
        let key = prefix + "k"
        // Already 100 bytes used (under tiny limit)
        UserDefaults.standard.set(String(repeating: "y", count: 100), forKey: key)

        // Writing the same key with value 90 — frees 10 + key bytes
        // and adds the new value: must fit.
        XCTAssertNil(StorageQuota.denyReason(prefix: prefix,
                                              keyWithPrefix: key,
                                              newValue: String(repeating: "z", count: 90),
                                              limit: 200),
                     "overwrite must not double-count the old record")
    }

    func testDenyReasonOverflowOnNewKeyEvenIfOldKeyExists() {
        let oldKey = prefix + "old"
        let newKey = prefix + "new"
        UserDefaults.standard.set(String(repeating: "y", count: 100), forKey: oldKey)

        let bigValue = String(repeating: "z", count: 200)
        XCTAssertNotNil(StorageQuota.denyReason(prefix: prefix,
                                                 keyWithPrefix: newKey,
                                                 newValue: bigValue,
                                                 limit: 200),
                       "new key — old is not freed, limit exceeded")
    }
}
