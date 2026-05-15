import Foundation

/// Per-origin context: shared persistent state of all tabs of a single
/// site. One app in two tabs — one OriginContext. Closing a tab
/// doesn't kill the context as long as at least one engine holds a reference.
///
/// Currently holds namespace prefixes for storage / Keychain / FS. Permission
/// grants, manifest hashes, quota tracking will land here next.
///
/// Obtain via `OriginContextRegistry.shared.context(for: origin)` —
/// deduplicates by Origin so two tabs of the same site share
/// permission decisions and storage space.
@MainActor
final class OriginContext {
    let origin: Origin

    /// Current network policy. Before `applyManifest` — `.initial` (allow only
    /// own host + subdomains). After manifest is applied, expanded by
    /// its `connect` list. Shared between tabs of the same origin via
    /// `OriginContextRegistry` — last loaded manifest wins.
    private(set) var networkPolicy: NetworkPolicy

    /// Capabilities declared by manifest (for future permission UI).
    /// Grants themselves are not stored here — they live in `PermissionStore` (Block 3).
    private(set) var declaredPermissions: [String] = []

    /// Manifest-declared `storage_quota` parsed to bytes. `nil` =
    /// origin uses `StorageQuota.defaultBytes` (100MB). Capped
    /// at `StorageQuota.hardMaxBytes` (1GB) — a manifest can't ask for
    /// more without a separate permission upgrade flow.
    private(set) var storageQuota: Int?

    init(origin: Origin) {
        self.origin = origin
        self.networkPolicy = .initial(for: origin)
    }

    /// Apply a freshly loaded manifest. Last-write-wins for all tabs
    /// of this origin. Call BEFORE eval'ing bundle.script so fetches
    /// from user code already see the correct allowlist.
    func applyManifest(_ manifest: LumenManifest) {
        self.networkPolicy = NetworkPolicy(origin: origin, manifestConnect: manifest.connect)
        self.declaredPermissions = manifest.permissions ?? []
        self.storageQuota = StorageQuota.parse(manifest.storageQuota)
    }

    /// UserDefaults prefix. `lumen.storage.<hash>.<userkey>` — legacy
    /// global keys `lumen.storage.<key>` are no longer visible after migration.
    var storagePrefix: String {
        "lumen.storage.\(origin.shortHash)."
    }

    /// Keychain service identifier. All app entries live under a single
    /// service — `SecItemDelete` by service = wipe the entire secure
    /// state of an app in one call.
    var keychainService: String {
        "com.lumen.secureStorage.\(origin.shortHash)"
    }

    /// Root of the app's FS sandbox under Documents/. Bridges (imagePicker,
    /// documentPicker, ...) place their tmp files inside.
    var documentsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("apps", isDirectory: true)
            .appendingPathComponent(origin.shortHash, isDirectory: true)
    }

    /// Tmp root. Can be wiped entirely on logout / clear-site-data
    /// without losing persistent data.
    var tmpRoot: URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("apps", isDirectory: true)
            .appendingPathComponent(origin.shortHash, isDirectory: true)
    }
}

/// Singleton registry, deduplicates OriginContext by Origin. Two tabs
/// of the same site get the same context — a permission grant in
/// one is visible in the other.
@MainActor
final class OriginContextRegistry {
    static let shared = OriginContextRegistry()

    private var contexts: [Origin: OriginContext] = [:]

    func context(for origin: Origin) -> OriginContext {
        if let existing = contexts[origin] { return existing }
        let fresh = OriginContext(origin: origin)
        contexts[origin] = fresh
        return fresh
    }
}
