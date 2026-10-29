// Shared by the app, the share extension and the tests.
// Mirrors notes/notes.js buildMarkdown()/noteFilename() and notes/bridge.py render(),
// so a note captured on the phone is byte-for-byte what the web app or the bridge writes.
import Foundation

public enum NamingStyle: String, Codable, CaseIterable, Identifiable {
    /// Docs convention (docs/05-daily-workflow.md): 2026-03-17-11-47-short-description.md
    case date
    /// memex-cli / memexlab-mcp shape: short-description-20260317T114700Z.md
    case slug
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .date: return "2026-03-17-11-47-short-description.md"
        case .slug: return "short-description-20260317T114700Z.md"
        }
    }
}

/// One thing to write into the vault.
public struct Capture {
    public var title: String
    public var body: String
    public var tags: [String]
    public var sources: [String]
    public var capturedVia: String
    public var capturedAt: Date
    /// Set for a daily note (templates/daily-note.md): the YYYY-MM-DD it belongs to.
    public var day: String?
    /// File name of a kept voice recording, relative to the note.
    public var audio: String?

    public init(title: String, body: String, tags: [String] = [], sources: [String] = [],
                capturedVia: String = "slate-ios", capturedAt: Date = Date(), day: String? = nil, audio: String? = nil) {
        self.title = title; self.body = body; self.tags = tags; self.sources = sources
        self.capturedVia = capturedVia; self.capturedAt = capturedAt; self.day = day; self.audio = audio
    }
}

public enum MemexMarkdown {
    /// Double-quoted YAML scalar via JSON escaping — valid YAML, injection-safe.
    public static func yq(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    /// memexlab-mcp governance._slugify: [^a-z0-9]+ -> "-", trimmed, at most `max` chars.
    public static func slugify(_ title: String, max: Int = 80) -> String {
        var out = ""
        var pendingDash = false
        for u in title.lowercased().unicodeScalars {
            let alnum = (u.value >= 0x61 && u.value <= 0x7a) || (u.value >= 0x30 && u.value <= 0x39)
            if alnum {
                if pendingDash && !out.isEmpty { out += "-" }
                pendingDash = false
                out.unicodeScalars.append(u)
            } else {
                pendingDash = true
            }
        }
        if out.count > max { out = String(out.prefix(max)) }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "note" : out
    }

    /// "a, b\nc" -> ["a", "b", "c"]
    public static func splitList(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func formatter(_ pattern: String, utc: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc ? TimeZone(identifier: "UTC") : .current
        f.dateFormat = pattern
        return f
    }

    /// 2026-03-17T11:47:00+03:00 — the device's local offset, like the web app.
    public static func localISO(_ d: Date, timeZone: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = timeZone
        return f.string(from: d)
    }
    public static func utcStamp(_ d: Date) -> String { formatter("yyyyMMdd'T'HHmmss'Z'", utc: true).string(from: d) }
    public static func dayKey(_ d: Date) -> String { formatter("yyyy-MM-dd", utc: false).string(from: d) }
    public static func hourMinute(_ d: Date) -> String { formatter("HH-mm", utc: false).string(from: d) }

    /// The daily-note body skeleton from docs/06-templates-and-note-types.md.
    public static func dailySkeleton(_ day: String) -> String {
        "# \(day)\n## What I did\n- \n## What I noticed\n- \n## Questions that came up\n- \n"
    }

    /// Frontmatter + body. Inbox notes follow docs/capture-anywhere.md (title / status /
    /// captured_via / source_url) plus captured_at, sources, tags; daily notes follow
    /// templates/daily-note.md (date / type: daily).
    public static func render(_ c: Capture, writeDir: String) -> String {
        var lines = ["---"]
        if let day = c.day {
            lines += ["date: \(day)", "type: daily",
                      "captured_via: \(yq(c.capturedVia))", "updated: \(yq(localISO(c.capturedAt)))"]
        } else {
            lines += ["title: \(yq(c.title.isEmpty ? "Untitled" : c.title))", "status: \(yq(writeDir))",
                      "captured_via: \(yq(c.capturedVia))", "captured_at: \(yq(localISO(c.capturedAt)))"]
            if let url = c.sources.first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }) {
                lines.append("source_url: \(yq(url))")
            }
            if c.sources.isEmpty {
                lines.append("sources: []")
            } else {
                lines.append("sources:")
                lines += c.sources.map { "- \(yq($0))" }
            }
        }
        if !c.tags.isEmpty { lines.append("tags: [" + c.tags.map(yq).joined(separator: ", ") + "]") }
        if let a = c.audio { lines.append("audio: \(yq(a))") }
        lines += ["---", "", trimTrailing(c.body), ""]
        return lines.joined(separator: "\n")
    }

    public static func filename(_ c: Capture, style: NamingStyle) -> String {
        if let day = c.day { return "\(day).md" }
        let slug = slugify(c.title.isEmpty ? "Untitled" : c.title)
        switch style {
        case .slug:
            return "\(slug)-\(utcStamp(c.capturedAt)).md"
        case .date:
            var short = String(slug.prefix(60))
            while short.hasSuffix("-") { short.removeLast() }
            return "\(dayKey(c.capturedAt))-\(hourMinute(c.capturedAt))-\(short).md"
        }
    }

    /// `write_dir:` from the vault's governance.yml, else "inbox" (same regex as the bridge).
    public static func writeDir(governanceYAML: String?) -> String {
        guard let text = governanceYAML else { return "inbox" }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            guard line.hasPrefix("write_dir:") else { continue }
            var v = String(line.dropFirst("write_dir:".count))
            if let hash = v.firstIndex(of: "#") { v = String(v[..<hash]) }
            v = v.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !v.isEmpty { return v }
        }
        return "inbox"
    }

    static func trimTrailing(_ s: String) -> String {
        var out = s
        while let last = out.last, last.isWhitespace || last.isNewline { out.removeLast() }
        return out
    }
}
