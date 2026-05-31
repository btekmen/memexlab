# MemexLab — website

The public website for **MemexLab** ([memexlab.xyz](https://memexlab.xyz)) — an
agent-operable, markdown-native memory layer for OpenClaw-compatible agents.

**Live:** <https://memexlab.xyz/> · **Status:** `0.2.0-harness-preview` (early preview — not production-stable)

This repository holds **only the website**: static HTML/CSS/JS plus one serverless function
that powers the showcase submission form. The methodology lives in the docs repo; the engine
is a separate, not-yet-public repository.

## Repository map

| Name | What it is | Visibility |
| --- | --- | --- |
| **`memexlab`** (this repo) | The website at memexlab.xyz | Public |
| **`memexlab-docs`** | Documentation & specification | Public |
| **`memex`** | The CLI engine + skills / schemas / evals / governance | Private — not yet released |
| Personal vaults | Your actual knowledge base | Never published |

## Contents

- `index.html` — landing page (semantic HTML, responsive, SEO + Open Graph + JSON-LD).
- `agents.html` — guide for OpenClaw agents operating a vault.
- `showcase.html` / `showcase.js` — the open-source community showcase.
- `submit-form.js` — on-site case-submission form handler.
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
