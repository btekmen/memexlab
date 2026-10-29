import Foundation
import Observation

/// Entries live in the app sandbox as one JSON file; audio clips beside it.
@Observable
final class EntryStore {
    private(set) var entries: [Entry] = []
    let directory: URL
    let audioDirectory: URL
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Slate", isDirectory: true)
        audioDirectory = directory.appendingPathComponent("audio", isDirectory: true)
        fileURL = directory.appendingPathComponent("entries.json")
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        load()
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? Self.decoder.decode([Entry].self, from: data) else { return }
        entries = list
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func persist() {
        guard let data = try? Self.encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func entry(id: UUID) -> Entry? { entries.first { $0.id == id } }

    func upsert(_ e: Entry) {
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
        scheduleSave()
    }

    func delete(_ e: Entry) {
        entries.removeAll { $0.id == e.id }
        if let a = e.audioFile { try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(a)) }
        scheduleSave()
    }

    func deleteAll() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: audioDirectory)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        persist()
    }

    @discardableResult
    func newEntry(title: String? = nil, body: String = "", sources: String = "", defaultTags: String = "") -> Entry {
        let now = Date()
        let e = Entry(title: title ?? Entry.defaultTitle(now), tags: defaultTags, sources: sources, body: body, created: now, updated: now)
        upsert(e)
        return e
    }

    /// One daily entry per calendar day; created from the template on first use.
    @discardableResult
    func daily(for date: Date = Date()) -> Entry {
        let key = MemexMarkdown.dayKey(date)
        if let e = entries.first(where: { $0.isDaily && $0.day == key }) { return e }
        let now = Date()
        let e = Entry(kind: .daily, day: key, title: key, body: MemexMarkdown.dailySkeleton(key), created: now, updated: now)
        upsert(e)
        return e
    }

    /// Files captures the share extension or a slate:// URL queued.
    @discardableResult
    func importPending(defaultTags: String) -> [Entry] {
        AppGroup.drain().map { p in
            let title = p.title.isEmpty ? (p.url.isEmpty ? Entry.defaultTitle(p.createdAt) : p.url) : p.title
            let e = Entry(title: title, tags: defaultTags, sources: p.url, body: p.body, created: p.createdAt, updated: p.createdAt)
            upsert(e)
            return e
        }
    }

    var unsent: [Entry] { entries.filter { $0.sent == nil || $0.isStale }.sorted { $0.created < $1.created } }

    /// Everything, as JSON, for the share sheet (Slate-style export).
    func exportJSON() throws -> URL {
        persist()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slate-export-\(MemexMarkdown.utcStamp(Date())).json")
        let notes = try JSONSerialization.jsonObject(with: Self.encoder.encode(entries))
        let payload: [String: Any] = ["app": "slate-for-memex-ios", "exported_at": MemexMarkdown.localISO(Date()), "notes": notes]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        return url
    }
}
