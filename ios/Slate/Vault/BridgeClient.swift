import Foundation

/// Talks to notes/bridge.py on the Mac (same LAN) — the same JSON the web app sends.
struct BridgeClient {
    let base: URL

    init?(_ string: String) {
        guard let u = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
              u.scheme == "http" || u.scheme == "https", u.host != nil else { return nil }
        base = u
    }

    struct Info: Decodable { let vault: String; let write_dir: String; let reindex: Bool? }

    func info() async throws -> Info {
        var req = URLRequest(url: base.appendingPathComponent("api/info"))
        req.timeoutInterval = 4
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(Info.self, from: data)
    }

    func send(_ entry: Entry, settings: Settings) async throws -> Entry.Sent {
        let now = Date()
        let cap = entry.capture(via: settings.via, at: now)
        var payload: [String: Any] = [
            "title": entry.displayTitle, "body": entry.body,
            "tags": cap.tags, "sources": cap.sources,
            "captured_via": settings.via, "captured_at": MemexMarkdown.localISO(now),
            "kind": entry.isDaily ? "daily" : "note",
            "reindex": settings.reindex,
        ]
        if entry.isDaily { payload["day"] = entry.day } else { payload["name"] = MemexMarkdown.filename(cap, style: settings.naming) }
        if let s = entry.sent, s.via == "bridge" { payload["path"] = s.path }

        var req = URLRequest(url: base.appendingPathComponent("api/capture"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, obj["ok"] as? Bool == true, let path = obj["path"] as? String else {
            throw VaultError.bridge(obj["error"] as? String ?? "bridge returned \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return Entry.Sent(via: "bridge", path: path, name: (path as NSString).lastPathComponent, at: now)
    }
}
