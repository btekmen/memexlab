# Hosting MemexLab on Vercel (with the on-site submission form)

The site is static, **plus** one serverless function (`api/submit-case.js`) that powers
the on-page case form: it validates a submission and opens a pull request against
`cases.json`. A maintainer reviews and merges, so nothing is published unreviewed.

GitHub Pages can't run that function — Vercel can. These are the one-time steps to move
`memexlab.xyz` to Vercel. Everything in the repo is already wired; this is account setup.

## 1. Import the repo into Vercel

1. Sign in at <https://vercel.com> with your GitHub account.
2. **Add New… → Project → Import** `btekmen/memexlab`.
3. Framework preset: **Other** (it's static + an `api/` function — zero config).
4. Deploy. You'll get a `*.vercel.app` URL serving the site and the function.

## 2. Create a GitHub token for the function

The function needs permission to open PRs on this repo. Use a **fine-grained PAT**:

1. GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new**.
2. **Resource owner:** btekmen · **Repository access:** *Only select repositories* → `memexlab`.
3. **Repository permissions:**
   - **Contents:** Read and write
   - **Pull requests:** Read and write
4. Generate and copy the token (starts with `github_pat_…`).

> Scope it to this one repo only. Never commit the token — it lives in Vercel env vars.

## 3. (Required) Cloudflare Turnstile for bot protection

The submission function is **fail-closed**: with no Turnstile secret set it returns `503`
and the form is disabled, so the configured GitHub token can't be abused to open unlimited
PRs. Configure Turnstile to enable the form.

1. Cloudflare dashboard → **Turnstile → Add site** → add `memexlab.xyz`.
2. Copy the **Site key** (public) and **Secret key** (private).
3. Put the **Site key** in `showcase.html` on the form: `data-sitekey="<site key>"` (client widget).
4. Set `TURNSTILE_SECRET` in Vercel (next step) — both are required for the form to work.

> Escape hatch for local testing only: set `ALLOW_UNVERIFIED=true` to bypass the origin and
> Turnstile checks. Never set this in Production.

## 4. Add environment variables in Vercel

Project → **Settings → Environment Variables** (Production + Preview):

| Name | Value |
| --- | --- |
| `GITHUB_TOKEN` | the fine-grained PAT from step 2 |
| `TURNSTILE_SECRET` | the Turnstile secret from step 3 (**required** — form is disabled without it) |
| `GH_OWNER` | `btekmen` (optional; this is the default) |
| `GH_REPO` | `memexlab` (optional; default) |
| `GH_BASE` | `main` (optional; default) |

Redeploy after adding them.

## 5. Point the domain at Vercel

Project → **Settings → Domains → Add** `memexlab.xyz` (and `www.memexlab.xyz`). Vercel
shows the exact DNS records. At your DNS provider (GoDaddy), **replace** the GitHub Pages
records with Vercel's:

- **Apex `memexlab.xyz`:** `A` → `76.76.21.21`
- **`www`:** `CNAME` → `cname.vercel-dns.com`

Remove the old GitHub Pages `A`/`AAAA` records (`185.199.108–111.153`, etc.) so the apex
points only to Vercel. Vercel issues the TLS certificate automatically.

> Because the apex can only point to one host, this **moves** the site off GitHub Pages.
> Once Vercel serves `memexlab.xyz`, you can disable the Pages deploy (delete or disable
> `.github/workflows/pages.yml`) and remove the `CNAME` file — both are GitHub-Pages-only.

## 6. Verify

- `https://memexlab.xyz/` and `/showcase.html` load.
- Submit a test case on the form → it should report a PR link. Confirm the PR appears in
  the repo, then close it (or merge to publish the test).

## Local development

```bash
npm i -g vercel        # once
vercel dev             # serves the site + /api locally with your env vars
```

Without `vercel dev`, a plain static server (e.g. `python3 -m http.server`) renders the
page but the form's `POST /api/submit-case` won't exist — the form falls back to the
GitHub links, which is expected.
