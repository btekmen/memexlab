import UIKit
import UniformTypeIdentifiers

/// "→ inbox" in the share sheet. Queues the shared URL/text for the app (app-group container);
/// the app files it into the vault the next time it is opened. No UI beyond a confirmation.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Saving to Slate…"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        Task { await handle() }
    }

    private func handle() async {
        var title = "", url = "", text = ""
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if title.isEmpty { title = item.attributedTitle?.string ?? "" }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                        if let u = loaded as? URL { url = u.absoluteString } else if let u = loaded as? NSURL { url = u.absoluteString ?? "" }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                        if let s = loaded as? String { text = s } else if let s = loaded as? NSString { text = s as String }
                    }
                }
            }
            if text.isEmpty, let s = item.attributedContentText?.string, s != url { text = s }
        }
        // Text apps share the page title as plain text next to the URL; treat a short text as the title.
        if title.isEmpty, !url.isEmpty, !text.isEmpty, text.count <= 120, !text.contains("\n") { title = text; text = "" }
        if url.isEmpty, text.hasPrefix("http") { url = text; text = "" }
        if url.isEmpty && text.isEmpty {
            finish("Nothing to capture.")
            return
        }
        do {
            try AppGroup.enqueue(PendingCapture(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                                text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
            finish("Saved → Slate. It lands in inbox/ next time you open the app.")
        } catch {
            finish("Could not save: \(error.localizedDescription)")
        }
    }

    private func finish(_ message: String) {
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
