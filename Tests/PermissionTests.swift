import XCTest
@testable import Lumen

/// Покрывают PermissionStore (sticky decisions, per-origin isolation, revoke,
/// clear). Prompt UI не тестируется здесь — UIAlertController требует
/// presenting controller и интерактивного tap'а; покрывается вручную/UITests.
@MainActor
final class PermissionTests: XCTestCase {

    private let testOriginA = Origin(scheme: "https", host: "a.example.com")
    private let testOriginB = Origin(scheme: "https", host: "b.example.com")

    override func setUp() {
        super.setUp()
        // Каждый тест на чистом state'е. UserDefaults — process-wide, между
        // тестами может протекать; явный wipe ключей наших origin'ов.
        let store = PermissionStore.shared
        store.clear(origin: testOriginA)
        store.clear(origin: testOriginB)
    }

    override func tearDown() {
        let store = PermissionStore.shared
        store.clear(origin: testOriginA)
        store.clear(origin: testOriginB)
        super.tearDown()
    }

    // MARK: - Status / set roundtrip

    func testFreshOriginStatusIsPrompt() {
        let store = PermissionStore.shared
        for cap in Capability.allCases {
            XCTAssertEqual(store.status(origin: testOriginA, capability: cap), .prompt,
                           "\(cap) on fresh origin = .prompt")
        }
    }

    func testSetGrantedPersistsAcrossStatusCalls() {
        let store = PermissionStore.shared
        store.set(origin: testOriginA, capability: .camera, grant: .granted)
        XCTAssertEqual(store.status(origin: testOriginA, capability: .camera), .granted)

        store.set(origin: testOriginA, capability: .notifications, grant: .denied)
        XCTAssertEqual(store.status(origin: testOriginA, capability: .notifications), .denied)

        // Не пересеклись с другими capabilities.
        XCTAssertEqual(store.status(origin: testOriginA, capability: .microphone), .prompt)
    }

    func testSetPromptRemovesDecision() {
        let store = PermissionStore.shared
        store.set(origin: testOriginA, capability: .camera, grant: .granted)
        XCTAssertEqual(store.status(origin: testOriginA, capability: .camera), .granted)

        store.set(origin: testOriginA, capability: .camera, grant: .prompt)
        XCTAssertEqual(store.status(origin: testOriginA, capability: .camera), .prompt,
                       "writing .prompt erases the decision — next request will ask again")
    }

    // MARK: - Per-origin isolation

    func testGrantOnOneOriginDoesNotLeakToOther() {
        let store = PermissionStore.shared
        store.set(origin: testOriginA, capability: .camera, grant: .granted)

        XCTAssertEqual(store.status(origin: testOriginA, capability: .camera), .granted)
        XCTAssertEqual(store.status(origin: testOriginB, capability: .camera), .prompt,
                       "different origin must NOT see a.example.com's grant")
    }

    func testDifferentSchemesAreDifferentOrigins() {
        // origin identity = scheme+host+port. http://a и https://a — разные.
        let httpA  = Origin(scheme: "http",  host: "a.example.com")
        let httpsA = Origin(scheme: "https", host: "a.example.com")

        let store = PermissionStore.shared
        store.clear(origin: httpA); store.clear(origin: httpsA)
        defer {
            store.clear(origin: httpA); store.clear(origin: httpsA)
        }

        store.set(origin: httpsA, capability: .location, grant: .granted)
        XCTAssertEqual(store.status(origin: httpsA, capability: .location), .granted)
        XCTAssertEqual(store.status(origin: httpA, capability: .location), .prompt,
                       "http и https — разные origin'ы, grant не shared")
    }

    // MARK: - Revoke / clear

    func testRevokeBringsCapabilityBackToPrompt() {
        let store = PermissionStore.shared
        store.set(origin: testOriginA, capability: .camera, grant: .granted)
        store.set(origin: testOriginA, capability: .microphone, grant: .denied)

        store.revoke(origin: testOriginA, capability: .camera)
        XCTAssertEqual(store.status(origin: testOriginA, capability: .camera), .prompt,
                       "revoked → .prompt next time")
        XCTAssertEqual(store.status(origin: testOriginA, capability: .microphone), .denied,
                       "revoke is per-capability, other decisions untouched")
    }

    func testClearWipesAllCapabilitiesForOrigin() {
        let store = PermissionStore.shared
        store.set(origin: testOriginA, capability: .camera, grant: .granted)
        store.set(origin: testOriginA, capability: .microphone, grant: .granted)
        store.set(origin: testOriginA, capability: .photos, grant: .denied)
        store.set(origin: testOriginB, capability: .camera, grant: .granted)

        store.clear(origin: testOriginA)

        for cap in Capability.allCases {
            XCTAssertEqual(store.status(origin: testOriginA, capability: cap), .prompt,
                           "\(cap) on cleared origin = .prompt")
        }
        // Другой origin не задело.
        XCTAssertEqual(store.status(origin: testOriginB, capability: .camera), .granted)
    }

    // MARK: - request() shortcuts when decision exists

    /// request() для decided'ого capability возвращает grant СИНХРОННО без
    /// показа UI. Тест не требует presenting controller'а — мы предзаписали
    /// решение.
    func testRequestReturnsExistingGrantWithoutPrompt() async {
        let store = PermissionStore.shared
        store.set(origin: testOriginA, capability: .camera, grant: .granted)
        let g1 = await store.request(origin: testOriginA, capability: .camera)
        XCTAssertEqual(g1, .granted, "pre-granted → returned without prompt")

        store.set(origin: testOriginA, capability: .microphone, grant: .denied)
        let g2 = await store.request(origin: testOriginA, capability: .microphone)
        XCTAssertEqual(g2, .denied, "pre-denied → returned without prompt")
    }

    // MARK: - Capability parsing

    func testCapabilityRawValueRoundtrip() {
        for cap in Capability.allCases {
            XCTAssertEqual(Capability(rawValue: cap.rawValue), cap,
                           "\(cap) round-trips through rawValue")
        }
        XCTAssertNil(Capability(rawValue: "bogus"))
    }

    func testGrantIsDecided() {
        XCTAssertTrue(Grant.granted.isDecided)
        XCTAssertTrue(Grant.denied.isDecided)
        XCTAssertFalse(Grant.prompt.isDecided)
    }
}
