import SwiftUI

enum Theme {
    static let bg = Color(red: 0.031, green: 0.047, blue: 0.090)      // #080c17
    static let panel = Color(red: 0.063, green: 0.102, blue: 0.180)   // #101a2e
    static let accent = Color(red: 0.133, green: 0.827, blue: 0.933)  // #22d3ee
    static let good = Color(red: 0.373, green: 0.816, blue: 0.627)
    static let warn = Color(red: 0.961, green: 0.706, blue: 0.329)
}

@main
struct SlateApp: App {
    @State private var store = EntryStore()
    @State private var settings = Settings()
    @State private var vault = VaultAccess()
    @State private var sender = Sender()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(settings)
                .environment(vault)
                .environment(sender)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: phase) { _, now in
                    if now == .active { importPending() } else { settings.persist(); store.persist() }
                }
                .onOpenURL { url in
                    // slate://capture?title=&url=&text=  — for Shortcuts and bookmarklets.
                    guard url.scheme == "slate", let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
                    let q = { (k: String) in comps.queryItems?.first { $0.name == k }?.value ?? "" }
                    try? AppGroup.enqueue(PendingCapture(title: q("title"), url: q("url"), text: q("text")))
                    importPending()
                }
        }
    }

    private func importPending() {
        let added = store.importPending(defaultTags: settings.defaultTags)
        guard !added.isEmpty, settings.autoSendShared else { return }
        Task { for e in added { _ = await sender.send(e, store: store, settings: settings, vault: vault) } }
    }
}

/// One place that knows how to deliver an entry (folder or bridge) and record the result.
@Observable
final class Sender {
    var busy = false
    var lastMessage: String?

    @MainActor
    func send(_ entry: Entry, store: EntryStore, settings: Settings, vault: VaultAccess) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let sent: Entry.Sent
            switch settings.delivery {
            case .bridge:
                guard let client = BridgeClient(settings.bridgeURL) else { throw VaultError.bridge("Bridge URL is not valid.") }
                sent = try await client.send(entry, settings: settings)
            case .folder:
                let audio = entry.audioFile.map { store.audioDirectory.appendingPathComponent($0) }
                sent = try vault.withAccess { root in try VaultWriter(root: root, settings: settings).send(entry, audio: audio) }
            }
            var e = store.entry(id: entry.id) ?? entry
            e.sent = sent
            store.upsert(e)
            lastMessage = "Sent → \(sent.path)"
            return true
        } catch {
            lastMessage = "Send failed: \(error.localizedDescription)"
            return false
        }
    }
}
