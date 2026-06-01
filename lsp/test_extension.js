// test_extension.js - smoke test the Node-side framing logic.
// Mimics what extension.js does inside VS Code, without needing VS Code.
//
// Run from repo root:
//   node lsp/test_extension.js

"use strict";

const cp = require("child_process");
const path = require("path");

const klsPath = path.join(__dirname, "..", "kls.exe");
console.log("launching:", klsPath);

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
            setTimeout(() => {
                if (pending.has(id)) {
                    pending.delete(id);
                    rej(new Error("timeout: " + method));
                }
            }, 3000);
        });
    }
    const body = Buffer.from(JSON.stringify(msg), "utf8");
    const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
    proc.stdin.write(Buffer.concat([header, body]));
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
        const total = i + 4 + len;
        if (buffer.length < total) return;
        const body = buffer.slice(i + 4, total).toString("utf8");
        buffer = buffer.slice(total);
        try {
            const msg = JSON.parse(body);
            if (msg.id != null && pending.has(msg.id)) {
                const { res } = pending.get(msg.id);
                pending.delete(msg.id);
                res(msg.result);
            } else if (msg.method === "textDocument/publishDiagnostics") {
                const n = (msg.params.diagnostics || []).length;
                console.log(`◀ publishDiagnostics for ${msg.params.uri}: ${n} items`);
                msg.params.diagnostics.forEach(d => {
                    console.log(`    [${d.severity}] line ${d.range.start.line}: ${d.message}`);
                });
            } else {
                console.log("◀ notification:", msg.method);
            }
        } catch (e) {
            console.log("← parse error:", e.message);
        }
    }
});

proc.stderr.on("data", d => process.stderr.write("[kls] " + d));

const goodCode = `module sample

func add(a, b) {
    emit a + b
}

func main() {
    let x = add(2, 3)
}
`;

const badCode = `func broken() {
    let x = "unterminated
`;

(async () => {
    try {
        const init = await send("initialize", { processId: process.pid, rootUri: null, capabilities: {} }, true);
        console.log("◀ init result, capabilities:", Object.keys(init.capabilities).join(", "));

        await send("initialized", {});
        console.log("→ initialized");

        await send("textDocument/didOpen", {
            textDocument: { uri: "file:///x/sample.k", languageId: "krypton", version: 1, text: goodCode }
        });
        console.log("→ didOpen sample.k");

        await new Promise(r => setTimeout(r, 200));

        const syms = await send("textDocument/documentSymbol", {
            textDocument: { uri: "file:///x/sample.k" }
        }, true);
        console.log(`◀ documentSymbol: ${syms.length} items: ${syms.map(s => s.name).join(", ")}`);

        const cmp = await send("textDocument/completion", {
            textDocument: { uri: "file:///x/sample.k" },
            position: { line: 0, character: 0 }
        }, true);
        const items = cmp.items || cmp;
        const userFns = items.filter(it => it.detail === "user function").map(i => i.label);
        console.log(`◀ completion: ${items.length} items, user funcs: [${userFns.join(", ")}]`);

        await send("textDocument/didOpen", {
            textDocument: { uri: "file:///x/bad.k", languageId: "krypton", version: 1, text: badCode }
        });
        console.log("→ didOpen bad.k");

        await new Promise(r => setTimeout(r, 200));

        await send("shutdown", null, true);
        console.log("◀ shutdown ok");

        await send("exit", null);
        console.log("→ exit");

        setTimeout(() => process.exit(0), 200);
    } catch (e) {
        console.error("ERROR:", e.message);
        process.exit(1);
    }
})();
