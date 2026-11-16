import CryptoKit
import Foundation
import Security

/// **What this Mac remembers of the others**: the Macs it lends itself to, the Macs it may borrow, and
/// its own `id` (the TXT of its session service, how a borrower recognises it on Bonjour whatever its
/// name becomes). A pairing outlives the session, as an accepted license does — incognito is about the
/// images, not about which Macs may talk.
///
/// **One Keychain item for all**, a generic password holding this JSON. The item's access list binds
/// the code signature that created it, and a build signed ad hoc gets a new signature every time:
/// at load, the item of a foreign signature is deleted (`forgetUnreadable`) and the first save
/// writes a fresh one — a build reads without a prompt for its whole life, at the price of the
/// pairings, which a new build forgets. A Developer ID build keeps its signature across updates
/// and is never asked, never forgotten.
///
/// Two instances with different `SILICONED_ROOT` are two Macs (the test of two apps on one machine):
/// the item's account carries the root then.
package struct Pairings: Codable, Equatable, Sendable {
    /// A Mac this one lends itself to, as the user accepted it.
    package struct Lent: Codable, Equatable, Sendable {
        package var name: String
        package var identity: Data
        package var key: Data
    }

    /// A Mac this one may compute on.
    package struct Borrowed: Codable, Equatable, Sendable {
        /// Its `id` on Bonjour.
        package var id: String
        package var name: String
        package var identity: Data
        package var key: Data
    }

    package var id: String
    package var lent: [Lent] = []
    package var borrowed: [Borrowed] = []

    package init(id: String = Pairings.newID()) { self.id = id }

    package static func newID() -> String {
        Pairing.random(8).map { String(format: "%02x", $0) }.joined()
    }

    package var lendingKeys: [PairedKey] {
        lent.map { PairedKey(identity: $0.identity, key: SymmetricKey(data: $0.key)) }
    }

    package mutating func lend(to name: String, _ k: PairedKey) {
        lent.removeAll { $0.identity == k.identity }
        lent.append(Lent(name: name, identity: k.identity, key: k.key.withUnsafeBytes { Data($0) }))
    }

    /// A new pairing with the same Mac replaces the old one: one key per Mac.
    package mutating func borrow(from id: String, name: String, _ k: PairedKey) {
        borrowed.removeAll { $0.id == id }
        borrowed.append(Borrowed(id: id, name: name, identity: k.identity, key: k.key.withUnsafeBytes { Data($0) }))
    }

    package func key(of b: Borrowed) -> PairedKey {
        PairedKey(identity: b.identity, key: SymmetricKey(data: b.key))
    }
}

// MARK: - The Keychain

extension Pairings {
    static let service = "dev.gwenn-ha.siliconed.pairings"

    package static func account(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let root = environment["SILICONED_ROOT"], !root.isEmpty { return "pairings " + root }
        return "pairings"
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// What the Keychain holds, or a new identity if nothing; `nil` if it could not be read (the user
    /// denied access): then nothing is written over it.
    package static func load(account: String = account()) -> Pairings? {
        forgetUnreadable(account: account)
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        switch SecItemCopyMatching(q as CFDictionary, &out) {
        case errSecSuccess:
            guard let d = out as? Data else { return nil }
            return try? JSONDecoder().decode(Pairings.self, from: d)
        case errSecItemNotFound:
            return Pairings()
        default:
            return nil
        }
    }

    /// **A build cannot quietly read what its predecessor wrote.** The item's access list binds the
    /// code signature that created it — and an ad hoc build signs anew every time, so a new build
    /// would be asked at every launch (« always allow » cannot stick to a signature that changes).
    /// Before reading, the item of a foreign signature goes: matching by attribute alone, the
    /// keychain asks nothing to delete — the first save writes a fresh one this build owns, and it
    /// reads without a prompt until the next build. The mark of the last signature lives beside, in
    /// Application Support. Only the app does this (the tests run unsigned); a Developer ID build
    /// keeps its signature, its mark matches, and nothing is ever deleted.
    private static func forgetUnreadable(account: String) {
        guard Bundle.main.bundleURL.pathExtension == "app", let now = ownSignature else { return }
        guard (try? String(contentsOf: markURL, encoding: .utf8)) != now else { return }
        SecItemDelete(query(account) as CFDictionary)
        try? now.write(to: markURL, atomically: true, encoding: .utf8)
    }

    /// Where the last signature is remembered.
    private static var markURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Siliconed", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("pairings-signature")
    }

    /// This build's cdhash — what the item's access list binds to.
    private static var ownSignature: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var static_: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &static_) == errSecSuccess, let staticCode = static_ else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any], let u = d[kSecCodeInfoUnique as String] as? Data else { return nil }
        return u.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    package func save(account: String = Pairings.account()) -> Bool {
        guard let d = try? JSONEncoder().encode(self) else { return false }
        let q = Pairings.query(account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: d] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = d
            add[kSecAttrLabel as String] = "Siliconed — paired Macs"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
