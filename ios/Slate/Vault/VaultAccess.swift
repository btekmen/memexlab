import Foundation
import Observation

/// The vault folder the user picked in Files, kept as a security-scoped bookmark.
/// Works with the iCloud Drive copy of the vault (the Mac's Desktop/Documents when
/// iCloud sync is on), an Obsidian vault, or a Working Copy checkout.
@Observable
final class VaultAccess {
    private static let key = "vaultBookmark"
    private(set) var name: String = ""
    private(set) var isConnected = false
    private(set) var lastError: String?

    init() { refresh() }

    func set(url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else { throw VaultError.noAccess }
        defer { url.stopAccessingSecurityScopedResource() }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.key)
        refresh()
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        refresh()
    }

    private func resolve() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { throw VaultError.notConnected }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, url.startAccessingSecurityScopedResource() {
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Self.key)
            }
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }

    func refresh() {
        do {
            let url = try resolve()
            name = url.lastPathComponent
            isConnected = true
            lastError = nil
        } catch {
            name = ""; isConnected = false
            lastError = (error as? VaultError) == .notConnected ? nil : error.localizedDescription
        }
    }

    /// Runs `body` with the folder's security scope open.
    func withAccess<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try resolve()
        guard url.startAccessingSecurityScopedResource() else { throw VaultError.noAccess }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }
}

enum VaultError: LocalizedError, Equatable {
    case notConnected, noAccess, escapesVault, bridge(String)
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Choose your vault folder in Settings first."
        case .noAccess: return "iOS refused access to the vault folder — pick it again in Settings."
        case .escapesVault: return "write_dir escapes the vault."
        case .bridge(let m): return m
        }
    }
}
