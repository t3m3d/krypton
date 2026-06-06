// kryptlink — URL shortener with click tracking + server-rendered QR codes.
// Node.js (Express + node:sqlite + qrcode). Pairs with kryptlink/ (the
// pure-Krypton implementation, kept as a showcase / future direction).
//
//   First time:
//     npm install
//     npm run init-db          (only for new DBs; existing ones migrate on boot)
//   Env:
//     KRYPTLINK_PASSWORD        bootstrap admin password (required)
//     KRYPTLINK_ADMIN_USERNAME  bootstrap admin username (default 'admin')
//     KRYPTLINK_DB              sqlite path (default: kryptlink.db)
//     KRYPTLINK_PUBLIC_HOST     short-URL base (default: http://localhost:8080)
//     KRYPTLINK_PUBLIC_DIR      static dir served at / (default: ./public)
//     PORT                      default 8080
//
//   Run:
//     npm start
//
// Routes:
//   GET  /                 → public landing (KRYPTLINK_PUBLIC_DIR/index.html)
//                            landing renders a compact login form, posted to /login
//   POST /login            → username + password → session cookie → /admin
//   POST /logout           → drop session
//   GET  /admin            → control panel (auth required)
//   POST /create           → new link (auth required, owned by current user)
//   GET  /stats/<code>     → click history (must own the link, or be admin)
//   GET  /qr/<code>.svg    → QR code for the short URL (public)
//   POST /users/create     → ADMIN ONLY — add a new account
//   GET  /<code>           → 302 + click log (bit.ly-style)

import express from "express";
import cookieParser from "cookie-parser";
import { DatabaseSync } from "node:sqlite";
import QRCode from "qrcode";
import { customAlphabet } from "nanoid";
import { createHmac, scryptSync, randomBytes, timingSafeEqual } from "node:crypto";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── Config ───────────────────────────────────────────────────────────
const PASSWORD       = process.env.KRYPTLINK_PASSWORD;
const ADMIN_USERNAME = process.env.KRYPTLINK_ADMIN_USERNAME || "admin";
const DB_PATH        = process.env.KRYPTLINK_DB              || "kryptlink.db";
const PUBLIC_HOST    = process.env.KRYPTLINK_PUBLIC_HOST     || "http://localhost:8080";
const PUBLIC_DIR     = process.env.KRYPTLINK_PUBLIC_DIR      || path.join(__dirname, "public");
const PORT           = Number(process.env.PORT) || 8080;

if (!PASSWORD) {
  console.error("kryptlink: KRYPTLINK_PASSWORD env var is required");
  process.exit(1);
}

// ── Password hashing (scrypt, built-in node:crypto) ──────────────────
function hashPassword(pw) {
  const salt = randomBytes(16);
  const hash = scryptSync(pw, salt, 64);
  return salt.toString("hex") + ":" + hash.toString("hex");
}
function verifyPassword(pw, stored) {
  try {
    const [saltHex, hashHex] = stored.split(":");
    const salt = Buffer.from(saltHex, "hex");
    const expected = Buffer.from(hashHex, "hex");
    const actual = scryptSync(pw, salt, 64);
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch { return false; }
}

// ── DB + migrations ──────────────────────────────────────────────────
const db = new DatabaseSync(DB_PATH);
db.exec("PRAGMA journal_mode = WAL");
db.exec("PRAGMA foreign_keys = ON");

// Idempotent boot-time migration (safe to run on every start).
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    is_admin      INTEGER NOT NULL DEFAULT 0,
    created_at    INTEGER NOT NULL
  );
`);
const linkCols = db.prepare("PRAGMA table_info(links)").all();
if (!linkCols.some((c) => c.name === "user_id")) {
  db.exec(`ALTER TABLE links ADD COLUMN user_id INTEGER REFERENCES users(id)`);
}
const userCols = db.prepare("PRAGMA table_info(users)").all();
if (!userCols.some((c) => c.name === "disabled")) {
  db.exec(`ALTER TABLE users ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0`);
}
if (!userCols.some((c) => c.name === "link_limit")) {
  // 0 means unlimited; default for new non-admin users is 100. Admins
  // are exempt from quotas regardless of column value.
  db.exec(`ALTER TABLE users ADD COLUMN link_limit INTEGER NOT NULL DEFAULT 100`);
}

// Audit log captures who-did-what-to-what, with IP + timestamp, so
// admin disputes can be settled and abuse can be traced.
db.exec(`
  CREATE TABLE IF NOT EXISTS audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          INTEGER NOT NULL,
    actor_id    INTEGER,           -- nullable for failed logins (no session)
    actor_name  TEXT,               -- snapshot at event time (survives user deletion)
    action      TEXT NOT NULL,      -- e.g. 'login.ok', 'link.create', 'user.disable'
    detail      TEXT,               -- free-form context (short URL, target username, etc.)
    ip          TEXT
  );
  CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit_log(ts DESC);
  CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log(actor_id);
`);
// Bootstrap admin if no admin user exists.
const anyAdmin = db.prepare("SELECT id FROM users WHERE is_admin = 1 LIMIT 1").get();
if (!anyAdmin) {
  const stmt = db.prepare("INSERT INTO users(username, password_hash, is_admin, created_at) VALUES (?, ?, 1, ?)");
  const result = stmt.run(ADMIN_USERNAME, hashPassword(PASSWORD), Math.floor(Date.now() / 1000));
  const adminId = Number(result.lastInsertRowid);
  // Backfill existing links to admin so the admin can see them.
  db.prepare("UPDATE links SET user_id = ? WHERE user_id IS NULL").run(adminId);
  console.log(`kryptlink: bootstrap admin '${ADMIN_USERNAME}' created (id=${adminId})`);
}

// ── Prepared statements ──────────────────────────────────────────────
const stmtLinkByCode      = db.prepare("SELECT * FROM links WHERE code = ?");
const stmtInsertLink      = db.prepare("INSERT INTO links(code, url, created_at, note, user_id) VALUES (?, ?, ?, ?, ?)");
const stmtRecentAllLinks  = db.prepare("SELECT l.*, u.username AS owner FROM links l LEFT JOIN users u ON u.id = l.user_id ORDER BY l.created_at DESC LIMIT ?");
const stmtRecentUserLinks = db.prepare("SELECT l.*, u.username AS owner FROM links l LEFT JOIN users u ON u.id = l.user_id WHERE l.user_id = ? ORDER BY l.created_at DESC LIMIT ?");
const stmtInsertClick     = db.prepare("INSERT INTO clicks(code, clicked_at, ip, user_agent, referrer) VALUES (?, ?, ?, ?, ?)");
const stmtClicksByCode    = db.prepare("SELECT * FROM clicks WHERE code = ? ORDER BY clicked_at DESC LIMIT ?");
const stmtCountClicksCode = db.prepare("SELECT COUNT(*) AS n FROM clicks WHERE code = ?");
const stmtUserByName      = db.prepare("SELECT * FROM users WHERE username = ?");
const stmtUserById        = db.prepare("SELECT * FROM users WHERE id = ?");
const stmtAllUsers        = db.prepare("SELECT id, username, is_admin, disabled, created_at FROM users ORDER BY created_at ASC");
const stmtInsertUser      = db.prepare("INSERT INTO users(username, password_hash, is_admin, created_at) VALUES (?, ?, ?, ?)");
const stmtUpdateUserPw    = db.prepare("UPDATE users SET password_hash = ? WHERE id = ?");
const stmtToggleUserDis   = db.prepare("UPDATE users SET disabled = ? WHERE id = ?");
const stmtDeleteUser      = db.prepare("DELETE FROM users WHERE id = ?");
const stmtClearUserLinks  = db.prepare("UPDATE links SET user_id = NULL WHERE user_id = ?");
const stmtCountUserLinks  = db.prepare("SELECT COUNT(*) AS n FROM links WHERE user_id = ?");
const stmtSetUserLimit    = db.prepare("UPDATE users SET link_limit = ? WHERE id = ?");
const stmtInsertAudit     = db.prepare("INSERT INTO audit_log(ts, actor_id, actor_name, action, detail, ip) VALUES (?, ?, ?, ?, ?, ?)");
const stmtRecentAudit     = db.prepare("SELECT * FROM audit_log ORDER BY ts DESC LIMIT ?");

// Append an audit entry. actor may be null for failed-login events
// (the user doesn't have a session yet). detail is a free-form string.
function logAudit(actor, action, detail, req) {
  stmtInsertAudit.run(
    Math.floor(Date.now() / 1000),
    actor ? actor.id : null,
    actor ? actor.username : (req && req.body && req.body.username) || null,
    action,
    detail || null,
    (req && req.ip) || null,
  );
}

// Returns { ok, used, limit } for a user. limit === 0 means unlimited
// (admin or admin-bumped non-admin). Admins are always unlimited.
function checkLinkQuota(user) {
  if (user.is_admin) return { ok: true, used: stmtCountUserLinks.get(user.id).n, limit: 0 };
  const used = stmtCountUserLinks.get(user.id).n;
  const limit = user.link_limit | 0;
  if (limit === 0) return { ok: true, used, limit: 0 };
  return { ok: used < limit, used, limit };
}

// ── Codes ────────────────────────────────────────────────────────────
const CODE_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const nanoid = customAlphabet(CODE_ALPHABET, 6);

const RESERVED = new Set([
  "", "admin", "login", "logout", "create", "stats", "qr", "users",
  "icons", "banner",
  "index.html", "index.htm", "favicon.ico", "robots.txt",
  "sitemap.xml", "humans.txt", "default.htm", "default.html",
  ".well-known",
]);

function genUniqueCode() {
  for (let i = 0; i < 8; i++) {
    const c = nanoid();
    if (!stmtLinkByCode.get(c)) return c;
  }
  throw new Error("couldn't allocate a unique code in 8 tries");
}

// ── Rate limiting ────────────────────────────────────────────────────
// Simple in-memory sliding-window buckets. State is per-process; OK for
// a single-instance deploy. For multi-instance scale this should move
// to SQLite or Redis. Each bucket: key → [{ ts: ms }] list (timestamps
// of recent hits). On each check we prune entries older than the
// window and compare count to the limit.
const _buckets = new Map();
function rateLimit(key, windowMs, max) {
  const now = Date.now();
  let arr = _buckets.get(key);
  if (!arr) { arr = []; _buckets.set(key, arr); }
  // Prune old
  while (arr.length && arr[0] < now - windowMs) arr.shift();
  if (arr.length >= max) return false;
  arr.push(now);
  return true;
}
// Best-effort GC so the Map doesn't grow without bound.
setInterval(() => {
  const cutoff = Date.now() - 24 * 3600 * 1000;
  for (const [k, arr] of _buckets) {
    while (arr.length && arr[0] < cutoff) arr.shift();
    if (arr.length === 0) _buckets.delete(k);
  }
}, 60 * 60 * 1000).unref();

// ── CSRF tokens ──────────────────────────────────────────────────────
// Stateless: token = HMAC(username|csrf-namespace, secret), truncated.
// Same-per-user (no rotation), good enough for the threat model — an
// attacker forging a cross-site POST can't read the user's cookie or
// guess the secret. Included as a hidden field in every authed POST
// form; the verifyCSRF middleware rejects mismatches.
function csrfTokenFor(user) {
  return createHmac("sha256", SESSION_SECRET).update(user.username + "|csrf").digest("hex").slice(0, 32);
}
function verifyCSRF(req, user) {
  if (!user) return false;
  const sent = req.body && req.body._csrf;
  const expected = csrfTokenFor(user);
  if (!sent || sent.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(sent), Buffer.from(expected));
}

// ── Session cookie (HMAC-signed username) ────────────────────────────
const SESSION_COOKIE = "kryptlink";
const SESSION_SECRET = scryptSync(PASSWORD, "kryptlink-session-salt", 32);

function signToken(username) {
  const sig = createHmac("sha256", SESSION_SECRET).update(username).digest("hex").slice(0, 32);
  return `${username}.${sig}`;
}
function verifyToken(token) {
  if (!token || typeof token !== "string") return null;
  const dot = token.lastIndexOf(".");
  if (dot <= 0) return null;
  const username = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = createHmac("sha256", SESSION_SECRET).update(username).digest("hex").slice(0, 32);
  // length-safe compare
  if (sig.length !== expected.length) return null;
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  return timingSafeEqual(a, b) ? username : null;
}
function getUser(req) {
  const username = verifyToken(req.cookies[SESSION_COOKIE]);
  if (!username) return null;
  const u = stmtUserByName.get(username);
  if (!u || u.disabled) return null;
  return u;
}

// ── Express setup ────────────────────────────────────────────────────
const app = express();
app.set("trust proxy", true);
app.use(cookieParser());
app.use(express.urlencoded({ extended: false }));

// ── HTML helpers ─────────────────────────────────────────────────────
const escapeHtml = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]));

// Per-page CSS injected into every body — covers the form / table /
// .pill / .created styles that aren't in the shared shell. The shell
// (public/index.html) handles fonts + cosmic background + banner +
// parallax + .login + .feature + responsive grid.
const PAGE_CSS = `<style>
h1{color:var(--accent);margin:.5em 0 .2em}
h2{color:var(--fg);margin:1.5em 0 .4em;font-size:1.15em}
input,button,textarea{font:inherit;padding:.5em;margin:.25em 0;border:1px solid color-mix(in srgb,var(--muted) 40%,transparent);border-radius:5px}
input[type=text],input[type=url],input[type=password]{width:100%;box-sizing:border-box;background:color-mix(in srgb,var(--bg-soft) 90%,transparent);color:var(--fg)}
.pageform label{display:block;color:var(--muted);font-size:.85em;margin-top:.6em}
.pageform button{background:var(--accent);color:white;border:none;cursor:pointer;padding:.55em 1.1em;font-weight:600}
.pageform button:hover{background:var(--accent-dim)}
button[disabled]{opacity:.55;cursor:not-allowed}
table{border-collapse:collapse;width:100%;margin-top:1em;font-size:.9em;background:color-mix(in srgb,var(--bg-soft) 70%,transparent);border-radius:6px;overflow:hidden}
th,td{padding:.55em .7em;text-align:left;border-bottom:1px solid color-mix(in srgb,var(--muted) 25%,transparent);vertical-align:top}
th{background:color-mix(in srgb,var(--bg-soft) 95%,transparent);color:var(--accent);font-weight:600;font-size:.85em;text-transform:uppercase;letter-spacing:.04em}
tr:last-child td{border-bottom:none}
a{color:var(--accent)}
a:hover{color:var(--frost)}
code{background:color-mix(in srgb,var(--accent) 15%,transparent);padding:.1em .3em;border-radius:3px;font-size:.9em}
.muted{color:var(--muted);font-size:.9em}
.ok{color:#7fdc8e}
.bad{color:#ff8585}
.pill{display:inline-block;padding:.1em .55em;border-radius:1em;background:var(--accent);color:white;font-size:.7em;vertical-align:middle;letter-spacing:.03em}
.pageform{margin-bottom:1em}
.created{display:flex;gap:1.2em;align-items:center;padding:1.1em;margin:.5em 0 1.5em;border:1px solid rgba(125,184,255,0.3);border-radius:10px;background:color-mix(in srgb,var(--bg-soft) 75%,transparent);backdrop-filter:blur(10px);box-shadow:0 0 30px rgba(125,184,255,0.1)}
.created-qr{width:128px;height:128px;background:white;padding:.4em;border-radius:6px;flex-shrink:0}
.created-body{flex:1;min-width:0}
.created-body .short{font-size:1.2em;word-break:break-all}
.copy-btn{font-size:.8em;padding:.3em .8em;margin-left:.5em;background:color-mix(in srgb,var(--accent) 20%,transparent);color:var(--frost);border:1px solid color-mix(in srgb,var(--accent) 35%,transparent);border-radius:4px;cursor:pointer}
.copy-btn:hover{background:color-mix(in srgb,var(--accent) 30%,transparent)}
.userbadge{color:var(--muted);font-size:.55em;font-weight:normal;vertical-align:middle;margin-left:.4em}
.logout-form{margin-top:2.5em}
.logout-form button{background:transparent;color:var(--muted);border:1px solid color-mix(in srgb,var(--muted) 30%,transparent);padding:.45em 1em;border-radius:5px;cursor:pointer}
.logout-form button:hover{color:var(--frost);border-color:var(--accent)}
</style>`;

// ── Shared shell template ────────────────────────────────────────────
// Loaded once at startup. The shell is public/index.html with a
// "<!-- BODY -->" marker right after the <main>+banner; we split it
// here into PRE + POST halves and any page renders by sandwiching its
// content between them. The shell carries: cosmic bg layers, banner,
// parallax script, font/color shell. Each page adds PAGE_CSS for its
// own form/table styling.
let SHELL_PRE = "";
let SHELL_POST = "";
function loadShell() {
  const tpl = fs.readFileSync(path.join(PUBLIC_DIR, "index.html"), "utf8");
  const marker = "<!-- BODY -->";
  const idx = tpl.indexOf(marker);
  if (idx < 0) {
    console.error("kryptlink: public/index.html missing <!-- BODY --> marker");
    process.exit(1);
  }
  SHELL_PRE = tpl.slice(0, idx);
  SHELL_POST = tpl.slice(idx + marker.length);
}
loadShell();

function renderShell(content) {
  return SHELL_PRE + PAGE_CSS + content + SHELL_POST;
}

function pageAdminBody(user, msg) {
  const links = user.is_admin
    ? stmtRecentAllLinks.all(100)
    : stmtRecentUserLinks.all(user.id, 100);

  const linkRows = links.length
    ? links.map((l) => {
        const short = `${PUBLIC_HOST}/${l.code}`;
        const date = new Date(l.created_at * 1000).toISOString().slice(0, 10);
        const ownerCell = user.is_admin
          ? `<td>${escapeHtml(l.owner || "—")}</td>`
          : "";
        return `<tr>
          <td><a href="${escapeHtml(short)}">${escapeHtml(l.code)}</a></td>
          <td><a href="${escapeHtml(l.url)}">${escapeHtml(l.url)}</a></td>
          ${ownerCell}
          <td>${date}</td>
          <td>${escapeHtml(l.note || "")}</td>
          <td><a href="/stats/${encodeURIComponent(l.code)}">stats</a> · <a href="/qr/${encodeURIComponent(l.code)}.svg">qr</a></td>
        </tr>`;
      }).join("")
    : `<tr><td colspan="${user.is_admin ? 6 : 5}" class="muted">no links yet</td></tr>`;

  const linkHeader = user.is_admin
    ? `<tr><th>Short</th><th>Destination</th><th>Owner</th><th>Created</th><th>Note</th><th></th></tr>`
    : `<tr><th>Short</th><th>Destination</th><th>Created</th><th>Note</th><th></th></tr>`;

  let usersSection = "";
  if (user.is_admin) {
    const users = stmtAllUsers.all();
    const uRows = users.map((u) => {
      const date = new Date(u.created_at * 1000).toISOString().slice(0, 10);
      return `<tr>
        <td>${escapeHtml(u.username)} ${u.is_admin ? '<span class="pill">admin</span>' : ""}</td>
        <td>${date}</td>
      </tr>`;
    }).join("");
    const csrf = csrfTokenFor(user);
    const adminUsers = stmtAllUsers.all();
    const adminUserRows = adminUsers.map((u) => {
      if (u.id === user.id) return ""; // skip self — managed in own section
      const linkCount = stmtCountUserLinks.get(u.id).n;
      const date = new Date(u.created_at * 1000).toISOString().slice(0, 10);
      const limitDisp = (u.link_limit | 0) === 0 ? "∞" : u.link_limit;
      return `<tr>
        <td>${escapeHtml(u.username)} ${u.is_admin ? '<span class="pill">admin</span>' : ""} ${u.disabled ? '<span class="pill" style="background:#a44">disabled</span>' : ""}</td>
        <td>${date}</td>
        <td>${linkCount} / ${limitDisp}</td>
        <td>
          <form method="POST" action="/users/toggle" style="display:inline;margin:0">
            <input type="hidden" name="_csrf" value="${csrf}">
            <input type="hidden" name="user_id" value="${u.id}">
            <button type="submit" class="copy-btn">${u.disabled ? "enable" : "disable"}</button>
          </form>
          <form method="POST" action="/users/set_limit" style="display:inline;margin:0">
            <input type="hidden" name="_csrf" value="${csrf}">
            <input type="hidden" name="user_id" value="${u.id}">
            <input type="number" name="link_limit" value="${u.link_limit | 0}" min="0" max="100000" style="width:6em;font-size:.85em;padding:.2em">
            <button type="submit" class="copy-btn">set cap</button>
          </form>
          <form method="POST" action="/users/delete" style="display:inline;margin:0" onsubmit="return confirm('Delete ${escapeHtml(u.username)}? Their links will be kept but un-owned.')">
            <input type="hidden" name="_csrf" value="${csrf}">
            <input type="hidden" name="user_id" value="${u.id}">
            <button type="submit" class="copy-btn" style="border-color:#a44;color:#ff8585">delete</button>
          </form>
        </td>
      </tr>`;
    }).join("");

    // Audit log — most recent 50 entries.
    const auditRows = stmtRecentAudit.all(50).map((a) => {
      const when = new Date(a.ts * 1000).toISOString().replace("T", " ").slice(0, 19);
      return `<tr>
        <td>${when}</td>
        <td>${escapeHtml(a.actor_name || "—")}</td>
        <td><code>${escapeHtml(a.action)}</code></td>
        <td>${escapeHtml(a.detail || "")}</td>
        <td class="muted">${escapeHtml(a.ip || "")}</td>
      </tr>`;
    }).join("") || `<tr><td colspan="5" class="muted">no events yet</td></tr>`;
    var auditSection = `
      <h2>Audit log <span class="muted" style="font-size:.6em;font-weight:normal">(last 50 events)</span></h2>
      <table>
        <tr><th>When (UTC)</th><th>Actor</th><th>Action</th><th>Detail</th><th>IP</th></tr>
        ${auditRows}
      </table>`;
    usersSection = `
      <h2>Users</h2>
      <table>
        <tr><th>User</th><th>Joined</th><th>Links / cap</th><th></th></tr>
        ${adminUserRows || `<tr><td colspan="4" class="muted">no other users yet</td></tr>`}
      </table>
      <h3 style="margin-top:1.5em;font-size:1em;color:var(--accent)">Create user</h3>
      <form method="POST" action="/users/create" class="pageform">
        <input type="hidden" name="_csrf" value="${csrf}">
        <label>New username <input type="text" name="username" pattern="[A-Za-z0-9_-]{2,32}" required></label>
        <label>Password <input type="password" name="password" minlength="8" required></label>
        <label><input type="checkbox" name="is_admin" value="1"> grant admin</label>
        <button type="submit">Create user</button>
      </form>
      <h3 style="margin-top:1.5em;font-size:1em;color:var(--accent)">Reset another user's password</h3>
      <form method="POST" action="/users/reset_password" class="pageform">
        <input type="hidden" name="_csrf" value="${csrf}">
        <label>Username <input type="text" name="username" pattern="[A-Za-z0-9_-]{2,32}" required></label>
        <label>New password <input type="password" name="password" minlength="8" required></label>
        <button type="submit">Reset password</button>
      </form>`;
  }

  const csrf = csrfTokenFor(user);
  const myQuota = checkLinkQuota(user);
  const quotaBadge = myQuota.limit === 0
    ? `<span class="muted">${myQuota.used} links</span>`
    : `<span class="${myQuota.ok ? "muted" : "bad"}">${myQuota.used} / ${myQuota.limit} links used</span>`;
  return `
    <h1>${user.is_admin ? "Admin" : "Dashboard"} <span class="userbadge">${escapeHtml(user.username)}${user.is_admin ? " · admin" : ""}</span></h1>
    ${msg ? `<div>${msg}</div>` : ""}
    <p style="margin-top:.4em">${quotaBadge}</p>
    <h2>Shorten a URL</h2>
    <form method="POST" action="/create" class="pageform">
      <input type="hidden" name="_csrf" value="${csrf}">
      <label>URL <input type="url" name="url" placeholder="https://example.com/long/path" required></label>
      <label>Custom code (optional) <input type="text" name="code" placeholder="launch" pattern="[A-Za-z0-9_\\-]{1,32}"></label>
      <label>Note (optional) <input type="text" name="note" placeholder="Q4 launch announcement"></label>
      <button type="submit">Shorten</button>
    </form>
    <h2>${user.is_admin ? "All links" : "Your links"}</h2>
    <table>
      ${linkHeader}
      ${linkRows}
    </table>
    ${usersSection}
    ${user.is_admin ? auditSection : ""}
    <h2>Your account</h2>
    <form method="POST" action="/password" class="pageform">
      <input type="hidden" name="_csrf" value="${csrf}">
      <label>Current password <input type="password" name="current" required></label>
      <label>New password (min 8 chars) <input type="password" name="next" minlength="8" required></label>
      <button type="submit">Change password</button>
    </form>
    <form method="POST" action="/logout" class="logout-form">
      <input type="hidden" name="_csrf" value="${csrf}">
      <button type="submit">Log out</button>
    </form>`;
}

function pageStatsBody(user, code) {
  const link = stmtLinkByCode.get(code);
  if (!link) return null;
  if (!user.is_admin && link.user_id !== user.id) return "forbidden";
  const total = stmtCountClicksCode.get(code).n;
  const clicks = stmtClicksByCode.all(code, 100);
  const rows = clicks.length
    ? clicks.map((c) => {
        const when = new Date(c.clicked_at * 1000).toISOString().replace("T", " ").slice(0, 19);
        return `<tr><td>${when}</td><td>${escapeHtml(c.ip)}</td><td>${escapeHtml(c.user_agent)}</td><td>${escapeHtml(c.referrer)}</td></tr>`;
      }).join("")
    : `<tr><td colspan="4" class="muted">no clicks yet</td></tr>`;
  return `
    <h1>${escapeHtml(code)}</h1>
    <p>
      <strong>Destination:</strong> <a href="${escapeHtml(link.url)}">${escapeHtml(link.url)}</a><br>
      <strong>Created:</strong> ${new Date(link.created_at * 1000).toISOString()}<br>
      <strong>Note:</strong> ${escapeHtml(link.note || "")}<br>
      <strong>Total clicks:</strong> ${total}
    </p>
    <p><a href="/qr/${encodeURIComponent(code)}.svg">QR code</a> · <a href="/admin">back to admin</a></p>
    <h2>Recent clicks</h2>
    <table>
      <tr><th>When (UTC)</th><th>IP</th><th>UA</th><th>Referrer</th></tr>
      ${rows}
    </table>`;
}

// Landing body — the features grid + login form. Wrapped by the shared
// shell at request time so banner + cosmic bg + parallax come along.
function landingBody() {
  return `
    <section class="hero">
      <div class="feature">
        <img src="/icons/code.png" alt="" class="feat-icon">
        <h3>Custom or random</h3>
        <p>Pick your own code (<code>kry.li/launch</code>) or auto-generate a 6-character base62.</p>
      </div>
      <div class="feature">
        <img src="/icons/analytics.png" alt="" class="feat-icon">
        <h3>Click analytics</h3>
        <p>Every visit logged with timestamp, referrer, IP, and user agent.</p>
      </div>
      <div class="feature">
        <img src="/icons/qr.png" alt="" class="feat-icon">
        <h3>Server-side QR</h3>
        <p>Each link gets a scannable QR code, rendered on the server, no third-party API.</p>
      </div>
      <div class="feature">
        <img src="/icons/fast.png" alt="" class="feat-icon">
        <h3>Lightning fast</h3>
        <p>No JavaScript framework, no client-side bloat — every page paints instantly.</p>
      </div>
      <div class="feature">
        <img src="/icons/privacy.png" alt="" class="feat-icon">
        <h3>Privacy</h3>
        <p>Self-hosted on our own infrastructure. No third-party trackers, no analytics SDKs.</p>
      </div>
      <div class="login">
        <form method="POST" action="/login" autocomplete="on">
          <p class="err" id="err" style="display:none"></p>
          <input type="text" name="username" placeholder="username" autocomplete="username" required>
          <input type="password" name="password" placeholder="password" autocomplete="current-password" required>
          <button type="submit">Log in</button>
          <button type="button" class="ghost" disabled title="signups are closed">Create account</button>
        </form>
      </div>
    </section>`;
}

// ── Routes ───────────────────────────────────────────────────────────

// Static assets under PUBLIC_DIR — cached 1h.
// MUST come before the bit.ly-style /:code catch-all so paths like
// /icons/code.png and /banner/kryli.png don't get treated as short codes.
app.use("/icons",  express.static(path.join(PUBLIC_DIR, "icons"),  { maxAge: "1h" }));
app.use("/banner", express.static(path.join(PUBLIC_DIR, "banner"), { maxAge: "1h" }));

// Landing — features grid + login form, wrapped in the shared shell.
app.get(["/", "/index.html"], (req, res) => {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.send(renderShell(landingBody()));
});

// Auth — username + password (rate-limited by IP and by username)
app.post("/login", (req, res) => {
  const ip = req.ip || "?";
  const username = (req.body.username || "").trim();
  const password = req.body.password || "";
  // 10 attempts / 15 min / IP and 10 attempts / 15 min / username.
  // Either bucket overflowing throttles. Failures and successes both
  // count — so a stolen password still has a quota.
  if (!rateLimit(`login:ip:${ip}`, 15 * 60 * 1000, 10) ||
      !rateLimit(`login:user:${username}`, 15 * 60 * 1000, 10)) {
    return res.status(429).redirect("/?err=throttled");
  }
  if (!username || !password) {
    return res.status(400).redirect("/?err=missing");
  }
  const user = stmtUserByName.get(username);
  if (!user || user.disabled || !verifyPassword(password, user.password_hash)) {
    logAudit(null, "login.fail", `username=${username}`, req);
    return res.status(401).redirect("/?err=bad");
  }
  logAudit(user, "login.ok", null, req);
  res.cookie(SESSION_COOKIE, signToken(username), {
    httpOnly: true,
    sameSite: "lax",
    secure: req.secure,
    maxAge: 30 * 24 * 3600 * 1000,
  });
  res.redirect("/admin");
});

app.post("/logout", (req, res) => {
  // CSRF not strictly required for logout (no harmful side effect),
  // but the form embeds it anyway and we don't reject if absent.
  res.clearCookie(SESSION_COOKIE);
  res.redirect("/");
});

// Admin (auth-gated)
app.get("/admin", (req, res) => {
  const user = getUser(req);
  if (!user) return res.redirect("/");
  res.send(renderShell(pageAdminBody(user, "")));
});

app.post("/create", (req, res) => {
  const user = getUser(req);
  if (!user) return res.status(401).redirect("/");
  if (!verifyCSRF(req, user)) return res.status(403).send(renderShell(`<h1>403</h1><p>CSRF check failed. <a href="/admin">back</a></p>`));
  // Rate limit: 30 creates per 5 minutes per user.
  if (!rateLimit(`create:${user.id}`, 5 * 60 * 1000, 30)) {
    return res.status(429).send(renderShell(pageAdminBody(user, '<span class="bad">slow down — too many creates in the last 5 min</span>')));
  }
  // Quota check: non-admin users have a max link cap.
  const q = checkLinkQuota(user);
  if (!q.ok) {
    return res.status(403).send(renderShell(pageAdminBody(user, `<span class="bad">link quota reached (${q.used}/${q.limit}) — delete a link or contact the admin to raise your cap</span>`)));
  }
  const url = (req.body.url || "").trim();
  let code = (req.body.code || "").trim();
  const note = (req.body.note || "").trim();
  if (!/^https?:\/\/[^\s]+$/i.test(url)) {
    return res.status(400).send(renderShell(pageAdminBody(user, '<span class="bad">invalid URL</span>')));
  }
  if (code) {
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(code) || RESERVED.has(code) || stmtLinkByCode.get(code)) {
      return res.status(409).send(renderShell(pageAdminBody(user, '<span class="bad">code unavailable</span>')));
    }
  } else {
    code = genUniqueCode();
  }
  stmtInsertLink.run(code, url, Math.floor(Date.now() / 1000), note || null, user.id);
  logAudit(user, "link.create", `${code} → ${url}`, req);
  const short = `${PUBLIC_HOST}/${code}`;
  const banner = `<div class="created">
    <img class="created-qr" src="/qr/${encodeURIComponent(code)}.svg" alt="QR code for ${escapeHtml(short)}">
    <div class="created-body">
      <div class="muted" style="font-size:.85em">Created</div>
      <div class="short">
        <a href="${escapeHtml(short)}" target="_blank" rel="noopener">${escapeHtml(short)}</a>
        <button type="button" class="copy-btn" onclick="navigator.clipboard.writeText('${short.replace(/'/g, "\\'")}').then(()=>{this.textContent='copied'})">copy</button>
      </div>
      <div class="muted" style="margin-top:.4em">
        → ${escapeHtml(url)} &middot;
        <a href="/qr/${encodeURIComponent(code)}.svg" download="${escapeHtml(code)}.svg">download QR</a> &middot;
        <a href="/stats/${encodeURIComponent(code)}">stats</a>
      </div>
    </div>
  </div>`;
  res.send(renderShell(pageAdminBody(user, banner)));
});

// ADMIN ONLY: create a new user account.
app.post("/users/create", (req, res) => {
  const user = getUser(req);
  if (!user) return res.status(401).redirect("/");
  if (!user.is_admin) return res.status(403).send(renderShell(pageAdminBody(user, '<span class="bad">admin only</span>')));
  if (!verifyCSRF(req, user)) return res.status(403).send(renderShell(`<h1>403</h1><p>CSRF check failed. <a href="/admin">back</a></p>`));
  const newName = (req.body.username || "").trim();
  const newPw = req.body.password || "";
  const grantAdmin = req.body.is_admin === "1" ? 1 : 0;
  if (!/^[A-Za-z0-9_-]{2,32}$/.test(newName)) {
    return res.status(400).send(renderShell(pageAdminBody(user, '<span class="bad">invalid username (2-32 chars, [A-Za-z0-9_-])</span>')));
  }
  if (newPw.length < 8) {
    return res.status(400).send(renderShell(pageAdminBody(user, '<span class="bad">password too short (min 8)</span>')));
  }
  if (stmtUserByName.get(newName)) {
    return res.status(409).send(renderShell(pageAdminBody(user, '<span class="bad">username taken</span>')));
  }
  stmtInsertUser.run(newName, hashPassword(newPw), grantAdmin, Math.floor(Date.now() / 1000));
  logAudit(user, "user.create", `${newName}${grantAdmin ? " (admin)" : ""}`, req);
  res.send(renderShell(pageAdminBody(user, `Created user <code>${escapeHtml(newName)}</code>${grantAdmin ? " (admin)" : ""}`)));
});

// Self-service: change your own password.
app.post("/password", (req, res) => {
  const user = getUser(req);
  if (!user) return res.status(401).redirect("/");
  if (!verifyCSRF(req, user)) return res.status(403).send(renderShell(`<h1>403</h1><p>CSRF check failed.</p>`));
  const current = req.body.current || "";
  const next = req.body.next || "";
  if (!verifyPassword(current, user.password_hash)) {
    return res.status(401).send(renderShell(pageAdminBody(user, '<span class="bad">current password is wrong</span>')));
  }
  if (next.length < 8) {
    return res.status(400).send(renderShell(pageAdminBody(user, '<span class="bad">new password must be at least 8 chars</span>')));
  }
  stmtUpdateUserPw.run(hashPassword(next), user.id);
  logAudit(user, "user.password.self", null, req);
  res.send(renderShell(pageAdminBody(user, '<span class="ok">password updated</span>')));
});

// ADMIN ONLY: toggle disable state for another user.
app.post("/users/toggle", (req, res) => {
  const actor = getUser(req);
  if (!actor) return res.status(401).redirect("/");
  if (!actor.is_admin) return res.status(403).send(renderShell(`<h1>403</h1>`));
  if (!verifyCSRF(req, actor)) return res.status(403).send(renderShell(`<h1>403</h1><p>CSRF check failed.</p>`));
  const target = stmtUserById.get(Number(req.body.user_id));
  if (!target) return res.status(404).send(renderShell(pageAdminBody(actor, '<span class="bad">user not found</span>')));
  if (target.id === actor.id) return res.status(400).send(renderShell(pageAdminBody(actor, '<span class="bad">cannot disable yourself</span>')));
  stmtToggleUserDis.run(target.disabled ? 0 : 1, target.id);
  logAudit(actor, target.disabled ? "user.enable" : "user.disable", target.username, req);
  res.send(renderShell(pageAdminBody(actor, `<span class="ok">user <code>${escapeHtml(target.username)}</code> ${target.disabled ? "enabled" : "disabled"}</span>`)));
});

// ADMIN ONLY: delete a user. Links they own become orphaned (user_id = NULL).
app.post("/users/delete", (req, res) => {
  const actor = getUser(req);
  if (!actor) return res.status(401).redirect("/");
  if (!actor.is_admin) return res.status(403).send(renderShell(`<h1>403</h1>`));
  if (!verifyCSRF(req, actor)) return res.status(403).send(renderShell(`<h1>403</h1><p>CSRF check failed.</p>`));
  const target = stmtUserById.get(Number(req.body.user_id));
  if (!target) return res.status(404).send(renderShell(pageAdminBody(actor, '<span class="bad">user not found</span>')));
  if (target.id === actor.id) return res.status(400).send(renderShell(pageAdminBody(actor, '<span class="bad">cannot delete yourself</span>')));
  if (target.is_admin) return res.status(400).send(renderShell(pageAdminBody(actor, '<span class="bad">cannot delete an admin from the UI (demote first via SQL)</span>')));
  stmtClearUserLinks.run(target.id);
  stmtDeleteUser.run(target.id);
  logAudit(actor, "user.delete", target.username, req);
  res.send(renderShell(pageAdminBody(actor, `<span class="ok">user <code>${escapeHtml(target.username)}</code> deleted; their links are now un-owned</span>`)));
});

// ADMIN ONLY: set a user's link-creation cap. 0 = unlimited.
app.post("/users/set_limit", (req, res) => {
  const actor = getUser(req);
  if (!actor) return res.status(401).redirect("/");
  if (!actor.is_admin) return res.status(403).send(renderShell(`<h1>403</h1>`));
  if (!verifyCSRF(req, actor)) return res.status(403).send(renderShell(`<h1>403</h1><p>CSRF check failed.</p>`));
  const target = stmtUserById.get(Number(req.body.user_id));
  if (!target) return res.status(404).send(renderShell(pageAdminBody(actor, '<span class="bad">user not found</span>')));
  const newLimit = Math.max(0, Math.min(100000, Number(req.body.link_limit) | 0));
  stmtSetUserLimit.run(newLimit, target.id);
  logAudit(actor, "user.set_limit", `${target.username} → ${newLimit || "∞"}`, req);
  res.send(renderShell(pageAdminBody(actor, `<span class="ok">cap for <code>${escapeHtml(target.username)}</code> set to ${newLimit || "∞"}</span>`)));
});

// ADMIN ONLY: reset another user's password.
app.post("/users/reset_password", (req, res) => {
  const actor = getUser(req);
  if (!actor) return res.status(401).redirect("/");
  if (!actor.is_admin) return res.status(403).send(renderShell(`<h1>403</h1>`));
  if (!verifyCSRF(req, actor)) return res.status(403).send(renderShell(`<h1>403</h1><p>CSRF check failed.</p>`));
  const target = stmtUserByName.get((req.body.username || "").trim());
  if (!target) return res.status(404).send(renderShell(pageAdminBody(actor, '<span class="bad">user not found</span>')));
  const newPw = req.body.password || "";
  if (newPw.length < 8) return res.status(400).send(renderShell(pageAdminBody(actor, '<span class="bad">password must be at least 8 chars</span>')));
  stmtUpdateUserPw.run(hashPassword(newPw), target.id);
  logAudit(actor, "user.password.admin", target.username, req);
  res.send(renderShell(pageAdminBody(actor, `<span class="ok">password reset for <code>${escapeHtml(target.username)}</code></span>`)));
});

app.get("/stats/:code", (req, res) => {
  const user = getUser(req);
  if (!user) return res.redirect("/");
  const body = pageStatsBody(user, req.params.code);
  // 404 in BOTH the "doesn't exist" and "exists but isn't yours" cases.
  // Returning a distinct 403 would leak the existence of someone else's
  // link to a probing user.
  if (!body || body === "forbidden") {
    return res.status(404).send(renderShell(`<h1>404 — link not found</h1><p><a href="/admin">back to admin</a></p>`));
  }
  res.send(renderShell(body));
});

// QR (public)
app.get("/qr/:code.svg", async (req, res) => {
  const short = `${PUBLIC_HOST}/${req.params.code}`;
  try {
    const svg = await QRCode.toString(short, { type: "svg", margin: 2, width: 256, errorCorrectionLevel: "M" });
    res.setHeader("Content-Type", "image/svg+xml");
    res.send(svg);
  } catch (e) {
    res.status(500).send("qr render failed");
  }
});

// Short-code redirect (catch-all, last)
app.get("/:code", (req, res, next) => {
  const code = req.params.code;
  if (RESERVED.has(code)) return next();
  const link = stmtLinkByCode.get(code);
  if (!link) return res.status(404).send(renderShell(`<h1>404 — link not found</h1><p><a href="/">home</a></p>`));
  // Per-owner click rate cap. Generous default (1000/min) so legit
  // virality isn't throttled; protects against a runaway abuser pumping
  // one customer's link in a loop. NULL owner (orphaned links from
  // deleted users) shares a single bucket.
  const ownerKey = link.user_id || 0;
  if (!rateLimit(`clicks:user:${ownerKey}`, 60 * 1000, 1000)) {
    return res.status(429).send(renderShell(`<h1>429 — too many clicks</h1><p>This link is temporarily rate-limited. Try again in a minute.</p>`));
  }
  stmtInsertClick.run(
    code,
    Math.floor(Date.now() / 1000),
    req.ip || "",
    req.get("User-Agent") || "",
    req.get("Referer") || "",
  );
  res.redirect(302, link.url);
});

// 404
app.use((req, res) => res.status(404).send(renderShell(`<h1>404</h1><p><a href="/">home</a></p>`)));

// ── Boot ─────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`kryptlink on http://127.0.0.1:${PORT}`);
  console.log(`public host: ${PUBLIC_HOST}`);
  console.log(`db: ${DB_PATH}`);
});
