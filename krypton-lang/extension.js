// extension.js — Krypton VS Code extension
//
// Spawns kls.exe and speaks LSP 3.17 directly using Node's child_process
// + a hand-rolled Content-Length frame parser. We avoid the
// vscode-languageclient dependency so the .vsix stays single-file.
//
// Capabilities consumed:
//   - publishDiagnostics  (server → client)
//   - textDocument/didOpen|didChange|didClose
//   - textDocument/documentSymbol
//   - textDocument/completion
//
// Config keys:
//   krypton.kls.path     — explicit path to kls.exe (else search)
//   krypton.kls.enabled  — disable to fall back to syntax-only mode
//   krypton.kls.trace    — log all frames to output channel

"use strict";

const vscode  = require("vscode");
const cp      = require("child_process");
const path    = require("path");
const fs      = require("fs");

let proc = null;
let output = null;
let diagnostics = null;
let buffer = Buffer.alloc(0);
let nextId = 1;
let pending = new Map();           // id → {resolve, reject}
let documentVersions = new Map();  // uri → version
let trace = false;

// ── kls.exe location ────────────────────────────────────────────

function findKlsBinary(extensionPath) {
    const cfg = vscode.workspace.getConfiguration("krypton");
    const explicit = cfg.get("kls.path", "");
    const probes = [];
    if (explicit) probes.push(["config", explicit]);
    probes.push(
        ["bundled",  path.join(extensionPath, "kls.exe")],
        ["sibling1", path.join(extensionPath, "..", "..", "kls.exe")],
        ["sibling2", path.join(extensionPath, "..", "kls.exe")]
    );
    for (const [tag, p] of probes) {
        const ok = fs.existsSync(p);
        output.appendLine(`  probe ${tag}: ${p} ${ok ? "FOUND" : "missing"}`);
        if (ok) return p;
    }
    // PATH lookup
    try {
        const cmd = process.platform === "win32" ? "where kls.exe" : "which kls";
        const out = cp.execSync(cmd, { stdio: ["ignore", "pipe", "ignore"] })
                      .toString().trim().split(/\r?\n/)[0];
        if (out && fs.existsSync(out)) {
            output.appendLine("  probe PATH: " + out + " FOUND");
            return out;
        }
    } catch (_) { /* not found */ }
    output.appendLine("  probe PATH: not found");
    return null;
}

// ── Frame I/O ───────────────────────────────────────────────────

function send(method, params, isRequest) {
    if (!proc) return Promise.reject(new Error("kls not running"));
    const msg = { jsonrpc: "2.0", method, params };
    let p = Promise.resolve(null);
    if (isRequest) {
        const id = nextId++;
        msg.id = id;
        p = new Promise((resolve, reject) => {
            pending.set(id, { resolve, reject });
            // Timeout after 5s — server should answer fast.
            setTimeout(() => {
                if (pending.has(id)) {
                    pending.get(id).reject(new Error("kls timeout: " + method));
                    pending.delete(id);
                }
            }, 5000);
        });
    }
    const body = Buffer.from(JSON.stringify(msg), "utf8");
    const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
    if (trace) output.appendLine("→ " + JSON.stringify(msg).slice(0, 300));
    proc.stdin.write(Buffer.concat([header, body]));
    return p;
}

function notify(method, params) { return send(method, params, false); }
function request(method, params) { return send(method, params, true); }

function onData(chunk) {
    buffer = Buffer.concat([buffer, chunk]);
    while (true) {
        const headerEnd = buffer.indexOf("\r\n\r\n");
        if (headerEnd < 0) return;
        const header = buffer.slice(0, headerEnd).toString("ascii");
        const m = /Content-Length:\s*(\d+)/i.exec(header);
        if (!m) {
            // Bad header — skip past it.
            buffer = buffer.slice(headerEnd + 4);
            continue;
        }
        const len = parseInt(m[1], 10);
        const total = headerEnd + 4 + len;
        if (buffer.length < total) return;       // wait for more bytes
        const body = buffer.slice(headerEnd + 4, total).toString("utf8");
        buffer = buffer.slice(total);
        try {
            const msg = JSON.parse(body);
            handleMessage(msg);
        } catch (e) {
            output.appendLine("← <unparseable> " + e.message);
        }
    }
}

function handleMessage(msg) {
    if (trace) output.appendLine("← " + JSON.stringify(msg).slice(0, 300));
    if (msg.id != null && pending.has(msg.id)) {
        const { resolve, reject } = pending.get(msg.id);
        pending.delete(msg.id);
        if (msg.error) reject(new Error(msg.error.message || "kls error"));
        else           resolve(msg.result);
        return;
    }
    if (msg.method === "textDocument/publishDiagnostics") {
        applyDiagnostics(msg.params);
    }
}

// ── Diagnostics fan-out ─────────────────────────────────────────

function applyDiagnostics(params) {
    const uri = vscode.Uri.parse(params.uri);
    const items = (params.diagnostics || []).map(d => {
        const range = new vscode.Range(
            d.range.start.line, d.range.start.character,
            d.range.end.line,   d.range.end.character
        );
        const severityMap = {
            1: vscode.DiagnosticSeverity.Error,
            2: vscode.DiagnosticSeverity.Warning,
            3: vscode.DiagnosticSeverity.Information,
            4: vscode.DiagnosticSeverity.Hint
        };
        const diag = new vscode.Diagnostic(
            range, d.message, severityMap[d.severity] || vscode.DiagnosticSeverity.Error
        );
        diag.source = "kls";
        return diag;
    });
    diagnostics.set(uri, items);
}

// ── Document lifecycle ──────────────────────────────────────────

function openDoc(doc) {
    if (output) output.appendLine(`onDidOpen: ${doc.uri.toString()} (lang=${doc.languageId})`);
    if (doc.languageId !== "krypton") return;
    documentVersions.set(doc.uri.toString(), doc.version);
    notify("textDocument/didOpen", {
        textDocument: {
            uri: doc.uri.toString(),
            languageId: "krypton",
            version: doc.version,
            text: doc.getText()
        }
    });
}

function changeDoc(e) {
    if (output && trace) output.appendLine(`onDidChange: ${e.document.uri.toString()} (lang=${e.document.languageId})`);
    if (e.document.languageId !== "krypton") return;
    documentVersions.set(e.document.uri.toString(), e.document.version);
    // Full sync — server is configured for sync mode 1.
    notify("textDocument/didChange", {
        textDocument: { uri: e.document.uri.toString(), version: e.document.version },
        contentChanges: [{ text: e.document.getText() }]
    });
}

function closeDoc(doc) {
    if (doc.languageId !== "krypton") return;
    documentVersions.delete(doc.uri.toString());
    notify("textDocument/didClose", {
        textDocument: { uri: doc.uri.toString() }
    });
}

// ── Provider adapters ───────────────────────────────────────────

function symbolProvider() {
    return {
        provideDocumentSymbols(doc) {
            return request("textDocument/documentSymbol", {
                textDocument: { uri: doc.uri.toString() }
            }).then(syms => {
                if (!Array.isArray(syms)) return [];
                if (output) {
                    output.appendLine(`documentSymbol(${doc.uri.toString()}) -> ${syms.length} items: ${syms.map(s => s.name).join(", ")}`);
                }
                return syms.map(s => {
                    const range = new vscode.Range(
                        s.range.start.line, s.range.start.character,
                        s.range.end.line,   s.range.end.character
                    );
                    const sel = new vscode.Range(
                        s.selectionRange.start.line, s.selectionRange.start.character,
                        s.selectionRange.end.line,   s.selectionRange.end.character
                    );
                    // Map LSP SymbolKind (1-based) → VS Code SymbolKind (0-based).
                    const kind = (s.kind != null) ? (s.kind - 1) : vscode.SymbolKind.Function;
                    return new vscode.DocumentSymbol(s.name, "", kind, range, sel);
                });
            }).catch(e => {
                if (output) output.appendLine(`documentSymbol error: ${e.message}`);
                return [];
            });
        }
    };
}

function completionProvider() {
    return {
        provideCompletionItems(doc, position) {
            return request("textDocument/completion", {
                textDocument: { uri: doc.uri.toString() },
                position: { line: position.line, character: position.character }
            }).then(res => {
                const items = (res && res.items) || (Array.isArray(res) ? res : []);
                return items.map(it => {
                    const ci = new vscode.CompletionItem(
                        it.label,
                        (it.kind != null) ? (it.kind - 1) : vscode.CompletionItemKind.Text
                    );
                    if (it.detail) ci.detail = it.detail;
                    return ci;
                });
            }).catch(() => []);
        }
    };
}

// ── Lifecycle ───────────────────────────────────────────────────

function activate(context) {
    // Create the output channel first thing — even if everything else
    // fails, the user can find "Krypton LSP" in View → Output.
    output = vscode.window.createOutputChannel("Krypton LSP");
    diagnostics = vscode.languages.createDiagnosticCollection("kls");
    context.subscriptions.push(output, diagnostics);
    output.appendLine("Krypton extension 1.8.4 activated");
    output.appendLine("extensionPath: " + context.extensionPath);
    output.show(true);   // surface the channel so first-time users see it

    try {
        activateImpl(context);
    } catch (e) {
        output.appendLine("FATAL during activate: " + (e && e.stack || e));
        vscode.window.showErrorMessage("Krypton extension failed to start: " + (e && e.message || e));
    }
}

function activateImpl(context) {
    const cfg = vscode.workspace.getConfiguration("krypton");
    if (!cfg.get("kls.enabled", true)) {
        output.appendLine("kls disabled by setting krypton.kls.enabled");
        return;
    }
    trace = cfg.get("kls.trace", false);
    output.appendLine("trace: " + trace);

    const bin = findKlsBinary(context.extensionPath);
    if (!bin) {
        const msg = "Krypton: kls.exe not found. Set 'krypton.kls.path' or place kls.exe on PATH. " +
                    "Syntax highlighting still works.";
        output.appendLine(msg);
        vscode.window.showWarningMessage(msg);
        return;
    }
    output.appendLine("launching: " + bin);

    proc = cp.spawn(bin, [], { stdio: ["pipe", "pipe", "pipe"] });
    proc.stdout.on("data", onData);
    proc.stderr.on("data", d => output.append("[kls.stderr] " + d.toString()));
    proc.on("exit", code => {
        output.appendLine("kls exited with code " + code);
        proc = null;
        // Surface the error so users notice — without this, diagnostics
        // just silently stop updating.
        diagnostics.clear();
    });
    proc.on("error", e => {
        vscode.window.showErrorMessage("kls failed to start: " + e.message);
        proc = null;
    });

    // Initialize handshake.
    request("initialize", {
        processId: process.pid,
        rootUri: vscode.workspace.workspaceFolders
            ? vscode.workspace.workspaceFolders[0].uri.toString()
            : null,
        capabilities: {}
    }).then(() => {
        notify("initialized", {});
        // Attach to already-open .k buffers.
        vscode.workspace.textDocuments.forEach(openDoc);
    }).catch(e => {
        output.appendLine("initialize failed: " + e.message);
    });

    // Wire events.
    context.subscriptions.push(
        vscode.workspace.onDidOpenTextDocument(openDoc),
        vscode.workspace.onDidChangeTextDocument(changeDoc),
        vscode.workspace.onDidCloseTextDocument(closeDoc),
        vscode.languages.registerDocumentSymbolProvider(
            { language: "krypton" }, symbolProvider()
        ),
        vscode.languages.registerCompletionItemProvider(
            { language: "krypton" }, completionProvider()
        )
    );
}

function deactivate() {
    if (!proc) return Promise.resolve();
    return new Promise(resolve => {
        try {
            request("shutdown", null)
                .catch(() => {})
                .then(() => notify("exit", null))
                .then(() => {
                    proc.stdin.end();
                    setTimeout(resolve, 100);
                });
        } catch (_) { resolve(); }
    });
}

module.exports = { activate, deactivate };
