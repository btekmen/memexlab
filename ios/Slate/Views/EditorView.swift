import SwiftUI

struct EditorView: View {
    @Environment(EntryStore.self) private var store
    @Environment(Settings.self) private var settings
    @Environment(VaultAccess.self) private var vault
    @Environment(Sender.self) private var sender
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Entry
    @State private var dictation = Dictation()
    @State private var baseBody = ""
    @State private var status: String?
    @State private var confirmDelete = false
    @FocusState private var bodyFocused: Bool

    init(entry: Entry) { _draft = State(initialValue: entry) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.title2.weight(.bold))
                        .disabled(draft.isDaily)
                        .foregroundStyle(draft.isDaily ? .secondary : .primary)
                    TextField("tags: idea, meeting, topic/x", text: $draft.tags)
                        .font(.footnote).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(8).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    if !draft.isDaily {
                        TextField("sources: https://…, [[slug]]", text: $draft.sources)
                            .font(.footnote).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .padding(8).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    TextEditor(text: $draft.body)
                        .focused($bodyFocused)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 320)
                    if let s = draft.sent {
                        Text("\(draft.isStale ? "Edited since last send · previously sent" : "Sent") \(s.at.formatted(date: .abbreviated, time: .shortened)) via \(s.via) → \(s.path)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let status { Text(status).font(.caption).foregroundStyle(status.hasPrefix("Send failed") ? .red : .secondary) }
                }
                .padding()
            }
            bottomBar
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: MemexMarkdown.render(draft.capture(via: settings.via, at: Date()), writeDir: draft.isDaily ? "daily" : "inbox"),
                              preview: SharePreview(draft.displayTitle)) { Label("Share as markdown", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete entry", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Delete this entry from the phone? Files already in the vault are not touched.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { dictation.stop(); store.delete(draft); dismiss() }
        }
        .onChange(of: draft) { _, new in
            var e = new
            e.updated = Date()
            store.upsert(e)
        }
        .onChange(of: dictation.transcript) { _, t in
            guard dictation.isRecording || !t.isEmpty else { return }
            let sep = baseBody.isEmpty || baseBody.hasSuffix("\n") || baseBody.hasSuffix(" ") ? "" : " "
            draft.body = baseBody + sep + t
        }
        .onChange(of: dictation.isRecording) { _, rec in
            if !rec { baseBody = draft.body; if let e = dictation.lastError { status = e } }
        }
        .onDisappear { dictation.stop() }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { toggleDictation() } label: {
                Label(dictation.isRecording ? "Stop" : "Dictate", systemImage: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(dictation.isRecording ? Color.red.opacity(0.25) : Theme.panel, in: Capsule())
                    .foregroundStyle(dictation.isRecording ? .red : .primary)
            }
            if dictation.isRecording {
                Text(dictation.usingOnDevice ? "on-device" : "Apple servers").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await send() } } label: {
                Label(sender.busy ? "Sending…" : "Send to Memex", systemImage: "arrow.up.doc")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.bg)
            }
            .disabled(sender.busy || dictation.isRecording)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private func toggleDictation() {
        if dictation.isRecording { dictation.stop(); return }
        baseBody = draft.body
        var recordURL: URL?
        if settings.keepAudio {
            let name = draft.audioFile ?? "\(draft.id.uuidString).m4a"
            draft.audioFile = name
            recordURL = store.audioDirectory.appendingPathComponent(name)
        }
        status = nil
        Task {
            do { try await dictation.start(locale: settings.locale, onDeviceOnly: settings.onDeviceOnly, recordTo: recordURL) }
            catch { status = error.localizedDescription }
        }
    }

    private func send() async {
        dictation.stop()
        bodyFocused = false
        let ok = await sender.send(draft, store: store, settings: settings, vault: vault)
        status = sender.lastMessage
        if ok, let e = store.entry(id: draft.id) { draft.sent = e.sent }
    }
}
