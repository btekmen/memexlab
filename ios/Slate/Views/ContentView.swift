import SwiftUI

struct ContentView: View {
    @Environment(EntryStore.self) private var store
    @Environment(Settings.self) private var settings
    @Environment(VaultAccess.self) private var vault
    @Environment(Sender.self) private var sender
    @State private var path: [Entry] = []
    @State private var showSettings = false
    @State private var search = ""
    @State private var sendingAll = false

    var body: some View {
        NavigationStack(path: $path) {
            EntryListView(search: $search) { path = [$0] }
                .navigationTitle("Slate")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $search, prompt: "Search entries")
                .navigationDestination(for: Entry.self) { EditorView(entry: $0) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { path = [store.daily()] } label: { Label("Today's journal", systemImage: "calendar") }
                        Button { path = [store.newEntry(defaultTags: settings.defaultTags)] } label: { Label("New entry", systemImage: "square.and.pencil") }
                    }
                }
                .safeAreaInset(edge: .bottom) { statusBar }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .onAppear {
                    // First launch: go straight to picking the vault.
                    if !vault.isConnected && settings.delivery == .folder && store.entries.isEmpty { showSettings = true }
                }
        }
        .background(Theme.bg)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if !store.unsent.isEmpty {
                Button(sendingAll ? "Sending…" : "Send \(store.unsent.count) unsent") { sendAll() }
                    .font(.footnote.weight(.semibold)).disabled(sendingAll)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var statusColor: Color {
        switch settings.delivery {
        case .folder: return vault.isConnected ? Theme.good : Theme.warn
        case .bridge: return Theme.accent
        }
    }
    private var statusText: String {
        switch settings.delivery {
        case .folder: return vault.isConnected ? "Vault: \(vault.name)" : "No vault folder — open Settings"
        case .bridge: return "Bridge: \(settings.bridgeURL)"
        }
    }

    private func sendAll() {
        sendingAll = true
        Task {
            for e in store.unsent {
                if !(await sender.send(e, store: store, settings: settings, vault: vault)) { break }
            }
            sendingAll = false
        }
    }
}

struct EntryListView: View {
    @Environment(EntryStore.self) private var store
    @Binding var search: String
    var open: (Entry) -> Void

    private var filtered: [Entry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.entries
            .filter { q.isEmpty || ($0.title + " " + $0.body + " " + $0.tags).lowercased().contains(q) }
            .sorted { $0.updated > $1.updated }
    }

    private var groups: [(String, [Entry])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.updated) }
        return dict.keys.sorted(by: >).map { day in
            let label = cal.isDateInToday(day) ? "Today" : cal.isDateInYesterday(day) ? "Yesterday"
                : day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            return (label, dict[day]!)
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No entries yet" : "No matches",
                                       systemImage: search.isEmpty ? "square.and.pencil" : "magnifyingglass",
                                       description: Text(search.isEmpty ? "Write or dictate. Entries stay on this phone until you send them to your vault." : ""))
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.0) { label, entries in
                Section(label) {
                    ForEach(entries) { e in
                        Button { open(e) } label: { EntryRow(entry: e) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.delete(e) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
    }
}

struct EntryRow: View {
    let entry: Entry
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(entry.sent == nil ? Theme.warn : entry.isStale ? Theme.accent : Theme.good)
                .frame(width: 8, height: 8).padding(.top, 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayTitle).font(.body.weight(.semibold)).lineLimit(1)
                    if entry.isDaily {
                        Text("DAILY").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().stroke(Theme.accent.opacity(0.5)))
                    }
                    if entry.audioFile != nil { Image(systemName: "waveform").font(.caption).foregroundStyle(.secondary) }
                }
                Text(entry.snippet).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}
