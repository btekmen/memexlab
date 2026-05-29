// Vercel serverless function: accept a Showcase case submission and open a
// pull request adding it to cases.json. A maintainer reviews/merges before it
// goes live, so nothing is published automatically.
//
// Required env vars (set in the Vercel project):
//   GITHUB_TOKEN     fine-grained PAT for btekmen/memexlab with
//                    Contents: Read and write + Pull requests: Read and write
// Optional env vars:
//   GH_OWNER         default "btekmen"
//   GH_REPO          default "memexlab"
//   GH_BASE          default "main"
//   TURNSTILE_SECRET Cloudflare Turnstile secret (enables bot verification)

const REGIONS = ["Africa", "Americas", "Asia", "Europe", "Middle East", "Oceania"];
const API = "https://api.github.com";

function clean(s, max) {
  // strip control characters, collapse whitespace, trim, cap length
  return String(s == null ? "" : s)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}

function slugify(s) {
  return clean(s, 60).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "case";
}

async function gh(token, method, path, body) {
  const res = await fetch(API + path, {
    method: method,
    headers: {
      Authorization: "Bearer " + token,
      Accept: "application/vnd.github+json",
      "User-Agent": "memexlab-submit",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (e) { /* non-JSON */ }
  if (!res.ok) {
    const msg = (json && json.message) || ("GitHub API " + res.status);
    throw new Error(msg);
  }
  return json;
}

async function verifyTurnstile(secret, token, ip) {
  if (!secret) return true; // not configured -> skip
  const form = new URLSearchParams();
  form.append("secret", secret);
  form.append("response", token || "");
  if (ip) form.append("remoteip", ip);
  try {
    const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
    const j = await r.json();
    return !!j.success;
  } catch (e) {
    return false;
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ ok: false, error: "Method not allowed" });
  }

  let body = req.body;
  if (typeof body === "string") { try { body = JSON.parse(body); } catch (e) { body = {}; } }
  body = body || {};

  // Honeypot: real users never fill this hidden field. Silently accept bots.
  if (clean(body.company, 50)) return res.status(200).json({ ok: true, skipped: true });

  // Bot check
  const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim();
  const okBot = await verifyTurnstile(process.env.TURNSTILE_SECRET, body.turnstileToken, ip);
  if (!okBot) return res.status(400).json({ ok: false, error: "Verification failed. Please retry." });

  // Validate + normalize
  const title = clean(body.title, 120);
  const author = clean(body.author, 80);
  const country = clean(body.country, 60);
  const region = clean(body.region, 20);
  const summary = clean(body.summary, 400);
  const url = clean(body.url, 300);
  let categories = body.categories;
  if (typeof categories === "string") categories = categories.split(",");
  categories = (Array.isArray(categories) ? categories : []).map(function (c) { return clean(c, 40); }).filter(Boolean).slice(0, 5);

  const errors = [];
  if (!title) errors.push("title");
  if (!author) errors.push("author");
  if (!country) errors.push("country");
  if (REGIONS.indexOf(region) === -1) errors.push("region");
  if (!summary) errors.push("summary");
  if (!categories.length) errors.push("categories");
  if (url && !/^https?:\/\//i.test(url)) errors.push("url");
  if (errors.length) return res.status(400).json({ ok: false, error: "Invalid or missing fields: " + errors.join(", ") });

  const token = process.env.GITHUB_TOKEN;
  if (!token) return res.status(500).json({ ok: false, error: "Server not configured (missing GITHUB_TOKEN)." });

  const owner = process.env.GH_OWNER || "btekmen";
  const repo = process.env.GH_REPO || "memexlab";
  const base = process.env.GH_BASE || "main";
  const repoPath = "/repos/" + owner + "/" + repo;

  const entry = {
    title: title,
    author: author,
    url: url,
    country: country,
    region: region,
    categories: categories,
    summary: summary,
    date: new Date().toISOString().slice(0, 7),
  };

  try {
    // 1. Read current cases.json
    const file = await gh(token, "GET", repoPath + "/contents/cases.json?ref=" + encodeURIComponent(base));
    const current = JSON.parse(Buffer.from(file.content, "base64").toString("utf8"));
    if (!Array.isArray(current.cases)) current.cases = [];
    current.cases.push(entry);
    const updated = Buffer.from(JSON.stringify(current, null, 2) + "\n", "utf8").toString("base64");

    // 2. Branch off base
    const ref = await gh(token, "GET", repoPath + "/git/ref/heads/" + encodeURIComponent(base));
    const branch = "case/" + slugify(title) + "-" + Date.now().toString(36);
    await gh(token, "POST", repoPath + "/git/refs", { ref: "refs/heads/" + branch, sha: ref.object.sha });

    // 3. Commit the updated file to the branch
    await gh(token, "PUT", repoPath + "/contents/cases.json", {
      message: 'Showcase: add "' + title + '"',
      content: updated,
      sha: file.sha,
      branch: branch,
    });

    // 4. Open the PR
    const prBody =
      "Submitted via the on-site form.\n\n" +
      "- **Author:** " + author + "\n" +
      "- **Country:** " + country + " (" + region + ")\n" +
      "- **Categories:** " + categories.join(", ") + "\n" +
      (url ? "- **Link:** " + url + "\n" : "") +
      "\n> " + summary + "\n\n" +
      "Review the entry in `cases.json`, then merge to publish.";
    const pr = await gh(token, "POST", repoPath + "/pulls", {
      title: "Showcase: " + title,
      head: branch,
      base: base,
      body: prBody,
    });

    return res.status(200).json({ ok: true, prUrl: pr.html_url, prNumber: pr.number });
  } catch (e) {
    return res.status(502).json({ ok: false, error: "Could not open the pull request: " + e.message });
  }
};
