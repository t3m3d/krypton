// Test documentSymbol against algorithms/run_length_encoding.k
"use strict";
const cp = require("child_process");
const fs = require("fs");
const path = require("path");

const klsPath = path.join(__dirname, "..", "kls.exe");
const filePath = path.join(__dirname, "..", "algorithms", "run_length_encoding.k");
const text = fs.readFileSync(filePath, "utf8");
const uri = "file:///" + filePath.replace(/\\/g, "/");

const proc = cp.spawn(klsPath, [], { stdio: ["pipe", "pipe", "pipe"] });
let buffer = Buffer.alloc(0);
let nextId = 1;
const pending = new Map();

function send(method, params, isReq) {
    const msg = { jsonrpc: "2.0", method, params };
    let p = Promise.resolve(null);
    if (isReq) {
        const id = nextId++;
        msg.id = id;
        p = new Promise((res, rej) => {
            pending.set(id, { res, rej });
            setTimeout(() => { if (pending.has(id)) { pending.delete(id); rej(new Error("timeout")); } }, 5000);
        });
    }
    const body = Buffer.from(JSON.stringify(msg), "utf8");
    proc.stdin.write(Buffer.concat([
        Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii"),
        body
    ]));
    return p;
}

proc.stdout.on("data", chunk => {
    buffer = Buffer.concat([buffer, chunk]);
    while (true) {
        const i = buffer.indexOf("\r\n\r\n");
        if (i < 0) return;
        const m = /Content-Length:\s*(\d+)/i.exec(buffer.slice(0, i).toString("ascii"));
        if (!m) { buffer = buffer.slice(i + 4); continue; }
        const len = parseInt(m[1], 10);
        if (buffer.length < i + 4 + len) return;
        const body = buffer.slice(i + 4, i + 4 + len).toString("utf8");
        buffer = buffer.slice(i + 4 + len);
        const msg = JSON.parse(body);
        if (msg.id != null && pending.has(msg.id)) {
            pending.get(msg.id).res(msg.result);
            pending.delete(msg.id);
        }
    }
});

proc.stderr.on("data", d => process.stderr.write("[kls] " + d));

(async () => {
    await send("initialize", { processId: process.pid, rootUri: null, capabilities: {} }, true);
    await send("initialized", {});
    await send("textDocument/didOpen", {
        textDocument: { uri, languageId: "krypton", version: 1, text }
    });
    await new Promise(r => setTimeout(r, 100));
    const syms = await send("textDocument/documentSymbol", {
        textDocument: { uri }
    }, true);
    console.log("\nDOCUMENT SYMBOLS:");
    console.log(JSON.stringify(syms, null, 2));
    console.log(`\nTotal: ${syms.length}`);
    syms.forEach((s, i) => console.log(`  ${i}: ${s.name} (kind=${s.kind})`));
    proc.stdin.end();
    setTimeout(() => process.exit(0), 200);
})().catch(e => { console.error(e); process.exit(1); });
