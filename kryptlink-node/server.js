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
const stmtAllUsers        = db.prepare("SELECT id, username, is_admin, created_at FROM users ORDER BY created_at ASC");
const stmtInsertUser      = db.prepare("INSERT INTO users(username, password_hash, is_admin, created_at) VALUES (?, ?, ?, ?)");

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
  return stmtUserByName.get(username) || null;
}

// ── Express setup ────────────────────────────────────────────────────
const app = express();
app.set("trust proxy", true);
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
button[disabled]{background:#999;cursor:not-allowed;opacity:.7}
table{border-collapse:collapse;width:100%;margin-top:1em;font-size:.9em}
th,td{padding:.4em .5em;text-align:left;border-bottom:1px solid #ddd;vertical-align:top}
th{background:#eee}
code{background:#eee;padding:.1em .3em;border-radius:3px}
.muted{color:#888;font-size:.9em}
.ok{color:#283}
.bad{color:#c44}
.pill{display:inline-block;padding:.05em .5em;border-radius:1em;background:#4F5AA8;color:white;font-size:.75em;vertical-align:middle}
form{margin-bottom:1em}
@media(prefers-color-scheme:dark){body{background:#15151c;color:#e8e8f0}input{background:#202028;color:inherit;border-color:#33333f}th{background:#1c1c25}td{border-color:#2a2a35}code{background:#2a2a35}}
</style>`;

function pageAdmin(user, msg) {
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
    usersSection = `
      <h2>Users</h2>
      <table>
        <tr><th>Username</th><th>Created</th></tr>
        ${uRows}
      </table>
      <form method="POST" action="/users/create" style="margin-top:1em">
        <label>New username <input type="text" name="username" pattern="[A-Za-z0-9_-]{2,32}" required></label>
        <label>Password <input type="password" name="password" minlength="8" required></label>
        <label><input type="checkbox" name="is_admin" value="1"> grant admin</label>
        <button type="submit">Create user</button>
      </form>`;
  }

  return `<!doctype html><html><head><title>kryptlink — admin</title>${CSS}</head><body>
    <h1>kryptlink <span class="muted" style="font-size:.5em">(${escapeHtml(user.username)}${user.is_admin ? " · admin" : ""})</span></h1>
    ${msg ? `<p class="ok">${msg}</p>` : ""}
    <h2>Shorten a URL</h2>
    <form method="POST" action="/create">
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
    <form method="POST" action="/logout" style="margin-top:2em">
      <button type="submit">Log out</button>
    </form>
  </body></html>`;
}

function pageStats(user, code) {
  const link = stmtLinkByCode.get(code);
  if (!link) return null;
  // Non-admin must own the link.
  if (!user.is_admin && link.user_id !== user.id) return "forbidden";
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

// Static assets under PUBLIC_DIR — cached 1h.
// MUST come before the bit.ly-style /:code catch-all so paths like
// /icons/code.png and /banner/kryli.png don't get treated as short codes.
app.use("/icons",  express.static(path.join(PUBLIC_DIR, "icons"),  { maxAge: "1h" }));
app.use("/banner", express.static(path.join(PUBLIC_DIR, "banner"), { maxAge: "1h" }));

// Static landing page (with a login form). Auth required only for /admin.
app.get(["/", "/index.html"], (req, res) => {
  const indexPath = path.join(PUBLIC_DIR, "index.html");
  if (fs.existsSync(indexPath)) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.sendFile(indexPath);
  }
  // Fallback if no public/index.html present.
  res.send(`<!doctype html><html><head><title>kryptlink</title>${CSS}</head><body>
    <h1>kry.li</h1><p>Short links + click tracking.</p>
    <form method="POST" action="/login">
      <input type="text" name="username" placeholder="username" required>
      <input type="password" name="password" placeholder="password" required>
      <button type="submit">Log in</button>
      <button type="button" disabled title="signups closed">Create an account</button>
    </form>
  </body></html>`);
});

// Auth — username + password
app.post("/login", (req, res) => {
  const username = (req.body.username || "").trim();
  const password = req.body.password || "";
  if (!username || !password) {
    return res.status(400).redirect("/?err=missing");
  }
  const user = stmtUserByName.get(username);
  if (!user || !verifyPassword(password, user.password_hash)) {
    return res.status(401).redirect("/?err=bad");
  }
  res.cookie(SESSION_COOKIE, signToken(username), {
    httpOnly: true,
    sameSite: "lax",
    secure: req.secure,
    maxAge: 30 * 24 * 3600 * 1000,
  });
  res.redirect("/admin");
});

app.post("/logout", (req, res) => {
  res.clearCookie(SESSION_COOKIE);
  res.redirect("/");
});

// Admin (auth-gated)
app.get("/admin", (req, res) => {
  const user = getUser(req);
  if (!user) return res.redirect("/");
  res.send(pageAdmin(user, ""));
});

app.post("/create", (req, res) => {
  const user = getUser(req);
  if (!user) return res.status(401).redirect("/");
  const url = (req.body.url || "").trim();
  let code = (req.body.code || "").trim();
  const note = (req.body.note || "").trim();
  if (!/^https?:\/\/[^\s]+$/i.test(url)) {
    return res.status(400).send(pageAdmin(user, '<span class="bad">invalid URL</span>'));
  }
  if (code) {
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(code) || RESERVED.has(code) || stmtLinkByCode.get(code)) {
      return res.status(409).send(pageAdmin(user, '<span class="bad">code unavailable</span>'));
    }
  } else {
    code = genUniqueCode();
  }
  stmtInsertLink.run(code, url, Math.floor(Date.now() / 1000), note || null, user.id);
  const short = `${PUBLIC_HOST}/${code}`;
  res.send(pageAdmin(user, `Created <a href="${escapeHtml(short)}">${escapeHtml(short)}</a>`));
});

// ADMIN ONLY: create a new user account.
app.post("/users/create", (req, res) => {
  const user = getUser(req);
  if (!user) return res.status(401).redirect("/");
  if (!user.is_admin) return res.status(403).send(pageAdmin(user, '<span class="bad">admin only</span>'));
  const newName = (req.body.username || "").trim();
  const newPw = req.body.password || "";
  const grantAdmin = req.body.is_admin === "1" ? 1 : 0;
  if (!/^[A-Za-z0-9_-]{2,32}$/.test(newName)) {
    return res.status(400).send(pageAdmin(user, '<span class="bad">invalid username (2-32 chars, [A-Za-z0-9_-])</span>'));
  }
  if (newPw.length < 8) {
    return res.status(400).send(pageAdmin(user, '<span class="bad">password too short (min 8)</span>'));
  }
  if (stmtUserByName.get(newName)) {
    return res.status(409).send(pageAdmin(user, '<span class="bad">username taken</span>'));
  }
  stmtInsertUser.run(newName, hashPassword(newPw), grantAdmin, Math.floor(Date.now() / 1000));
  res.send(pageAdmin(user, `Created user <code>${escapeHtml(newName)}</code>${grantAdmin ? " (admin)" : ""}`));
});

app.get("/stats/:code", (req, res) => {
  const user = getUser(req);
  if (!user) return res.redirect("/");
  const html = pageStats(user, req.params.code);
  if (!html) return res.status(404).send("<h1>not found</h1>");
  if (html === "forbidden") return res.status(403).send("<h1>403 — that link isn't yours</h1>");
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
