# MemexLab

The landing site for **MemexLab** — an agent-operable Memex skills layer built on
OpenClaw and the Memex knowledge operating system.

**Live:** <https://memexlab.xyz/> · **Status:** `0.2.0-harness-preview` (early preview — not production-stable)

MemexLab is a local-first, markdown-native knowledge operating system that turns raw
inputs into governed, citable, compounding thinking assets for agents. This repository
holds **only the public landing page** — a static, dependency-free HTML/CSS site.

## Contents

- `index.html` — the landing page (semantic HTML, responsive, SEO + Open Graph + JSON-LD).
- `showcase.html` / `showcase.js` — the open-source community showcase.
- `submit-form.js` — the on-site case-submission form handler.
- `api/submit-case.js` — Vercel serverless function: validates a submission and opens a PR.
- `cases.json` — the showcase data (one object per case; community-contributed).
- `styles.css` — styles (CSS variables, `prefers-reduced-motion` aware).
- `assets/favicon.svg` — favicon.
- `CONTRIBUTING.md` — how to submit a case.
- `SETUP-VERCEL.md` — how to host on Vercel and enable the on-site form.
- `vercel.json` — Vercel project config.
- `CNAME` / `.nojekyll` / `.github/workflows/pages.yml` — GitHub Pages support (legacy/mirror).
- `.github/ISSUE_TEMPLATE/submit-a-case.yml` — case submission issue form (no-JS fallback).

## Hosting

The site is static **plus** one serverless function for the on-site submission form, so it
is hosted on **Vercel** (`memexlab.xyz`). The function opens a pull request for each
submission; a maintainer reviews and merges to publish. See
[`SETUP-VERCEL.md`](SETUP-VERCEL.md) for the one-time setup (Vercel project, GitHub token,
Turnstile, DNS).

The GitHub Pages files (`CNAME`, `.nojekyll`, the Pages workflow) remain for a static-only
fallback; they don't run the form.

## Showcase

[`showcase.html`](https://memexlab.xyz/showcase.html) is an open, community-maintained
gallery of real-world Memex developments and best cases from around the world. It is fully
static: the page reads [`cases.json`](cases.json) at runtime and renders filterable cards —
no backend, no database.

Anyone can contribute a case via the issue form or a pull request that adds one object to
`cases.json`. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the schema and guidelines.

## Local preview

No dependencies or build step — open `index.html` directly, or serve the folder:

```bash
python3 -m http.server 8000
# then open http://localhost:8000
```

## Deploy

The workflow deploys on every push to `main`. One-time setup:

1. **Settings → Pages → Source: GitHub Actions**.
2. DNS for `memexlab.xyz` (apex records at your DNS provider):

   ```
   A     @   185.199.108.153
   A     @   185.199.109.153
   A     @   185.199.110.153
   A     @   185.199.111.153
   AAAA  @   2606:50c0:8000::153
   AAAA  @   2606:50c0:8001::153
   AAAA  @   2606:50c0:8002::153
   AAAA  @   2606:50c0:8003::153
   ```

3. Confirm the custom domain in **Settings → Pages**, then enable **Enforce HTTPS**.

## Credits

Intellectual lineage and references are credited on the site. Not affiliated with the
people or projects referenced unless otherwise stated.
