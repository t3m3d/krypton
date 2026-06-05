// kryptlink — URL shortener with click tracking + server-rendered QR codes.
// Node.js (Express + better-sqlite3 + qrcode). Pairs with kryptlink/ (the
// pure-Krypton implementation, kept as a showcase / future direction).
//
//   First time:
//     npm install
//     npm run init-db
//   Env:
//     KRYPTLINK_PASSWORD     admin password (required)
//     KRYPTLINK_DB           sqlite path (default: kryptlink.db)
//     KRYPTLINK_PUBLIC_HOST  short-URL base (default: http://localhost:8080)
//     KRYPTLINK_PUBLIC_DIR   static dir served at / (default: ./public)
//     PORT                   default 8080
//
//   Run:
//     npm start
//
// Routes mirror the Krypton spec one-for-one:
//   GET  /                 → public landing (KRYPTLINK_PUBLIC_DIR/index.html)
//   GET  /admin            → admin (login OR control panel)
//   POST /login            → cookie session
//   POST /logout
//   POST /create           → new link (auth required)
//   GET  /stats/<code>     → click history (auth required)
//   GET  /qr/<code>.svg    → QR code for the short URL
//   GET  /<code>           → 302 + click log (bit.ly-style)

import express from "express";
import cookieParser from "cookie-parser";
import { DatabaseSync } from "node:sqlite";
import QRCode from "qrcode";
import { customAlphabet } from "nanoid";
import crypto from "node:crypto";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── Config ───────────────────────────────────────────────────────────
const PASSWORD     = process.env.KRYPTLINK_PASSWORD;
const DB_PATH      = process.env.KRYPTLINK_DB          || "kryptlink.db";
const PUBLIC_HOST  = process.env.KRYPTLINK_PUBLIC_HOST || "http://localhost:8080";
const PUBLIC_DIR   = process.env.KRYPTLINK_PUBLIC_DIR  || path.join(__dirname, "public");
const PORT         = Number(process.env.PORT) || 8080;

if (!PASSWORD) {
  console.error("kryptlink: KRYPTLINK_PASSWORD env var is required");
  process.exit(1);
}

// ── DB ───────────────────────────────────────────────────────────────
const db = new DatabaseSync(DB_PATH);
db.exec("PRAGMA journal_mode = WAL");
db.exec("PRAGMA foreign_keys = ON");

const stmtLinkByCode      = db.prepare("SELECT * FROM links WHERE code = ?");
const stmtInsertLink      = db.prepare("INSERT INTO links(code, url, created_at, note) VALUES (?, ?, ?, ?)");
const stmtRecentLinks     = db.prepare("SELECT * FROM links ORDER BY created_at DESC LIMIT ?");
const stmtInsertClick     = db.prepare("INSERT INTO clicks(code, clicked_at, ip, user_agent, referrer) VALUES (?, ?, ?, ?, ?)");
const stmtClicksByCode    = db.prepare("SELECT * FROM clicks WHERE code = ? ORDER BY clicked_at DESC LIMIT ?");
const stmtCountClicksCode = db.prepare("SELECT COUNT(*) AS n FROM clicks WHERE code = ?");

// ── Codes ────────────────────────────────────────────────────────────
const CODE_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const nanoid = customAlphabet(CODE_ALPHABET, 6);

const RESERVED = new Set([
  "", "admin", "login", "logout", "create", "stats", "qr",
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

// ── Session cookie (single shared password) ──────────────────────────
const SESSION_TOKEN = crypto.createHash("sha256").update(PASSWORD).digest("hex").slice(0, 32);
const SESSION_COOKIE = "kryptlink";

function hasSession(req) {
  return req.cookies[SESSION_COOKIE] === SESSION_TOKEN;
}

// ── Express setup ────────────────────────────────────────────────────
const app = express();
app.set("trust proxy", true);  // honour X-Forwarded-For from nginx
app.use(cookieParser());
app.use(express.urlencoded({ extended: false }));

// ── HTML helpers ─────────────────────────────────────────────────────
const escapeHtml = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]));

const CSS = `<style>
body{font-family:system-ui,sans-serif;max-width:720px;margin:2em auto;padding:0 1em;color:#222;background:#fafafa}
h1{color:#4F5AA8}
input,button{font:inherit;padding:.5em;margin:.25em 0;border:1px solid #ccc;border-radius:4px}
input[type=text],input[type=url],input[type=password]{width:100%;box-sizing:border-box}
button{background:#4F5AA8;color:white;border:none;cursor:pointer}
button:hover{background:#3a448a}
table{border-collapse:collapse;width:100%;margin-top:1em;font-size:.9em}
th,td{padding:.4em .5em;text-align:left;border-bottom:1px solid #ddd;vertical-align:top}
th{background:#eee}
code{background:#eee;padding:.1em .3em;border-radius:3px}
.muted{color:#888;font-size:.9em}
.ok{color:#283}
.bad{color:#c44}
form{margin-bottom:1em}
@media(prefers-color-scheme:dark){body{background:#15151c;color:#e8e8f0}input{background:#202028;color:inherit;border-color:#33333f}th{background:#1c1c25}td{border-color:#2a2a35}code{background:#2a2a35}}
</style>`;

function pageLogin(error) {
  return `<!doctype html><html><head><title>kryptlink — login</title>${CSS}</head><body>
    <h1>kryptlink</h1>
    ${error ? `<p class="bad">${escapeHtml(error)}</p>` : ""}
    <form method="POST" action="/login">
      <label>Password <input type="password" name="password" autofocus></label>
      <button type="submit">Log in</button>
    </form>
  </body></html>`;
}

function pageAdmin(msg) {
  const links = stmtRecentLinks.all(50);
  const rows = links.length
    ? links.map((l) => {
        const short = `${PUBLIC_HOST}/${l.code}`;
        const date = new Date(l.created_at * 1000).toISOString().slice(0, 10);
        return `<tr>
          <td><a href="${escapeHtml(short)}">${escapeHtml(l.code)}</a></td>
          <td><a href="${escapeHtml(l.url)}">${escapeHtml(l.url)}</a></td>
          <td>${date}</td>
          <td>${escapeHtml(l.note || "")}</td>
          <td><a href="/stats/${encodeURIComponent(l.code)}">stats</a> · <a href="/qr/${encodeURIComponent(l.code)}.svg">qr</a></td>
        </tr>`;
      }).join("")
    : `<tr><td colspan="5" class="muted">no links yet</td></tr>`;

  return `<!doctype html><html><head><title>kryptlink — admin</title>${CSS}</head><body>
    <h1>kryptlink</h1>
    ${msg ? `<p class="ok">${msg}</p>` : ""}
    <form method="POST" action="/create">
      <label>URL <input type="url" name="url" placeholder="https://example.com/long/path" required></label>
      <label>Custom code (optional) <input type="text" name="code" placeholder="launch" pattern="[A-Za-z0-9_\\-]{1,32}"></label>
      <label>Note (optional) <input type="text" name="note" placeholder="Q4 launch announcement"></label>
      <button type="submit">Shorten</button>
    </form>
    <h2>Recent links</h2>
    <table>
      <tr><th>Short</th><th>Destination</th><th>Created</th><th>Note</th><th></th></tr>
      ${rows}
    </table>
    <form method="POST" action="/logout" style="margin-top:2em">
      <button type="submit">Log out</button>
    </form>
  </body></html>`;
}

function pageStats(code) {
  const link = stmtLinkByCode.get(code);
  if (!link) return null;
  const total = stmtCountClicksCode.get(code).n;
  const clicks = stmtClicksByCode.all(code, 100);
  const rows = clicks.length
    ? clicks.map((c) => {
        const when = new Date(c.clicked_at * 1000).toISOString().replace("T", " ").slice(0, 19);
        return `<tr><td>${when}</td><td>${escapeHtml(c.ip)}</td><td>${escapeHtml(c.user_agent)}</td><td>${escapeHtml(c.referrer)}</td></tr>`;
      }).join("")
    : `<tr><td colspan="4" class="muted">no clicks yet</td></tr>`;
  return `<!doctype html><html><head><title>stats — ${escapeHtml(code)}</title>${CSS}</head><body>
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
    </table>
  </body></html>`;
}

// ── Routes ───────────────────────────────────────────────────────────

// Static landing page
app.get(["/", "/index.html"], (req, res) => {
  const indexPath = path.join(PUBLIC_DIR, "index.html");
  if (fs.existsSync(indexPath)) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.sendFile(indexPath);
  }
  res.send(`<!doctype html><html><head><title>kryptlink</title>${CSS}</head><body><h1>kry.li</h1><p>Short links + click tracking.</p><p><a href="/admin">admin</a></p></body></html>`);
});

// Auth
app.post("/login", (req, res) => {
  if (req.body.password === PASSWORD) {
    res.cookie(SESSION_COOKIE, SESSION_TOKEN, { httpOnly: true, sameSite: "lax", maxAge: 30 * 24 * 3600 * 1000 });
    return res.redirect("/admin");
  }
  res.status(401).send(pageLogin("bad password"));
});

app.post("/logout", (req, res) => {
  res.clearCookie(SESSION_COOKIE);
  res.redirect("/");
});

// Admin (auth-gated)
app.get("/admin", (req, res) => {
  if (!hasSession(req)) return res.send(pageLogin(""));
  res.send(pageAdmin(""));
});

app.post("/create", (req, res) => {
  if (!hasSession(req)) return res.status(401).send(pageLogin(""));
  const url = (req.body.url || "").trim();
  let code = (req.body.code || "").trim();
  const note = (req.body.note || "").trim();
  if (!/^https?:\/\/[^\s]+$/i.test(url)) {
    return res.status(400).send(pageAdmin('<span class="bad">invalid URL</span>'));
  }
  if (code) {
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(code) || RESERVED.has(code) || stmtLinkByCode.get(code)) {
      return res.status(409).send(pageAdmin('<span class="bad">code unavailable</span>'));
    }
  } else {
    code = genUniqueCode();
  }
  stmtInsertLink.run(code, url, Math.floor(Date.now() / 1000), note || null);
  const short = `${PUBLIC_HOST}/${code}`;
  res.send(pageAdmin(`Created <a href="${escapeHtml(short)}">${escapeHtml(short)}</a>`));
});

app.get("/stats/:code", (req, res) => {
  if (!hasSession(req)) return res.send(pageLogin(""));
  const html = pageStats(req.params.code);
  if (!html) return res.status(404).send("<h1>not found</h1>");
  res.send(html);
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
  if (!link) return res.status(404).send("<h1>link not found</h1>");
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
app.use((req, res) => res.status(404).send("<h1>404</h1>"));

// ── Boot ─────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`kryptlink on http://127.0.0.1:${PORT}`);
  console.log(`public host: ${PUBLIC_HOST}`);
  console.log(`db: ${DB_PATH}`);
});
