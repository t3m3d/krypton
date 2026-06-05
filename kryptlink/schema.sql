-- kryptlink schema (SQLite). Run once on a fresh DB:
--   sqlite3 kryptlink.db < schema.sql

CREATE TABLE IF NOT EXISTS links (
  code        TEXT PRIMARY KEY,            -- short code (e.g. 'aB3xQ')
  url         TEXT NOT NULL,               -- destination URL
  created_at  INTEGER NOT NULL,            -- unix epoch seconds
  note        TEXT                          -- optional note from creator
);

CREATE TABLE IF NOT EXISTS clicks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT NOT NULL,
  clicked_at  INTEGER NOT NULL,
  ip          TEXT,
  user_agent  TEXT,
  referrer    TEXT,
  FOREIGN KEY(code) REFERENCES links(code)
);

CREATE INDEX IF NOT EXISTS idx_clicks_code ON clicks(code);
CREATE INDEX IF NOT EXISTS idx_clicks_ts   ON clicks(clicked_at);
