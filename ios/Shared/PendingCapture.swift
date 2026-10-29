// The share extension cannot reach the vault folder the app was granted, so it drops a
// capture here (app-group container) and the app files it the next time it is in front.
import Foundation

public struct PendingCapture: Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(title: String, url: String, text: String) {
        id = UUID(); self.title = title; self.url = url; self.text = text; createdAt = Date()
    }

    /// Same shape as the docs' bookmarklet: selected text as a quote block, then the URL.
    public var body: String {
        var s = ""
        if !text.isEmpty { s += "> " + text.replacingOccurrences(of: "\n", with: "\n> ") + "\n\n" }
        if !url.isEmpty { s += url + "\n" }
        return s
    }
}

public enum AppGroup {
    public static let id = "group.xyz.memexlab.slate"

    public static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
    public static var pendingDir: URL? {
        container?.appendingPathComponent("pending", isDirectory: true)
    }

    public static func enqueue(_ p: PendingCapture) throws {
        guard let dir = pendingDir else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(p).write(to: dir.appendingPathComponent(p.id.uuidString + ".json"), options: .atomic)
    }

    /// Reads every queued capture, oldest first, and removes the files.
    public static func drain() -> [PendingCapture] {
        guard let dir = pendingDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        var out: [PendingCapture] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f), let p = try? dec.decode(PendingCapture.self, from: data) { out.append(p) }
            try? FileManager.default.removeItem(at: f)
        }
        return out.sorted { $0.createdAt < $1.createdAt }
    }
}
