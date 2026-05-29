# MemexLab

The landing site for **MemexLab** — an agent-operable Memex skills layer built on
OpenClaw and the Memex knowledge operating system.

**Live:** <https://memexlab.xyz/> · **Status:** `0.2.0-harness-preview` (early preview — not production-stable)

MemexLab is a local-first, markdown-native knowledge operating system that turns raw
inputs into governed, citable, compounding thinking assets for agents. This repository
holds **only the public landing page** — a static, dependency-free HTML/CSS site.

## Contents

- `index.html` — the landing page (semantic HTML, responsive, SEO + Open Graph + JSON-LD).
- `styles.css` — styles (CSS variables, `prefers-reduced-motion` aware).
- `assets/favicon.svg` — favicon.
- `CNAME` — custom domain (`memexlab.xyz`).
- `.nojekyll` — serves files verbatim (no Jekyll processing).
- `.github/workflows/pages.yml` — GitHub Pages deployment on push to `main`.

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
