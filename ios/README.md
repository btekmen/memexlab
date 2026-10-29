# Slate for Memex — iOS

A native, Slate-style private journal for a memex vault. Write or dictate on the phone;
**Send to Memex** writes the entry straight into the vault as plain markdown — the same
files, names and provenance frontmatter as [`../notes/`](../notes/) (the web app) and
`notes/bridge.py`:

- `inbox/YYYY-MM-DD-HH-MM-short-description.md` (docs convention; the memex-cli/mcp
  `<slug>-<UTC stamp>.md` shape is a setting) with `title`, `status: inbox`, `captured_via`,
  `source_url`, `captured_at`, `sources`, `tags` — the engine docs' *Capture Anywhere* contract;
- **Today's journal** → one `daily/YYYY-MM-DD.md` per day from `templates/daily-note.md`;
- every write appended to `.memexlab/log.jsonl`; `write_dir:` in `governance.yml` honoured.

No account, no server, no analytics. Entries live on the phone (Application Support JSON)
until sent.

## How it reaches the vault

| Delivery | How |
| --- | --- |
| **Vault folder** (default) | Pick the vault root once in Files (`UIDocumentPicker`, security-scoped bookmark). Works with the iCloud Drive copy of the vault (Mac Desktop/Documents sync), an Obsidian vault, or a Working Copy checkout. Writes are `NSFileCoordinator`-coordinated so iCloud syncs them cleanly; `memex reindex` runs on the Mac as usual. |
| **Local bridge** | `python3 notes/bridge.py --vault ~/vault --host 0.0.0.0 --reindex` on the Mac; the phone POSTs to it over the LAN (`NSAllowsLocalNetworking`). Can trigger `memex reindex`. |

## Capture anywhere

- **Share sheet** — the `SlateShare` extension ("→ inbox") takes a URL and/or text from any app,
  queues it in the app group, and the app files it (auto-send on open, if enabled).
- **URL scheme** — `slate://capture?title=…&url=…&text=…` for Shortcuts / bookmarklets.
- **Dictation** — `SFSpeechRecognizer` with `requiresOnDeviceRecognition` whenever the language
  supports it; "on-device only" refuses to fall back to Apple's servers. Optionally keeps the
  `.m4a` next to the note (`audio:` frontmatter), like Slate's audio export.

## Build

Needs a Mac with Xcode 15+, and an Apple Developer team for a real device (app groups +
share extension need signing; the simulator runs without a team).

```sh
brew install xcodegen
cd ios
xcodegen generate          # writes Slate.xcodeproj from project.yml
open Slate.xcodeproj
```

In Xcode: select the **Slate** target → Signing & Capabilities → pick your team (also on
**SlateShare**). The app group `group.xyz.memexlab.slate` and bundle ids `xyz.memexlab.Slate` /
`xyz.memexlab.SlateShare` are set in `project.yml`; change the prefix if the ids are taken.
Run on a device (dictation and the share sheet are best tested there). Tests: ⌘U — they pin
the on-disk format to the web app's.

Not included yet: an app icon / asset catalog (add `Assets.xcassets` and set
`ASSETCATALOG_COMPILER_APPICON_NAME`), and a Siri/Shortcuts App Intent.

## Layout

```
project.yml                 XcodeGen spec (targets: Slate, SlateShare, SlateTests)
Shared/MemexMarkdown.swift  frontmatter, slugs, file names, governance write_dir — shared with the extension
Shared/PendingCapture.swift app-group queue the share extension writes into
Slate/SlateApp.swift        app entry, Sender (folder | bridge), slate:// handling
Slate/Models/Entry.swift    the entry record
Slate/Store/                EntryStore (JSON on disk), Settings (UserDefaults)
Slate/Vault/                VaultAccess (bookmark), VaultWriter (files + log), BridgeClient
Slate/Speech/Dictation.swift
Slate/Views/                ContentView + list, EditorView, SettingsView
SlateShare/                 share extension
SlateTests/                 XCTest for the markdown contract
```

This folder is excluded from the Vercel deploy by `.vercelignore`.
