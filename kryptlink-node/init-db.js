// Initialize a fresh SQLite database for kryptlink.
// Usage: node init-db.js [path-to-db]
import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dbPath = process.argv[2] || process.env.KRYPTLINK_DB || "kryptlink.db";
const schema = fs.readFileSync(path.join(__dirname, "schema.sql"), "utf8");

const db = new DatabaseSync(dbPath);
db.exec(schema);
db.close();

console.log(`db initialised: ${dbPath}`);
