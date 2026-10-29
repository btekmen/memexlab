import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(EntryStore.self) private var store
    @Environment(Settings.self) private var settings
    @Environment(VaultAccess.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var pickFolder = false
    @State private var bridgeState: String?
    @State private var exportURL: URL?
    @State private var confirmWipe = false
    @State private var folderError: String?

    private let locales = [("", "Device language"), ("tr-TR", "Türkçe"), ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("de-DE", "Deutsch"), ("fr-FR", "Français")]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Deliver via", selection: $settings.delivery) {
                        ForEach(Settings.Delivery.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } header: { Text("Where entries go") } footer: {
                    Text("Inbox entries are written as plain markdown with Capture Anywhere frontmatter (title, status: inbox, captured_via, source_url) into the vault's write dir — inbox/ unless governance.yml says otherwise — and logged to .memexlab/log.jsonl. Today's journal keeps one daily/YYYY-MM-DD.md.")
                }

                if settings.delivery == .folder {
                    Section("Vault folder") {
                        HStack {
                            Image(systemName: vault.isConnected ? "folder.fill" : "folder.badge.questionmark")
                                .foregroundStyle(vault.isConnected ? Theme.good : Theme.warn)
                            Text(vault.isConnected ? vault.name : "Not chosen")
                            Spacer()
                            Button(vault.isConnected ? "Change…" : "Choose…") { pickFolder = true }
                        }
                        if vault.isConnected { Button("Forget folder", role: .destructive) { vault.forget() } }
                        if let folderError { Text(folderError).font(.footnote).foregroundStyle(.red) }
                        Text("Pick the vault's root (the folder that holds inbox/). With the Mac's Desktop in iCloud Drive it is under iCloud Drive → Desktop; an Obsidian vault is under Obsidian; a git checkout lives in Working Copy.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Local bridge") {
                        TextField("http://192.168.1.10:7357", text: $settings.bridgeURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Run memex reindex after each send", isOn: $settings.reindex)
                        Button("Test connection") { testBridge() }
                        if let bridgeState { Text(bridgeState).font(.footnote).foregroundStyle(.secondary) }
                        Text("On the Mac: python3 notes/bridge.py --vault ~/vault --host 0.0.0.0 --reindex — then use the Mac's LAN address here.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Files") {
                    Picker("Inbox file name", selection: $settings.naming) {
                        ForEach(NamingStyle.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("captured_via", text: $settings.capturedVia).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Default tags for new entries", text: $settings.defaultTags).textInputAutocapitalization(.never).autocorrectionDisabled()
                }

                Section {
                    Picker("Language", selection: $settings.dictationLocale) {
                        ForEach(locales, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Toggle("On-device recognition only", isOn: $settings.onDeviceOnly)
                    Toggle("Keep the recording (.m4a next to the note)", isOn: $settings.keepAudio)
                } header: { Text("Dictation") } footer: {
                    Text("With “on-device only”, speech never leaves the phone; languages Apple hasn't shipped on-device models for will refuse to start instead of falling back to Apple's servers.")
                }

                Section("Capture anywhere") {
                    Toggle("Send shared items as soon as the app opens", isOn: $settings.autoSendShared)
                    Text("Share sheet: “→ inbox” in Safari and any app. Shortcuts: open slate://capture?title=…&url=…&text=….")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Your data") {
                    Text("\(store.entries.count) entries on this phone").font(.footnote).foregroundStyle(.secondary)
                    Button("Export all (JSON)") { exportURL = try? store.exportJSON() }
                    if let exportURL { ShareLink(item: exportURL) { Label("Share export", systemImage: "square.and.arrow.up") } }
                    Button("Delete everything on this phone", role: .destructive) { confirmWipe = true }
                }

                Section {
                    Text("No account. No server. No analytics. Entries stay on this phone until you send them to a folder you chose or a bridge you run.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Slate for Memex on GitHub", destination: URL(string: "https://github.com/btekmen/memexlab/tree/main/ios")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settings.persist(); dismiss() } } }
            .onDisappear { settings.persist() }
            .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do { try vault.set(url: url); folderError = nil } catch { folderError = error.localizedDescription }
                case .failure(let e): folderError = e.localizedDescription
                }
            }
            .confirmationDialog("Delete every entry stored on this phone? Files already in your vault are not touched.", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { store.deleteAll() }
            }
        }
    }

    private func testBridge() {
        guard let client = BridgeClient(settings.bridgeURL) else { bridgeState = "Not a valid URL"; return }
        bridgeState = "Testing…"
        Task {
            do { let i = try await client.info(); bridgeState = "OK → \(i.vault)/\(i.write_dir)/ (reindex \(i.reindex == true ? "on" : "off"))" }
            catch { bridgeState = "Not reachable: \(error.localizedDescription)" }
        }
    }
}
