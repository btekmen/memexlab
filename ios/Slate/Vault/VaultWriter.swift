import Foundation

/// Writes one entry into the vault, the way the web app and bridge.py do:
/// <write_dir>/<name>.md (inbox) or daily/<YYYY-MM-DD>.md, plus a line in .memexlab/log.jsonl.
/// Writes are file-coordinated so iCloud sees them cleanly.
struct VaultWriter {
    let root: URL
    let settings: Settings

    func send(_ entry: Entry, audio: URL?) throws -> Entry.Sent {
        let now = Date()
        var cap = entry.capture(via: settings.via, at: now)
        let wd: String
        if entry.isDaily {
            wd = "daily"
        } else {
            let gov = try? read(root.appendingPathComponent("governance.yml"))
            wd = MemexMarkdown.writeDir(governanceYAML: gov)
        }
        guard !wd.contains("..") else { throw VaultError.escapesVault }
        let dir = root.appendingPathComponent(wd, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let name: String
        let action: String
        if entry.isDaily, let day = entry.day {
            name = "\(day).md"; action = "daily_note"
        } else if let s = entry.sent, s.via == "folder", s.path.hasPrefix(wd + "/"),
                  FileManager.default.fileExists(atPath: dir.appendingPathComponent(s.name).path) {
            name = s.name; action = "update_note"                 // edited after a send: same file
        } else {
            name = unique(MemexMarkdown.filename(cap, style: settings.naming), in: dir); action = "capture_note"
        }

        if let audio, settings.keepAudio, !entry.isDaily, FileManager.default.fileExists(atPath: audio.path) {
            let aname = String(name.dropLast(3)) + ".m4a"
            try copy(audio, to: dir.appendingPathComponent(aname))
            cap.audio = aname
        }

        try write(MemexMarkdown.render(cap, writeDir: wd), to: dir.appendingPathComponent(name))
        let path = "\(wd)/\(name)"
        appendLog(["ts": MemexMarkdown.localISO(now), "agent": settings.via, "action": action,
                   "path": path, "title": entry.displayTitle, "sources": cap.sources])
        return Entry.Sent(via: "folder", path: path, name: name, at: now)
    }

    private func unique(_ wanted: String, in dir: URL) -> String {
        let base = String(wanted.dropLast(3))
        var i = 0
        while true {
            let n = i == 0 ? "\(base).md" : "\(base)-\(i).md"
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path) { return n }
            i += 1
        }
    }

    // MARK: coordinated file I/O

    private func read(_ url: URL) throws -> String {
        var coordError: NSError?
        var result: Result<String, Error> = .failure(CocoaError(.fileReadNoSuchFile))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = Result { try String(contentsOf: u, encoding: .utf8) }
        }
        if let e = coordError { throw e }
        return try result.get()
    }

    private func write(_ text: String, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do { try Data(text.utf8).write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError { throw e }
        if let e = writeError { throw e }
    }

    private func copy(_ src: URL, to dst: URL) throws {
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: dst, options: .forReplacing, error: &coordError) { u in
            do {
                if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
                try FileManager.default.copyItem(at: src, to: u)
            } catch { copyError = error }
        }
        if let e = coordError { throw e }
        if let e = copyError { throw e }
    }

    private func appendLog(_ entry: [String: Any]) {
        let dir = root.appendingPathComponent(".memexlab", isDirectory: true)
        let url = dir.appendingPathComponent("log.jsonl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let text = String(data: line, encoding: .utf8) else { return }
        let prev = (try? read(url)) ?? ""
        let sep = prev.isEmpty || prev.hasSuffix("\n") ? "" : "\n"
        try? write(prev + sep + text + "\n", to: url)
    }
}
