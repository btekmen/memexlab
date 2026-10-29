# MemexLab — website

The public website for **MemexLab** ([memexlab.xyz](https://memexlab.xyz)) — an
agent-operable, markdown-native memory layer for OpenClaw-compatible agents.

**Live:** <https://memexlab.xyz/> · **Status:** `0.2.0-harness-preview` (early preview — not production-stable)

This repository holds **only the website**: static HTML/CSS/JS plus one serverless function
that powers the showcase submission form. The methodology lives in the docs repo; the open
`memex` CLI engine lives in [`memexlab-engine`](https://github.com/btekmen/memexlab-engine).

## Repository map

| Name | What it is | Visibility |
| --- | --- | --- |
| **`memexlab`** (this repo) | The website at memexlab.xyz | Public |
| **`memexlab-docs`** | Documentation & specification | Public |
| **[`memexlab-engine`](https://github.com/btekmen/memexlab-engine)** | The governed memory layer for AI agents — the open `memex` CLI engine (skills / schemas / evals / governance) | Public |
| **Memex** | The flagship app — your sovereign personal AGI ([memex.memexlab.xyz](https://memex.memexlab.xyz)), built on MemexLab | Live |
| Personal vaults | Your actual knowledge base | Never published |

## Contents

- `index.html` — landing page (semantic HTML, responsive, SEO + Open Graph + JSON-LD).
- `agents.html` — guide for OpenClaw agents operating a vault.
- `showcase.html` / `showcase.js` — the open-source community showcase.
- `submit-form.js` — on-site case-submission form handler.
- `notes/` — **Slate for Memex**: a private, local-first notes/journal app (`index.html`, `notes.js`, `notes.css`, installable PWA) whose entries land in your vault's `inbox/` as markdown with provenance frontmatter — see [Slate for Memex](#slate-for-memex-notes).
- `notes/bridge.py` — optional stdlib-only local bridge for the app (writes into the vault, runs `memex reindex`).
- `api/submit-case.js` — Vercel serverless function: validates a submission and opens a PR.
- `cases.json` — showcase data (one object per case; community-contributed).
- `styles.css` / `assets/favicon.svg` — styles and favicon.
- `CONTRIBUTING.md` — how to submit a case.
- `SETUP-VERCEL.md` — Vercel hosting + form setup.
- `vercel.json` — Vercel project config.
- `LICENSE` — MIT.

## Hosting & deploy

Hosted on **Vercel** — the site is static **plus** one serverless function
(`api/submit-case.js`), which GitHub Pages can't run. Importing the repo, the scoped GitHub
token, Cloudflare Turnstile, env vars, and DNS are all covered in
[`SETUP-VERCEL.md`](SETUP-VERCEL.md). Vercel auto-deploys on every push to `main`.

## Submission form & abuse protection

Flow: on-site form → serverless function → opens a **pull request** against `cases.json` → a
maintainer reviews and merges to publish. Nothing goes live unreviewed. Bot protection is a
honeypot field **plus Cloudflare Turnstile**; the function is **fail-closed** — it refuses
submissions unless Turnstile is configured — and only accepts requests from the site's own
origin. Configure Turnstile per [`SETUP-VERCEL.md`](SETUP-VERCEL.md) before promoting the form
widely. The GitHub issue form and direct PRs are always-available fallbacks.

## Slate for Memex (`notes/`)

[memexlab.xyz/notes](https://memexlab.xyz/notes/) is a Slate-style private journal for a memex
vault — a fifth path for the engine docs' [Capture Anywhere](https://btekmen.github.io/memexlab-engine/capture-anywhere/)
contract. Write or dictate an entry, and **Send to Memex** writes
`<vault>/inbox/YYYY-MM-DD-HH-MM-short-description.md` (the docs' naming; the
`memex-cli`/`memexlab-mcp` shape `<slug>-<UTC stamp>.md` is a setting) with the contract's
frontmatter — `title`, `status: inbox`, `captured_via`, `source_url` — plus `captured_at`,
`sources` and `tags`, and appends the write to `.memexlab/log.jsonl`. **Today's journal** keeps
one `daily/YYYY-MM-DD.md` per day from the `daily-note.md` template (`date`, `type: daily`).
`write_dir:` in the vault's `governance.yml` is honoured. Opening the app with
`?title=&text=&url=` (Android share target, a bookmarklet, an iOS Shortcut) pre-fills an entry.
Entries stay in the browser (IndexedDB) until sent; there is no account, server, or analytics.

Three ways to reach the vault:

| Path | Works in | Notes |
| --- | --- | --- |
| **Vault folder** | Chrome, Edge, Brave, Arc | Pick the vault once (File System Access API); writes go straight into `inbox/`. |
| **Local bridge** | Every browser, iPhone on the LAN | `python3 notes/bridge.py --vault ~/vault [--reindex]` serves the app at `http://127.0.0.1:7357` and exposes one write endpoint; `--reindex` runs `memex reindex` after each send. Loopback-only unless `--host` is given; browser origins are checked. |
| **Download** | Anywhere | Save the `.md` yourself and drop it into `inbox/`. |

Dictation uses the browser's speech recognition where available (on-device on recent Safari/iOS;
Chrome may use Google's service — the app says nothing else leaves the machine). Export/import
of all entries is JSON, as in Slate.

## Local preview

No build step. Static preview:

```bash
python3 -m http.server 8000   # then open http://localhost:8000
```

For the form/function locally, use `vercel dev` (see `SETUP-VERCEL.md`).

## License

[MIT](LICENSE).

## Credits

Intellectual lineage and references are credited on the site and in `memexlab-docs`. Not
affiliated with the people or projects referenced unless otherwise stated.
