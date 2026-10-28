#!/usr/bin/env python3
"""Slate for Memex — local bridge.

Serves the Slate app from this folder on 127.0.0.1 and gives it one governed write path
into your vault: POST /api/capture files an entry into the vault's write dir (default
`inbox/`, or `write_dir:` from the vault's governance.yml) with the same provenance
frontmatter memexlab-mcp's capture_note writes, appends to .memexlab/log.jsonl, and —
only if you start it with --reindex — runs `memex reindex` afterwards.

Standard library only. Nothing leaves your machine: the server binds to loopback unless
you pass --host, and browser requests are accepted only from this origin and memexlab.xyz
(add more with --allow-origin). There is no code path that writes outside the write dir.

    python3 bridge.py --vault "~/Desktop/Memex/Wiki"            # app at http://127.0.0.1:7357
    python3 bridge.py --vault ~/vault --reindex                  # + `memex reindex` after each send
    python3 bridge.py --vault ~/vault --host 0.0.0.0             # reachable from your phone on the LAN
"""
from __future__ import annotations

import argparse
import datetime as dt
import itertools
import json
import pathlib
import re
import shlex
import subprocess
import sys
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

APP_DIR = pathlib.Path(__file__).resolve().parent
DEFAULT_WRITE_DIR = "inbox"
LOG_REL = pathlib.Path(".memexlab") / "log.jsonl"
MAX_BODY_BYTES = 2_000_000          # memex MAX_NOTE_BYTES
MAX_REQUEST_BYTES = 4_000_000
DEFAULT_ORIGINS = ("https://memexlab.xyz", "https://www.memexlab.xyz")
_SAFE_PATH = re.compile(r"^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*\.md$")


def slugify(title: str) -> str:
    """Mirrors memexlab-mcp governance._slugify."""
    slug = re.sub(r"[^a-z0-9]+", "-", title.casefold()).strip("-")
    return slug[:80].rstrip("-") or "note"


def yq(s: str) -> str:
    """Double-quoted YAML scalar via JSON escaping (valid YAML, injection-safe)."""
    return json.dumps(str(s), ensure_ascii=False)


def write_dir(vault: pathlib.Path) -> str:
    gov = vault / "governance.yml"
    if gov.is_file():
        for line in gov.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^write_dir:\s*[\"']?([^\"'#\n]+)", line)
            if m and m.group(1).strip():
                return m.group(1).strip().strip("/")
    return DEFAULT_WRITE_DIR


def render(entry: dict, wd: str) -> str:
    lines = ["---", f"title: {yq(entry['title'])}", f"status: {yq(wd)}",
             f"captured_by: {yq(entry['captured_by'])}", f"captured_at: {yq(entry['captured_at'])}"]
    if entry["sources"]:
        lines.append("sources:")
        lines += [f"- {yq(s)}" for s in entry["sources"]]
    else:
        lines.append("sources: []")
    if entry["tags"]:
        lines.append("tags: [" + ", ".join(yq(t) for t in entry["tags"]) + "]")
    lines += ["---", "", entry["body"].rstrip(), ""]
    return "\n".join(lines)


def _str_list(v, limit=50) -> list[str]:
    if not isinstance(v, list):
        return []
    out = []
    for x in v[:limit]:
        if isinstance(x, str) and x.strip() and "\n" not in x:
            out.append(x.strip()[:500])
    return out


class Bridge:
    def __init__(self, vault: pathlib.Path, reindex_cmd: str | None):
        self.vault = vault.resolve()
        self.reindex_cmd = reindex_cmd
        if not self.vault.is_dir():
            raise SystemExit(f"vault is not a directory: {vault}")

    def target_dir(self) -> tuple[str, pathlib.Path]:
        wd = write_dir(self.vault)
        target = (self.vault / wd).resolve()
        if not target.is_relative_to(self.vault):
            raise PermissionError(f"write dir escapes vault: {wd}")
        return wd, target

    def info(self) -> dict:
        wd, _ = self.target_dir()
        return {"app": "slate-bridge", "vault": self.vault.name, "vault_path": str(self.vault),
                "write_dir": wd, "reindex": bool(self.reindex_cmd)}

    def capture(self, req: dict) -> dict:
        title = req.get("title")
        if not isinstance(title, str) or not title.strip():
            raise ValueError("title is required")
        title = title.strip()[:300]
        if "/" in title or "\\" in title or ".." in title:
            raise ValueError("title must not contain path separators")
        body = req.get("body", "")
        if not isinstance(body, str):
            raise ValueError("body must be a string")
        if len(body.encode("utf-8")) > MAX_BODY_BYTES:
            raise ValueError("body larger than 2 MB")
        agent = req.get("captured_by") if isinstance(req.get("captured_by"), str) else "slate"
        agent = re.sub(r"[^\w.-]+", "-", agent.strip())[:40] or "slate"
        now = dt.datetime.now().astimezone()
        captured_at = req.get("captured_at") if isinstance(req.get("captured_at"), str) and len(req.get("captured_at")) < 40 else now.isoformat(timespec="seconds")
        entry = {"title": title, "body": body, "tags": _str_list(req.get("tags")), "sources": _str_list(req.get("sources")),
                 "captured_by": agent, "captured_at": captured_at}

        wd, target = self.target_dir()
        target.mkdir(parents=True, exist_ok=True)

        # Overwrite a file this app wrote earlier (edit after send) — only inside the write dir.
        rel = None
        action = "capture_note"
        prev = req.get("path")
        if isinstance(prev, str) and _SAFE_PATH.match(prev):
            cand = (self.vault / prev).resolve()
            if cand.is_file() and cand.parent == target:
                rel, action = cand.relative_to(self.vault), "update_note"
        if rel is None:
            slug = slugify(title)
            stamp = now.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            for i in itertools.count():
                name = f"{slug}-{stamp}.md" if i == 0 else f"{slug}-{stamp}-{i}.md"
                cand = target / name
                if cand.resolve().parent != target:
                    raise PermissionError(f"write escapes boundary: {name}")
                if not cand.exists():
                    rel = cand.relative_to(self.vault)
                    break
        (self.vault / rel).write_text(render(entry, wd), encoding="utf-8")

        log_path = self.vault / LOG_REL
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"ts": now.isoformat(), "agent": agent, "action": action, "path": str(rel),
                                "title": title, "sources": entry["sources"]}, ensure_ascii=False) + "\n")

        result = {"ok": True, "path": str(rel), "action": action}
        if req.get("reindex"):
            result["reindex"] = self.reindex()
        return result

    def reindex(self) -> dict:
        if not self.reindex_cmd:
            return {"ran": False, "error": "bridge started without --reindex"}
        try:
            p = subprocess.run(shlex.split(self.reindex_cmd), cwd=self.vault, capture_output=True, text=True, timeout=600)
            tail = (p.stdout + p.stderr).strip().splitlines()[-5:]
            return {"ran": True, "ok": p.returncode == 0, "exit": p.returncode, "output": tail}
        except (OSError, subprocess.SubprocessError) as e:
            return {"ran": False, "error": str(e)}


def make_handler(bridge: Bridge, origins: set[str]):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(APP_DIR), **kw)

        # --- helpers ---
        def _origin_ok(self) -> bool:
            origin = self.headers.get("Origin")
            if origin is None:                       # curl / same-origin navigations
                return True
            host = self.headers.get("Host", "")
            return origin in origins or origin == f"http://{host}"

        def _cors(self):
            origin = self.headers.get("Origin")
            if origin and self._origin_ok():
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
                self.send_header("Access-Control-Allow-Private-Network", "true")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

        def _json(self, status: int, data: dict):
            raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self._cors()
            self.end_headers()
            self.wfile.write(raw)

        def end_headers(self):
            # The app's own files: keep the vault out of any shared cache, allow the SW scope.
            if not self.path.startswith("/api/"):
                self.send_header("Cache-Control", "no-cache")
            super().end_headers()

        def _fallback_page(self):
            # bridge.py was downloaded on its own: no app files beside it. Point at the hosted app.
            port = self.server.server_address[1]
            html = (
                "<!doctype html><meta charset=utf-8><title>Slate bridge</title>"
                "<body style='font:16px/1.6 -apple-system,Inter,sans-serif;background:#080c17;color:#e9eef7;max-width:620px;margin:60px auto;padding:0 20px'>"
                "<h1 style='font-size:1.4rem'>Slate bridge is running</h1>"
                f"<p>Vault: <code>{bridge.vault}</code> &rarr; <code>{bridge.target_dir()[0]}/</code></p>"
                "<p>The app files are not next to <code>bridge.py</code>, so open the hosted app and point it here:</p>"
                "<p><a style='color:#22d3ee' href='https://memexlab.xyz/notes/'>memexlab.xyz/notes</a> &rarr; Settings &rarr; Local bridge &rarr; "
                f"<code>http://127.0.0.1:{port}</code> &rarr; Test.</p>"
                "<p>Prefer everything local (Safari, offline)? Put <code>index.html</code>, <code>notes.css</code>, <code>notes.js</code>, "
                "<code>manifest.webmanifest</code> and <code>sw.js</code> from "
                "<a style='color:#22d3ee' href='https://github.com/btekmen/memexlab/tree/main/notes'>memexlab/notes</a> beside this script and reload.</p>"
            ).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)

        # --- routes ---
        def do_OPTIONS(self):
            if not self._origin_ok():
                self._json(HTTPStatus.FORBIDDEN, {"ok": False, "error": "origin not allowed"})
                return
            self.send_response(HTTPStatus.NO_CONTENT)
            self._cors()
            self.send_header("Access-Control-Max-Age", "600")
            self.end_headers()

        def do_GET(self):
            route = self.path.split("?")[0]
            if route.startswith("/assets/") and (APP_DIR.parent / "assets").is_dir():
                self.directory = str(APP_DIR.parent)          # the site's favicon, next to notes/
            elif route in ("/", "/index.html") and not (APP_DIR / "index.html").is_file():
                return self._fallback_page()
            if route == "/api/info":
                if not self._origin_ok():
                    return self._json(HTTPStatus.FORBIDDEN, {"ok": False, "error": "origin not allowed"})
                return self._json(HTTPStatus.OK, bridge.info())
            if self.path.startswith("/api/"):
                return self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "no such endpoint"})
            super().do_GET()

        def do_POST(self):
            if not self._origin_ok():
                return self._json(HTTPStatus.FORBIDDEN, {"ok": False, "error": "origin not allowed"})
            route = self.path.split("?")[0]
            if route not in ("/api/capture", "/api/reindex"):
                return self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "no such endpoint"})
            try:
                n = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                n = -1
            if n < 0 or n > MAX_REQUEST_BYTES:
                return self._json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"ok": False, "error": "request too large"})
            try:
                req = json.loads(self.rfile.read(n) or b"{}")
                if not isinstance(req, dict):
                    raise ValueError("JSON object expected")
            except (ValueError, UnicodeDecodeError) as e:
                return self._json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"bad JSON: {e}"})
            try:
                if route == "/api/reindex":
                    return self._json(HTTPStatus.OK, {"ok": True, "reindex": bridge.reindex()})
                return self._json(HTTPStatus.OK, bridge.capture(req))
            except (ValueError, PermissionError) as e:
                return self._json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(e)})
            except OSError as e:
                return self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": f"write failed: {e}"})

        def log_message(self, fmt, *args):
            if self.path.startswith("/api/"):
                sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % args))

    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vault", required=True, help="path to your memex vault (the folder holding inbox/)")
    ap.add_argument("--host", default="127.0.0.1", help="bind address (default loopback only)")
    ap.add_argument("--port", type=int, default=7357)
    ap.add_argument("--reindex", nargs="?", const="memex reindex", default=None, metavar="CMD",
                    help="run this command in the vault after each send (default: 'memex reindex')")
    ap.add_argument("--allow-origin", action="append", default=[], metavar="ORIGIN",
                    help="extra browser origin allowed to call the API (repeatable)")
    args = ap.parse_args(argv)

    bridge = Bridge(pathlib.Path(args.vault).expanduser(), args.reindex)
    origins = set(DEFAULT_ORIGINS) | set(args.allow_origin)
    origins |= {f"http://{h}:{args.port}" for h in ("127.0.0.1", "localhost")}
    if args.host not in ("127.0.0.1", "localhost"):
        print(f"! bound to {args.host}: anyone on your network who can reach this port can write to {bridge.vault.name}/{bridge.target_dir()[0]}/", file=sys.stderr)

    srv = ThreadingHTTPServer((args.host, args.port), make_handler(bridge, origins))
    wd, _ = bridge.target_dir()
    print(f"Slate for Memex bridge\n  app     http://{'127.0.0.1' if args.host == '0.0.0.0' else args.host}:{args.port}/\n"
          f"  vault   {bridge.vault}\n  writes  {wd}/  (+ .memexlab/log.jsonl)\n"
          f"  reindex {args.reindex or 'off (pass --reindex)'}\n  Ctrl-C to stop", file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()
