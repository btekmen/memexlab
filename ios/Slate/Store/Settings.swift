import Foundation
import Observation

@Observable
final class Settings {
    enum Delivery: String, CaseIterable, Identifiable {
        case folder, bridge
        var id: String { rawValue }
        var label: String { self == .folder ? "Vault folder (Files / iCloud)" : "Local bridge (bridge.py on your Mac)" }
    }

    // Plain stored properties (observation-tracked); persist() writes them to UserDefaults —
    // called when the settings sheet closes and when the app goes to the background.
    var delivery: Delivery
    var naming: NamingStyle
    var capturedVia: String
    var defaultTags: String
    var bridgeURL: String
    var reindex: Bool
    var onDeviceOnly: Bool
    var keepAudio: Bool
    var dictationLocale: String
    var autoSendShared: Bool

    func persist() {
        let d = UserDefaults.standard
        d.set(delivery.rawValue, forKey: "delivery")
        d.set(naming.rawValue, forKey: "naming")
        d.set(capturedVia, forKey: "capturedVia")
        d.set(defaultTags, forKey: "defaultTags")
        d.set(bridgeURL, forKey: "bridgeURL")
        d.set(reindex, forKey: "reindex")
        d.set(onDeviceOnly, forKey: "onDeviceOnly")
        d.set(keepAudio, forKey: "keepAudio")
        d.set(dictationLocale, forKey: "dictationLocale")
        d.set(autoSendShared, forKey: "autoSendShared")
    }

    init() {
        let d = UserDefaults.standard
        delivery = Delivery(rawValue: d.string(forKey: "delivery") ?? "") ?? .folder
        naming = NamingStyle(rawValue: d.string(forKey: "naming") ?? "") ?? .date
        capturedVia = d.string(forKey: "capturedVia") ?? "slate-ios"
        defaultTags = d.string(forKey: "defaultTags") ?? ""
        bridgeURL = d.string(forKey: "bridgeURL") ?? "http://192.168.1.10:7357"
        reindex = d.bool(forKey: "reindex")
        onDeviceOnly = d.object(forKey: "onDeviceOnly") == nil ? true : d.bool(forKey: "onDeviceOnly")
        keepAudio = d.bool(forKey: "keepAudio")
        dictationLocale = d.string(forKey: "dictationLocale") ?? ""
        autoSendShared = d.object(forKey: "autoSendShared") == nil ? true : d.bool(forKey: "autoSendShared")
    }

    var via: String { capturedVia.trimmingCharacters(in: .whitespaces).isEmpty ? "slate-ios" : capturedVia.trimmingCharacters(in: .whitespaces) }
    var locale: Locale { dictationLocale.isEmpty ? Locale.current : Locale(identifier: dictationLocale) }
}
