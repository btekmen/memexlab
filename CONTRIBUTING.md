# Contributing to the MemexLab Showcase

The [showcase](https://memexlab.xyz/showcase.html) is an open, community-maintained
gallery of real-world Memex developments and best cases. Anyone can add a case. There is
no backend and no database — every entry lives in [`cases.json`](cases.json) and is
reviewed like any other open-source change.

## Two ways to submit

### 1. Issue form (easiest)

Open a [**Submit a case** issue](https://github.com/btekmen/memexlab/issues/new?template=submit-a-case.yml),
fill in the fields, and a maintainer will convert it into a `cases.json` entry.

### 2. Pull request (direct)

[Edit `cases.json`](https://github.com/btekmen/memexlab/edit/main/cases.json), add one
object to the `cases` array following the schema below, and open a PR.

## Case entry schema

```json
{
  "title": "Short, specific title",
  "author": "Your name or @handle",
  "url": "https://…  (optional: link to a write-up or repo)",
  "country": "Country",
  "flag": "🇺🇳  (optional emoji)",
  "region": "Africa | Americas | Asia | Europe | Middle East | Oceania",
  "categories": ["Research synthesis", "Governance"],
  "summary": "1–3 sentences: what you built and why it matters.",
  "date": "2026-05"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `title` | yes | Specific, not marketing. |
| `author` | yes | Name or `@handle`. |
| `url` | no | A link readers can follow, if you have one. |
| `country` | yes | Where the work is based. |
| `flag` | no | Emoji flag, purely decorative. |
| `region` | yes | One of the six values above (drives the region filter). |
| `categories` | yes | One or more tags; reuse existing ones where they fit. |
| `summary` | yes | Plain, concrete description. |
| `date` | yes | `YYYY` or `YYYY-MM`. |

## Guidelines

- **Be honest and concrete.** Describe what was actually built. No unverifiable claims,
  no hype words ("revolutionary", "10x"), no implying endorsement or affiliation.
- **Respect privacy.** Don't include private vault contents, secrets, personal data, or
  anyone's information without their consent.
- **Keep it on-topic.** The case should involve Memex-style durable, markdown-native,
  agent-operable knowledge work.
- **One object per case.** Keep `cases.json` valid JSON (no trailing commas).

## Validating your change

`cases.json` must stay valid JSON. A quick local check:

```bash
python3 -c "import json; json.load(open('cases.json')); print('cases.json OK')"
```

Maintainers may lightly edit wording for consistency before merging. Thanks for
contributing!
