# AGENTS.md — memexlab (website)

Adapter for the fleet-wide policy: `/Users/tekmen/_portfolio/AI_OPERATING_SYSTEM.md` (local path on the maintainer's machine). Rules live there; repo facts live here.

> **This repo deploys its root as a static site.** Any file in the repo root may be served at `memexlab.xyz/<file>` — including this one. Keep everything here public-safe: no internal strategy, credentials, or private data in any committed file.

## Purpose

Public website for MemexLab at [memexlab.xyz](https://memexlab.xyz) — landing page, agent guide, and community showcase. Static HTML/CSS/JS plus one Vercel serverless function that turns showcase submissions into review-gated pull requests.

## Stack

- Static HTML/CSS/JS — no framework, no build step, no package.json.
- One serverless function: `api/submit-case.js` (Vercel Node runtime, `vercel.json` sets `maxDuration`).
- Showcase data in `cases.json`; contributions via form → PR, or GitHub issue form (`.github/ISSUE_TEMPLATE/submit-a-case.yml`).

## Commands

| Command | Status | Notes |
|---|---|---|
| (none — no build/test/lint) | — | Static site; open `index.html` or serve the folder to preview. `api/submit-case.js` has no test suite. |

## Deploy model

- **Auto-deploy: pushing to `main` is a production deploy** (Vercel imports this repo; see `SETUP-VERCEL.md` and README). Treat `git push origin main` with deploy-level caution.
- Env vars live in the Vercel project, never in the repo: `GITHUB_TOKEN` (required), `TURNSTILE_SECRET`, `GH_OWNER`, `GH_REPO`, `GH_BASE`, `ALLOW_UNVERIFIED` (see `.env.example` and the header of `api/submit-case.js`).

## Guardrails

- **Root = public web.** Before adding any file to the repo root, remember it becomes a URL on memexlab.xyz (no `.vercelignore` exists). Scratch/working docs do not belong in this repo.
- `api/submit-case.js` is a public write endpoint. Abuse protection is honeypot + Cloudflare Turnstile (fail-closed) + origin check + PR review gate; there is no separate rate limiting. Don't widen what it accepts or what it can write without revisiting that posture.
- Never commit `.env` files or credential values; `.gitignore` covers `.env*` with an `.env.example` exception.
- Keep repo-map/version claims in README consistent with the actual state of `memexlab-engine` and `memexlab-docs` when editing.

## Justified absences

- No ARCHITECTURE.md: a static site plus one ~200-line function; README's contents map covers it.
- No test suite/CI: no build step; the one function is small and review-gated on its output side.
