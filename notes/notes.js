/* Slate for Memex — notes.js
   Local-first capture. Entries live in this browser (IndexedDB) until you send one to your
   vault through: (1) a vault folder picked with the File System Access API, (2) bridge.py
   running on 127.0.0.1, or (3) a plain .md download. A sent entry is written as
   <write_dir>/<slug>-<UTC stamp>.md with the same provenance frontmatter memexlab-mcp's
   capture_note writes, and appended to .memexlab/log.jsonl. No analytics, no other network. */
'use strict';

const DEFAULT_AGENT = 'slate';
const DEFAULT_BRIDGE = 'http://127.0.0.1:7357';
const SETTINGS_KEY = 'slate-settings';
const MAX_BODY = 2_000_000; // memex MAX_NOTE_BYTES

const $ = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => Array.from(el.querySelectorAll(sel));

/* ---------------- settings ---------------- */
const DEFAULTS = { method: 'auto', bridge: DEFAULT_BRIDGE, reindex: false, lang: '', defaultTags: '', agent: DEFAULT_AGENT, preview: false };
function loadSettings() {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}') }; } catch { return { ...DEFAULTS }; }
}
function saveSettings() { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch { /* private mode */ } }
let settings = loadSettings();

/* ---------------- IndexedDB ---------------- */
const dbp = new Promise((resolve, reject) => {
  const req = indexedDB.open('memex-slate', 1);
  req.onupgradeneeded = () => {
    const db = req.result;
    if (!db.objectStoreNames.contains('notes')) db.createObjectStore('notes', { keyPath: 'id' });
    if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv');
  };
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});
async function tx(store, mode, fn) {
  const db = await dbp;
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, mode);
    const req = fn(t.objectStore(store));
    t.oncomplete = () => resolve(req ? req.result : undefined);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}
const db = {
  all: () => tx('notes', 'readonly', (s) => s.getAll()),
  put: (n) => tx('notes', 'readwrite', (s) => s.put(n)),
  del: (id) => tx('notes', 'readwrite', (s) => s.delete(id)),
  clear: () => tx('notes', 'readwrite', (s) => s.clear()),
  kvGet: (k) => tx('kv', 'readonly', (s) => s.get(k)),
  kvSet: (k, v) => tx('kv', 'readwrite', (s) => s.put(v, k)),
  kvDel: (k) => tx('kv', 'readwrite', (s) => s.delete(k)),
};

/* ---------------- helpers ---------------- */
const pad = (n) => String(n).padStart(2, '0');
function isoLocal(d) {
  const off = -d.getTimezoneOffset(); const a = Math.abs(off);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}${off >= 0 ? '+' : '-'}${pad(Math.floor(a / 60))}:${pad(a % 60)}`;
}
function stampUtc(d) {
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
}
// Mirrors memexlab-mcp governance._slugify: [^a-z0-9]+ -> "-", trimmed, <= 80 chars.
function slugify(title) {
  const s = String(title).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80).replace(/-+$/, '');
  return s || 'note';
}
// JSON string escaping is valid YAML double-quoted scalar syntax.
const yq = (s) => JSON.stringify(String(s));
const splitList = (s) => String(s || '').split(/[,\n]/).map((x) => x.trim()).filter(Boolean);
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));
function dayLabel(ts) {
  const d = new Date(ts); const today = new Date(); const y = new Date(); y.setDate(today.getDate() - 1);
  const same = (a, b) => a.toDateString() === b.toDateString();
  if (same(d, today)) return 'Today';
  if (same(d, y)) return 'Yesterday';
  return d.toLocaleDateString(undefined, { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' });
}
function defaultTitle(d) { return d.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()); }
function escapeHtml(s) { return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

let toastTimer;
function toast(msg, bad = false) {
  const el = $('#toast'); el.textContent = msg; el.classList.toggle('bad', bad); el.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { el.hidden = true; }, bad ? 5000 : 2600);
}

/* ---------------- markdown (frontmatter + body) ---------------- */
function noteWriteDir() { return vault.writeDir || 'inbox'; }
function buildMarkdown(note, when = new Date()) {
  const lines = ['---', `title: ${yq(note.title || 'Untitled')}`, `status: ${yq(noteWriteDir())}`, `captured_by: ${yq(settings.agent || DEFAULT_AGENT)}`, `captured_at: ${yq(isoLocal(when))}`];
  const src = splitList(note.sources);
  lines.push(src.length ? 'sources:' : 'sources: []');
  src.forEach((s) => lines.push(`- ${yq(s)}`));
  const tags = splitList(note.tags);
  if (tags.length) lines.push(`tags: [${tags.map(yq).join(', ')}]`);
  lines.push('---', '', (note.body || '').replace(/\s+$/, ''), '');
  return lines.join('\n');
}
function noteFilename(note, when) {
  if (note.sent && note.sent.name) return note.sent.name;
  return `${slugify(note.title || 'Untitled')}-${stampUtc(when)}.md`;
}

/* ---------------- tiny markdown preview ---------------- */
function inline(s) {
  s = escapeHtml(s);
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  s = s.replace(/\[\[([^\]|]+)(?:\|([^\]]*))?\]\]/g, (_, t, l) => `<span class="wikilink">[[${l || t}]]</span>`);
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>').replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>').replace(/(^|\s)_([^_\n]+)_/g, '$1<em>$2</em>');
  s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" rel="noopener noreferrer" target="_blank">$1</a>');
  s = s.replace(/(^|\s)(https?:\/\/[^\s<]+)/g, '$1<a href="$2" rel="noopener noreferrer" target="_blank">$2</a>');
  return s;
}
function renderMarkdown(md) {
  const out = []; const lines = md.split('\n'); let i = 0;
  const para = [];
  const flush = () => { if (para.length) { out.push(`<p>${inline(para.join(' '))}</p>`); para.length = 0; } };
  while (i < lines.length) {
    const l = lines[i];
    if (/^```/.test(l)) { flush(); const buf = []; i++; while (i < lines.length && !/^```/.test(lines[i])) buf.push(lines[i++]); i++; out.push(`<pre><code>${escapeHtml(buf.join('\n'))}</code></pre>`); continue; }
    const h = /^(#{1,3})\s+(.*)$/.exec(l);
    if (h) { flush(); out.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`); i++; continue; }
    if (/^>\s?/.test(l)) { flush(); const buf = []; while (i < lines.length && /^>\s?/.test(lines[i])) buf.push(lines[i++].replace(/^>\s?/, '')); out.push(`<blockquote>${inline(buf.join(' '))}</blockquote>`); continue; }
    if (/^\s*[-*+]\s+/.test(l) || /^\s*\d+[.)]\s+/.test(l)) {
      flush(); const ordered = /^\s*\d+[.)]\s+/.test(l); const items = [];
      while (i < lines.length && (/^\s*[-*+]\s+/.test(lines[i]) || /^\s*\d+[.)]\s+/.test(lines[i]))) {
        let t = lines[i++].replace(/^\s*([-*+]|\d+[.)])\s+/, '');
        let box = '';
        t = t.replace(/^\[([ xX])\]\s*/, (_, c) => { box = `<input type="checkbox" disabled${c.trim() ? ' checked' : ''}>`; return ''; });
        items.push(`<li>${box}${inline(t)}</li>`);
      }
      out.push(`<${ordered ? 'ol' : 'ul'}>${items.join('')}</${ordered ? 'ol' : 'ul'}>`); continue;
    }
    if (/^\s*(-{3,}|\*{3,})\s*$/.test(l)) { flush(); out.push('<hr>'); i++; continue; }
    if (!l.trim()) { flush(); i++; continue; }
    para.push(l); i++;
  }
  flush(); return out.join('\n');
}

/* ---------------- state ---------------- */
let notes = []; let current = null; let saveTimer = null; let dirty = false;
const vault = { handle: null, name: '', writeDir: 'inbox', perm: 'none' };
const bridge = { ok: false, info: null, checkedAt: 0 };

const els = {
  entries: $('#entries'), search: $('#search'), title: $('#title'), tags: $('#tags'), sources: $('#sources'), body: $('#editor-body'),
  preview: $('#preview'), empty: $('#empty'), wrap: $('#editor-body-wrap'), saveState: $('#save-state'), sentLine: $('#sent-line'),
  vaultDot: $('#vault-dot'), vaultText: $('#vault-text'), sidebar: $('#sidebar'), settings: $('#settings'),
};

/* ---------------- entry list ---------------- */
function renderList() {
  const q = els.search.value.trim().toLowerCase();
  const list = notes.filter((n) => !q || (n.title + ' ' + n.body + ' ' + n.tags).toLowerCase().includes(q))
    .sort((a, b) => b.updated - a.updated);
  els.entries.innerHTML = '';
  if (!list.length) { els.entries.innerHTML = `<div class="none">${q ? 'No entries match.' : 'No entries yet.'}</div>`; return; }
  let lastDay = '';
  for (const n of list) {
    const day = dayLabel(n.updated);
    if (day !== lastDay) { const d = document.createElement('div'); d.className = 'day'; d.textContent = day; els.entries.appendChild(d); lastDay = day; }
    const b = document.createElement('button'); b.type = 'button'; b.className = 'entry' + (current && n.id === current.id ? ' active' : '');
    const state = !n.sent ? 'unsent' : (n.sent.at < n.updated ? 'stale' : 'sent');
    const snippet = (n.body || '').replace(/\s+/g, ' ').trim().slice(0, 90) || 'Empty';
    b.innerHTML = `<div class="t"><span class="mark ${state}" title="${state === 'sent' ? 'Sent to vault' : state === 'stale' ? 'Edited since last send' : 'Not sent yet'}"></span><span>${escapeHtml(n.title || 'Untitled')}</span></div><div class="s">${escapeHtml(snippet)}</div>`;
    b.addEventListener('click', () => { openNote(n.id); els.sidebar.classList.remove('open'); });
    els.entries.appendChild(b);
  }
}

/* ---------------- editor ---------------- */
function openNote(id) {
  flushSave();
  current = notes.find((n) => n.id === id) || null;
  const has = !!current;
  els.empty.hidden = has; els.wrap.hidden = !has;
  if (!has) { renderList(); return; }
  els.title.value = current.title; els.tags.value = current.tags; els.sources.value = current.sources; els.body.value = current.body;
  renderSentLine(); renderPreview(); renderList();
  if (!current.body && !current.title) els.title.focus(); else els.body.focus();
}
function renderSentLine() {
  if (!current || !current.sent) { els.sentLine.hidden = true; return; }
  const s = current.sent; const stale = s.at < current.updated;
  els.sentLine.hidden = false;
  els.sentLine.innerHTML = `${stale ? 'Edited since last send · previously' : 'Sent'} ${escapeHtml(new Date(s.at).toLocaleString())} via ${escapeHtml(s.via)} → <code>${escapeHtml(s.path)}</code>`;
}
function renderPreview() {
  const on = settings.preview; $('#btn-preview').setAttribute('aria-pressed', String(on));
  els.preview.hidden = !on; els.body.hidden = on;
  if (on && current) els.preview.innerHTML = renderMarkdown(els.body.value) || '<p class="muted">Nothing to preview.</p>';
}
async function newNote() {
  flushSave();
  const now = Date.now();
  const n = { id: uid(), title: defaultTitle(new Date(now)), tags: settings.defaultTags || '', sources: '', body: '', created: now, updated: now, sent: null };
  notes.push(n); await db.put(n); openNote(n.id); els.title.select();
}
function scheduleSave() {
  if (!current) return;
  dirty = true; els.saveState.textContent = 'Editing…';
  clearTimeout(saveTimer); saveTimer = setTimeout(flushSave, 400);
}
function flushSave() {
  clearTimeout(saveTimer);
  if (!current || !dirty) return;
  current.title = els.title.value.trim(); current.tags = els.tags.value; current.sources = els.sources.value; current.body = els.body.value;
  current.updated = Date.now(); dirty = false;
  db.put(current).then(() => { els.saveState.textContent = 'Saved locally'; renderList(); renderSentLine(); }).catch((e) => { els.saveState.textContent = 'Save failed'; toast('Could not save: ' + e.message, true); });
}
async function deleteCurrent() {
  if (!current) return;
  if (!confirm(`Delete "${current.title || 'Untitled'}" from this browser? (Already-sent files in the vault are not touched.)`)) return;
  const id = current.id; notes = notes.filter((n) => n.id !== id); await db.del(id); current = null; dirty = false;
  openNote(notes.sort((a, b) => b.updated - a.updated)[0]?.id);
}

/* ---------------- delivery: vault folder (File System Access API) ---------------- */
const fsSupported = 'showDirectoryPicker' in window;
async function pickVault() {
  try {
    const h = await window.showDirectoryPicker({ mode: 'readwrite', id: 'memex-vault' });
    vault.handle = h; vault.name = h.name; vault.perm = 'granted';
    await db.kvSet('vault', h); await readWriteDir(); updateVaultStatus(); toast(`Vault folder: ${h.name}`);
  } catch (e) { if (e.name !== 'AbortError') toast('Could not open folder: ' + e.message, true); }
}
async function restoreVault() {
  if (!fsSupported) return;
  try {
    const h = await db.kvGet('vault'); if (!h) return;
    vault.handle = h; vault.name = h.name;
    vault.perm = await h.queryPermission({ mode: 'readwrite' });
    if (vault.perm === 'granted') await readWriteDir();
  } catch { /* handle gone */ }
}
async function ensureVaultPerm() {
  if (!vault.handle) return false;
  if (vault.perm !== 'granted') vault.perm = await vault.handle.requestPermission({ mode: 'readwrite' });
  if (vault.perm === 'granted') await readWriteDir();
  updateVaultStatus(); return vault.perm === 'granted';
}
async function readWriteDir() {
  vault.writeDir = 'inbox';
  try {
    const f = await vault.handle.getFileHandle('governance.yml'); const t = await (await f.getFile()).text();
    const m = /^write_dir:\s*["']?([^"'#\n]+)/m.exec(t); if (m && m[1].trim()) vault.writeDir = m[1].trim().replace(/^\/+|\/+$/g, '');
  } catch { /* no governance.yml */ }
}
async function dirAt(root, rel, create) {
  let d = root;
  for (const part of rel.split('/').filter(Boolean)) { if (part === '..') throw new Error('write dir escapes vault'); d = await d.getDirectoryHandle(part, { create }); }
  return d;
}
async function writeFile(dir, name, text) {
  const fh = await dir.getFileHandle(name, { create: true }); const w = await fh.createWritable(); await w.write(text); await w.close();
}
async function sendViaVault(note) {
  if (!(await ensureVaultPerm())) throw new Error('Vault folder permission not granted');
  const when = new Date(); const wd = noteWriteDir();
  const dir = await dirAt(vault.handle, wd, true);
  let name = noteFilename(note, when);
  const reuse = note.sent && note.sent.via === 'vault' && note.sent.name === name;
  if (!reuse) {
    const base = name.replace(/\.md$/, '');
    for (let i = 0; ; i++) {
      name = i === 0 ? `${base}.md` : `${base}-${i}.md`;
      try { await dir.getFileHandle(name); } catch { break; } // free name
    }
  }
  const text = buildMarkdown(note, when);
  await writeFile(dir, name, text);
  const path = `${wd}/${name}`;
  try {
    const logDir = await dirAt(vault.handle, '.memexlab', true);
    let prev = ''; try { prev = await (await (await logDir.getFileHandle('log.jsonl')).getFile()).text(); } catch { /* new log */ }
    const entry = { ts: when.toISOString(), agent: settings.agent || DEFAULT_AGENT, action: reuse ? 'update_note' : 'capture_note', path, title: note.title, sources: splitList(note.sources) };
    await writeFile(logDir, 'log.jsonl', prev + (prev && !prev.endsWith('\n') ? '\n' : '') + JSON.stringify(entry) + '\n');
  } catch { /* log is best-effort */ }
  return { via: 'vault', path, name };
}

/* ---------------- delivery: local bridge ---------------- */
function bridgeUrl() { return (settings.bridge || DEFAULT_BRIDGE).replace(/\/+$/, ''); }
async function probeBridge(quiet = true) {
  try {
    const r = await fetch(bridgeUrl() + '/api/info', { signal: AbortSignal.timeout(1500), cache: 'no-store' });
    const info = await r.json();
    bridge.ok = !!info.vault; bridge.info = info; bridge.checkedAt = Date.now();
  } catch { bridge.ok = false; bridge.info = null; bridge.checkedAt = Date.now(); }
  updateVaultStatus();
  if (!quiet) toast(bridge.ok ? `Bridge OK → ${bridge.info.vault} (${bridge.info.write_dir}/)` : 'Bridge not reachable at ' + bridgeUrl(), !bridge.ok);
  return bridge.ok;
}
async function sendViaBridge(note) {
  const when = new Date();
  const payload = {
    title: note.title || 'Untitled', body: note.body || '', tags: splitList(note.tags), sources: splitList(note.sources),
    captured_by: settings.agent || DEFAULT_AGENT, captured_at: isoLocal(when),
    path: note.sent && note.sent.via === 'bridge' ? note.sent.path : null,
    reindex: !!settings.reindex,
  };
  const r = await fetch(bridgeUrl() + '/api/capture', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(60000) });
  const res = await r.json().catch(() => ({}));
  if (!r.ok || !res.ok) throw new Error(res.error || `bridge returned ${r.status}`);
  if (res.reindex && res.reindex.ran === false && settings.reindex) toast('Sent. Reindex skipped: ' + (res.reindex.error || 'not enabled on the bridge'), true);
  return { via: 'bridge', path: res.path, name: res.path.split('/').pop(), reindex: res.reindex };
}

/* ---------------- delivery: download ---------------- */
function downloadNote(note) {
  const when = new Date(); const name = noteFilename(note, when);
  const blob = new Blob([buildMarkdown(note, when)], { type: 'text/markdown;charset=utf-8' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  return { via: 'download', path: `${noteWriteDir()}/${name}`, name };
}

/* ---------------- send orchestration ---------------- */
async function deliver(note) {
  const m = settings.method;
  if (m === 'download') return downloadNote(note);
  if (m === 'bridge') return sendViaBridge(note);
  if (m === 'vault') { if (!fsSupported) throw new Error('This browser cannot write to folders — use the bridge or downloads'); if (!vault.handle) throw new Error('Choose a vault folder in Settings first'); return sendViaVault(note); }
  // auto
  if (bridge.ok || Date.now() - bridge.checkedAt > 20000) await probeBridge();
  if (bridge.ok) return sendViaBridge(note);
  if (vault.handle) return sendViaVault(note);
  return downloadNote(note);
}
async function sendNote(note, { silent = false } = {}) {
  if (!note) return false;
  if (new Blob([note.body || '']).size > MAX_BODY) { toast('Entry is larger than 2 MB — memex will not index it. Split it.', true); return false; }
  try {
    const res = await deliver(note);
    note.sent = { via: res.via, path: res.path, name: res.name, at: Date.now() };
    await db.put(note);
    if (!silent) {
      const extra = res.reindex && res.reindex.ran ? ' · reindexed' : '';
      toast(res.via === 'download' ? `Downloaded ${res.name} — drop it into ${noteWriteDir()}/` : `Sent → ${res.path}${extra}`);
    }
    return true;
  } catch (e) { toast('Send failed: ' + e.message, true); return false; }
}
async function sendCurrent() {
  flushSave(); if (!current) return;
  const btn = $('#btn-send'); btn.disabled = true;
  try { await sendNote(current); } finally { btn.disabled = false; renderSentLine(); renderList(); }
}
async function sendAllUnsent() {
  flushSave();
  const pending = notes.filter((n) => !n.sent || n.sent.at < n.updated).sort((a, b) => a.created - b.created);
  if (!pending.length) { toast('Nothing unsent.'); return; }
  if (settings.method === 'download' || (settings.method === 'auto' && !bridge.ok && !vault.handle && !(await probeBridge()))) {
    toast('Bulk send needs a vault folder or the bridge — downloads go one entry at a time.', true); return;
  }
  let ok = 0;
  for (const n of pending) { if (await sendNote(n, { silent: true })) ok++; else break; }
  toast(`Sent ${ok} of ${pending.length} entries.`, ok !== pending.length); renderList(); renderSentLine();
}

/* ---------------- status ---------------- */
function updateVaultStatus() {
  const m = settings.method; let cls = ''; let text = '';
  if (bridge.ok && (m === 'auto' || m === 'bridge')) { cls = 'ok'; text = `Bridge → ${bridge.info.vault}/${bridge.info.write_dir}`; }
  else if (m === 'bridge') { cls = 'bad'; text = 'Bridge not reachable'; }
  else if (vault.handle && (m === 'auto' || m === 'vault')) { cls = vault.perm === 'granted' ? 'ok' : 'warn'; text = vault.perm === 'granted' ? `Folder → ${vault.name}/${vault.writeDir}` : `Folder ${vault.name} — click to reconnect`; }
  else if (m === 'vault') { cls = 'warn'; text = 'No vault folder chosen'; }
  else if (m === 'download') { cls = 'ok'; text = 'Entries download as .md'; }
  else { cls = ''; text = 'Not connected — entries will download'; }
  els.vaultDot.className = 'dot ' + cls; els.vaultText.textContent = text;
  const picked = $('#vault-name'); if (picked) picked.textContent = vault.handle ? `${vault.name}/ (${vault.perm})` : 'none';
  $('#btn-forget-vault').hidden = !vault.handle;
  const bs = $('#bridge-state'); if (bs) bs.textContent = bridge.checkedAt ? (bridge.ok ? `OK · ${bridge.info.vault}` : 'not reachable') : '';
}

/* ---------------- dictation ---------------- */
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
let rec = null; let recOn = false;
function toggleDictation() {
  const btn = $('#btn-dictate');
  if (recOn) { rec.stop(); return; }
  if (!current) return;
  rec = new SR(); rec.continuous = true; rec.interimResults = true; if (settings.lang) rec.lang = settings.lang;
  let base = ''; let insertAt = 0;
  rec.onstart = () => { recOn = true; btn.classList.add('recording'); btn.setAttribute('aria-pressed', 'true'); base = els.body.value; insertAt = els.body.selectionEnd ?? base.length; };
  rec.onresult = (ev) => {
    let finalText = ''; let interim = '';
    for (let i = 0; i < ev.results.length; i++) { const t = ev.results[i][0].transcript; if (ev.results[i].isFinal) finalText += t + ' '; else interim += t; }
    const head = base.slice(0, insertAt); const tail = base.slice(insertAt);
    const sep = head && !/\s$/.test(head) ? ' ' : '';
    els.body.value = head + sep + finalText + interim + tail; scheduleSave();
  };
  rec.onerror = (ev) => { if (ev.error !== 'aborted' && ev.error !== 'no-speech') toast('Dictation: ' + ev.error, true); };
  rec.onend = () => { recOn = false; btn.classList.remove('recording'); btn.setAttribute('aria-pressed', 'false'); flushSave(); };
  try { rec.start(); } catch (e) { toast('Dictation unavailable: ' + e.message, true); }
}

/* ---------------- settings UI ---------------- */
function openSettings() {
  $$('input[name=method]').forEach((r) => { r.checked = r.value === settings.method; });
  $('#bridge-url').value = settings.bridge; $('#reindex').checked = !!settings.reindex; $('#lang').value = settings.lang;
  $('#default-tags').value = settings.defaultTags; $('#agent').value = settings.agent;
  $('#fs-unsupported').hidden = fsSupported; $('#btn-pick-vault').disabled = !fsSupported;
  updateVaultStatus(); els.settings.hidden = false;
  if (navigator.storage && navigator.storage.estimate) navigator.storage.estimate().then((e) => { $('#storage-info').textContent = `${notes.length} entries · ${(e.usage / 1024).toFixed(0)} KB used in this browser`; }).catch(() => {});
}
function closeSettings() { els.settings.hidden = true; saveSettings(); updateVaultStatus(); }

function exportAll() {
  flushSave();
  const blob = new Blob([JSON.stringify({ app: 'slate-for-memex', exported_at: isoLocal(new Date()), notes }, null, 2)], { type: 'application/json' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `slate-export-${stampUtc(new Date())}.json`; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}
async function importFile(file) {
  try {
    const data = JSON.parse(await file.text()); const list = Array.isArray(data) ? data : data.notes;
    if (!Array.isArray(list)) throw new Error('not a Slate export');
    let added = 0;
    for (const raw of list) {
      if (!raw || typeof raw !== 'object') continue;
      const n = { id: typeof raw.id === 'string' ? raw.id : uid(), title: String(raw.title || ''), tags: String(raw.tags || ''), sources: String(raw.sources || ''), body: String(raw.body || ''), created: Number(raw.created) || Date.now(), updated: Number(raw.updated) || Date.now(), sent: raw.sent && typeof raw.sent === 'object' ? raw.sent : null };
      if (notes.some((x) => x.id === n.id)) continue;
      notes.push(n); await db.put(n); added++;
    }
    renderList(); toast(`Imported ${added} entries.`);
  } catch (e) { toast('Import failed: ' + e.message, true); }
}
async function wipe() {
  if (!confirm('Delete every entry stored in this browser? Files already in your vault are not touched.')) return;
  await db.clear(); notes = []; current = null; dirty = false; openNote(null); closeSettings(); toast('Deleted.');
}

/* ---------------- wiring ---------------- */
function wire() {
  $('#btn-new').addEventListener('click', newNote); $('#btn-new-2').addEventListener('click', newNote);
  $('#btn-send').addEventListener('click', sendCurrent); $('#btn-send-all').addEventListener('click', sendAllUnsent);
  $('#btn-download').addEventListener('click', () => { flushSave(); if (current) { const r = downloadNote(current); toast(`Downloaded ${r.name}`); } });
  $('#btn-preview').addEventListener('click', () => { flushSave(); settings.preview = !settings.preview; saveSettings(); renderPreview(); });
  $('#btn-menu').addEventListener('click', () => els.sidebar.classList.toggle('open'));
  $('#btn-settings').addEventListener('click', openSettings); $('#btn-settings-2').addEventListener('click', openSettings); $('#btn-settings-close').addEventListener('click', closeSettings);
  els.settings.addEventListener('click', (e) => { if (e.target === els.settings) closeSettings(); });
  $('#vault-status').addEventListener('click', () => { if (vault.handle && vault.perm !== 'granted') ensureVaultPerm(); });

  for (const id of ['title', 'tags', 'sources', 'editor-body']) $('#' + id).addEventListener('input', scheduleSave);
  els.body.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') { e.preventDefault(); const s = els.body.selectionStart; els.body.setRangeText('  ', s, els.body.selectionEnd, 'end'); scheduleSave(); }
  });
  els.search.addEventListener('input', renderList);

  $$('input[name=method]').forEach((r) => r.addEventListener('change', () => { settings.method = r.value; saveSettings(); updateVaultStatus(); }));
  $('#btn-pick-vault').addEventListener('click', pickVault);
  $('#btn-forget-vault').addEventListener('click', async () => { await db.kvDel('vault'); vault.handle = null; vault.name = ''; vault.perm = 'none'; updateVaultStatus(); });
  $('#bridge-url').addEventListener('change', (e) => { settings.bridge = e.target.value.trim() || DEFAULT_BRIDGE; saveSettings(); bridge.checkedAt = 0; });
  $('#btn-probe').addEventListener('click', () => probeBridge(false));
  $('#reindex').addEventListener('change', (e) => { settings.reindex = e.target.checked; saveSettings(); });
  $('#lang').addEventListener('change', (e) => { settings.lang = e.target.value; saveSettings(); });
  $('#default-tags').addEventListener('change', (e) => { settings.defaultTags = e.target.value.trim(); saveSettings(); });
  $('#agent').addEventListener('change', (e) => { settings.agent = e.target.value.trim() || DEFAULT_AGENT; saveSettings(); });
  $('#btn-export').addEventListener('click', exportAll);
  $('#btn-import').addEventListener('click', () => $('#import-file').click());
  $('#import-file').addEventListener('change', (e) => { if (e.target.files[0]) importFile(e.target.files[0]); e.target.value = ''; });
  $('#btn-wipe').addEventListener('click', wipe);

  if (SR) { const b = $('#btn-dictate'); b.hidden = false; b.addEventListener('click', toggleDictation); }

  document.addEventListener('keydown', (e) => {
    const mod = e.metaKey || e.ctrlKey; if (!mod) { if (e.key === 'Escape' && !els.settings.hidden) closeSettings(); return; }
    if (e.key === 'n') { e.preventDefault(); newNote(); }
    else if (e.key === 'Enter') { e.preventDefault(); sendCurrent(); }
    else if (e.key === 'k') { e.preventDefault(); els.sidebar.classList.add('open'); els.search.focus(); }
    else if (e.key === '/') { e.preventDefault(); $('#btn-preview').click(); }
    else if (e.key === ',') { e.preventDefault(); els.settings.hidden ? openSettings() : closeSettings(); }
    else if (e.key === 'Backspace' && e.shiftKey) { e.preventDefault(); deleteCurrent(); }
    else if (e.key === 's') { e.preventDefault(); flushSave(); }
  });
  window.addEventListener('beforeunload', flushSave);
  document.addEventListener('visibilitychange', () => { if (document.hidden) flushSave(); });
}

/* ---------------- boot ---------------- */
(async function boot() {
  wire();
  // Served by bridge.py? Then the bridge is this origin.
  if (/^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]|\d+\.\d+\.\d+\.\d+)(:\d+)?$/.test(location.origin) && settings.bridge === DEFAULT_BRIDGE && !localStorage.getItem(SETTINGS_KEY)) {
    settings.bridge = location.origin; saveSettings();
  }
  try { notes = await db.all(); } catch (e) { toast('Storage unavailable: ' + e.message, true); notes = []; }
  await restoreVault();
  updateVaultStatus();
  const latest = notes.slice().sort((a, b) => b.updated - a.updated)[0];
  openNote(latest ? latest.id : null);
  probeBridge();
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('./sw.js').catch(() => {});
})();
