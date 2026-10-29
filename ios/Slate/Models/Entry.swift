import Foundation

/// A journal entry kept on the phone until it is sent to the vault.
struct Entry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case note, daily }

    struct Sent: Codable, Hashable {
        var via: String      // "folder" | "bridge"
        var path: String     // vault-relative, e.g. inbox/2026-03-17-11-47-foo.md
        var name: String
        var at: Date
    }

    var id: UUID = UUID()
    var kind: Kind = .note
    var day: String? = nil          // daily notes: YYYY-MM-DD
    var title: String = ""
    var tags: String = ""           // comma separated, as typed
    var sources: String = ""        // comma separated URLs / [[slugs]]
    var body: String = ""
    var created: Date = Date()
    var updated: Date = Date()
    var sent: Sent? = nil
    var audioFile: String? = nil    // file name inside the app's audio folder

    var isDaily: Bool { kind == .daily }
    var isStale: Bool { if let s = sent { return s.at < updated } else { return false } }
    var displayTitle: String { title.isEmpty ? "Untitled" : title }
    var snippet: String {
        let flat = body.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        return flat.isEmpty ? "Empty" : String(flat.prefix(90))
    }

    func capture(via: String, at: Date) -> Capture {
        Capture(title: title, body: body,
                tags: MemexMarkdown.splitList(tags), sources: MemexMarkdown.splitList(sources),
                capturedVia: via, capturedAt: at, day: isDaily ? day : nil, audio: nil)
    }

    static func defaultTitle(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
    }
}
