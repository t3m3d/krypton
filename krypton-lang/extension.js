// Krypton language support. The extension speaks framed LSP directly to kls.
"use strict";

const vscode = require("vscode");
const cp = require("child_process");
const fs = require("fs");
const path = require("path");

const MAX_FRAME = 16 * 1024 * 1024;
let current = null;
let output = null;
let diagnostics = null;
let disposed = false;
let lifecycle = Promise.resolve();

function log(message) {
    if (output) output.appendLine(message);
}

function executable(candidate) {
    try {
        fs.accessSync(candidate, process.platform === "win32" ? fs.constants.F_OK : fs.constants.X_OK);
        return fs.statSync(candidate).isFile();
    } catch (_) {
        return false;
    }
}

function findKlsBinary(extensionPath) {
    const name = process.platform === "win32" ? "kls.exe" : "kls";
    const explicit = vscode.workspace.getConfiguration("krypton").get("kls.path", "");
    if (explicit) {
        if (!path.isAbsolute(explicit) || !executable(explicit)) {
            throw new Error("krypton.kls.path must name an absolute, executable kls file.");
        }
        return explicit;
    }
    const probes = [
        path.join(extensionPath, "server", process.platform + "-" + process.arch, name),
        path.join(extensionPath, name)
    ];
    if (process.platform === "darwin") {
        probes.push("/opt/homebrew/bin/kls", "/usr/local/bin/kls");
    }
    for (const directory of (process.env.PATH || "").split(path.delimiter)) {
        if (directory && path.isAbsolute(directory)) probes.push(path.join(directory, name));
    }
    const root = process.env.KRYPTON_ROOT || process.env.KRYPTON;
    if (root && path.isAbsolute(root)) {
        probes.push(path.join(root, name));
        if (process.platform === "darwin") probes.push(path.join(root, "compiler", "macos_arm64", name));
    }
    for (const candidate of probes) {
        if (executable(candidate)) return candidate;
    }
    throw new Error(name + " not found. Install Krypton or set krypton.kls.path. Highlighting and snippets remain available.");
}

function range(value) {
    return new vscode.Range(value.start.line, value.start.character, value.end.line, value.end.character);
}

class Session {
    constructor(binary) {
        this.binary = binary;
        this.child = null;
        this.buffer = Buffer.alloc(0);
        this.pending = new Map();
        this.versions = new Map();
        this.nextId = 1;
        this.ready = false;
        this.closed = false;
        this.stopPromise = null;
        this.trace = vscode.workspace.getConfiguration("krypton").get("kls.trace", false);
    }

    rejectPending(error) {
        for (const entry of this.pending.values()) {
            clearTimeout(entry.timer);
            entry.reject(error);
        }
        this.pending.clear();
    }

    fail(error) {
        this.ready = false;
        this.rejectPending(error);
        log("kls: " + error.message);
    }

    send(method, params, request, timeout = 5000) {
        if (!this.child || this.closed || this.child.exitCode !== null) {
            return Promise.reject(new Error("kls is not running"));
        }
        const message = { jsonrpc: "2.0", method, params };
        let result = Promise.resolve(null);
        if (request) {
            message.id = this.nextId++;
            result = new Promise((resolve, reject) => {
                const timer = setTimeout(() => {
                    this.pending.delete(message.id);
                    reject(new Error("kls timeout: " + method));
                }, timeout);
                this.pending.set(message.id, { resolve, reject, timer });
            });
        }
        const body = Buffer.from(JSON.stringify(message), "utf8");
        const header = Buffer.from("Content-Length: " + body.length + "\r\n\r\n", "ascii");
        if (this.trace) log("→ " + method + " (" + body.length + " bytes)");
        try {
            this.child.stdin.write(Buffer.concat([header, body]));
        } catch (error) {
            this.fail(error);
            if (!request) return Promise.reject(error);
        }
        return result;
    }

    notify(method, params) {
        this.send(method, params, false).catch(error => {
            if (!this.closed) log(method + ": " + error.message);
        });
    }

    request(method, params, timeout) {
        if (!this.ready && method !== "initialize" && method !== "shutdown") {
            return Promise.reject(new Error("kls has not initialized"));
        }
        return this.send(method, params, true, timeout);
    }

    onData(chunk) {
        if (this.closed) return;
        this.buffer = Buffer.concat([this.buffer, chunk]);
        while (this.buffer.length) {
            const end = this.buffer.indexOf("\r\n\r\n");
            if (end < 0) {
                if (this.buffer.length > 8192) this.protocolError("Oversized LSP header");
                return;
            }
            const header = this.buffer.subarray(0, end).toString("ascii");
            const match = /^Content-Length:\s*(\d+)\s*$/im.exec(header);
            const length = match ? Number(match[1]) : -1;
            if (end > 8192 || !Number.isSafeInteger(length) || length < 0 || length > MAX_FRAME) {
                this.protocolError("Invalid LSP Content-Length");
                return;
            }
            const total = end + 4 + length;
            if (this.buffer.length < total) return;
            const body = this.buffer.subarray(end + 4, total).toString("utf8");
            this.buffer = this.buffer.subarray(total);
            try {
                this.handle(JSON.parse(body));
            } catch (error) {
                this.protocolError("Invalid LSP message: " + error.message);
                return;
            }
        }
    }

    protocolError(message) {
        this.fail(new Error(message));
        this.closed = true;
        this.buffer = Buffer.alloc(0);
        if (this.child) this.child.kill();
    }

    handle(message) {
        if (this.trace) log("← " + (message.method || "response " + message.id));
        if (message.id != null && !message.method && this.pending.has(message.id)) {
            const entry = this.pending.get(message.id);
            this.pending.delete(message.id);
            clearTimeout(entry.timer);
            if (message.error) entry.reject(new Error(message.error.message || "kls error"));
            else entry.resolve(message.result);
            return;
        }
        if (message.method && message.id != null) {
            const reply = Buffer.from(JSON.stringify({
                jsonrpc: "2.0", id: message.id,
                error: { code: -32601, message: "Unsupported client request: " + message.method }
            }), "utf8");
            this.child.stdin.write(Buffer.concat([
                Buffer.from("Content-Length: " + reply.length + "\r\n\r\n", "ascii"), reply
            ]));
            return;
        }
        if (message.method !== "textDocument/publishDiagnostics" || current !== this) return;
        const params = message.params || {};
        if (!this.versions.has(params.uri)) return;
        if (params.version != null && params.version < this.versions.get(params.uri)) return;
        const severities = [
            vscode.DiagnosticSeverity.Error, vscode.DiagnosticSeverity.Error,
            vscode.DiagnosticSeverity.Warning, vscode.DiagnosticSeverity.Information,
            vscode.DiagnosticSeverity.Hint
        ];
        const items = (params.diagnostics || []).map(item => {
            const diagnostic = new vscode.Diagnostic(range(item.range), item.message,
                severities[item.severity] ?? vscode.DiagnosticSeverity.Error);
            diagnostic.source = "kls";
            return diagnostic;
        });
        diagnostics.set(vscode.Uri.parse(params.uri), items);
    }

    async start() {
        log("Starting " + this.binary);
        const folder = (vscode.workspace.workspaceFolders || []).find(item => item.uri.scheme === "file");
        this.child = cp.spawn(this.binary, [], {
            stdio: ["pipe", "pipe", "pipe"],
            cwd: folder ? folder.uri.fsPath : undefined,
            shell: false
        });
        this.child.stdout.on("data", chunk => this.onData(chunk));
        this.child.stderr.on("data", chunk => log("[kls.stderr] " + chunk.toString()));
        this.child.stdin.on("error", error => this.fail(error));
        this.child.on("error", error => this.fail(error));
        this.child.on("exit", code => {
            this.closed = true;
            this.ready = false;
            this.rejectPending(new Error("kls exited (" + code + ")"));
            this.versions.clear();
            if (current === this) diagnostics.clear();
            log("kls exited (" + code + ")");
        });
        await this.request("initialize", {
            processId: process.pid,
            rootUri: folder ? folder.uri.toString() : null,
            capabilities: { general: { positionEncodings: ["utf-16"] } }
        }, 10000);
        if (this.closed || this.stopPromise || disposed) return;
        this.notify("initialized", {});
        this.ready = true;
        vscode.workspace.textDocuments.forEach(document => this.open(document));
        log("kls ready");
    }

    open(document) {
        if (!this.ready || document.languageId !== "krypton") return;
        const uri = document.uri.toString();
        if (this.versions.has(uri)) return;
        this.versions.set(uri, document.version);
        this.notify("textDocument/didOpen", { textDocument: {
            uri, languageId: "krypton", version: document.version, text: document.getText()
        } });
    }

    change(event) {
        const document = event.document;
        if (!this.ready || document.languageId !== "krypton") return;
        if (!this.versions.has(document.uri.toString())) {
            this.open(document);
            return;
        }
        this.versions.set(document.uri.toString(), document.version);
        this.notify("textDocument/didChange", {
            textDocument: { uri: document.uri.toString(), version: document.version },
            contentChanges: [{ text: document.getText() }]
        });
    }

    close(document) {
        const uri = document.uri.toString();
        if (!this.versions.delete(uri)) return;
        diagnostics.delete(document.uri);
        if (this.ready) this.notify("textDocument/didClose", { textDocument: { uri } });
    }

    stop() {
        if (!this.stopPromise) this.stopPromise = this.shutdown();
        return this.stopPromise;
    }

    async shutdown() {
        this.ready = false;
        if (!this.child || this.closed) return;
        try { await this.request("shutdown", null, 1000); } catch (_) { /* bounded shutdown */ }
        if (!this.closed) {
            this.notify("exit", null);
            this.child.stdin.end();
            await new Promise(resolve => {
                const timer = setTimeout(() => { this.child.kill(); resolve(); }, 1000);
                this.child.once("exit", () => { clearTimeout(timer); resolve(); });
            });
        }
        this.closed = true;
        this.rejectPending(new Error("kls stopped"));
        this.versions.clear();
    }
}

function completionItem(item) {
    const label = typeof item.label === "string" ? item.label : item.label.label;
    const canonical = label === "kp" ? "print" : label;
    const result = new vscode.CompletionItem(canonical,
        item.kind != null ? item.kind - 1 : vscode.CompletionItemKind.Text);
    if (item.detail) result.detail = item.detail;
    if (item.sortText) result.sortText = item.sortText;
    if (item.filterText) result.filterText = item.filterText;
    if (item.documentation) result.documentation = typeof item.documentation === "string"
        ? item.documentation : item.documentation.value;
    if (item.insertText != null || label === "kp") {
        let text = item.insertText == null ? canonical : item.insertText;
        if (label === "kp") text = text.replace(/^kp\b/, "print");
        result.insertText = item.insertTextFormat === 2 ? new vscode.SnippetString(text) : text;
    }
    if (item.textEdit && item.textEdit.range) {
        result.range = range(item.textEdit.range);
        const text = label === "kp" ? item.textEdit.newText.replace(/^kp\b/, "print") : item.textEdit.newText;
        result.insertText = item.insertTextFormat === 2 ? new vscode.SnippetString(text) : text;
    }
    return result;
}

async function restart(context) {
    if (current) {
        const previous = current;
        current = null;
        await previous.stop();
    }
    diagnostics.clear();
    if (disposed) return;
    if (vscode.workspace.isTrusted === false) {
        log("Restricted Mode: highlighting and snippets only.");
        return;
    }
    if (!vscode.workspace.getConfiguration("krypton").get("kls.enabled", true)) {
        log("kls disabled by configuration.");
        return;
    }
    current = new Session(findKlsBinary(context.extensionPath));
    const session = current;
    try {
        await session.start();
    } catch (error) {
        if (current === session) current = null;
        await session.stop();
        throw error;
    }
}

function activate(context) {
    disposed = false;
    output = vscode.window.createOutputChannel("Krypton LSP");
    diagnostics = vscode.languages.createDiagnosticCollection("kls");
    log("Krypton extension " + require("./package.json").version + " activated (.k, .ks, .htk)");
    const schedule = () => {
        lifecycle = lifecycle.catch(() => {}).then(() => restart(context)).catch(error => {
            log(error.stack || error.message);
            vscode.window.showWarningMessage("Krypton: " + error.message);
        });
        return lifecycle;
    };
    const selector = [{ language: "krypton", scheme: "file" }, { language: "krypton", scheme: "untitled" }];
    context.subscriptions.push(output, diagnostics,
        vscode.commands.registerCommand("krypton.restartLanguageServer", schedule),
        vscode.workspace.onDidOpenTextDocument(document => { if (current) current.open(document); }),
        vscode.workspace.onDidChangeTextDocument(event => { if (current) current.change(event); }),
        vscode.workspace.onDidCloseTextDocument(document => { if (current) current.close(document); }),
        vscode.workspace.onDidChangeConfiguration(event => {
            if (event.affectsConfiguration("krypton.kls")) schedule();
        }),
        vscode.languages.registerDocumentSymbolProvider(selector, {
            async provideDocumentSymbols(document) {
                if (!current || !current.ready) return [];
                try {
                    const symbols = await current.request("textDocument/documentSymbol",
                        { textDocument: { uri: document.uri.toString() } });
                    const convert = symbol => {
                        const result = new vscode.DocumentSymbol(symbol.name, symbol.detail || "",
                            symbol.kind != null ? symbol.kind - 1 : vscode.SymbolKind.Function,
                            range(symbol.range), range(symbol.selectionRange || symbol.range));
                        result.children = (symbol.children || []).map(convert);
                        return result;
                    };
                    return Array.isArray(symbols) ? symbols.map(convert) : [];
                } catch (_) { return []; }
            }
        }),
        vscode.languages.registerCompletionItemProvider(selector, {
            async provideCompletionItems(document, position) {
                if (!current || !current.ready) return [];
                try {
                    const response = await current.request("textDocument/completion", {
                        textDocument: { uri: document.uri.toString() },
                        position: { line: position.line, character: position.character }
                    });
                    const items = Array.isArray(response) ? response : (response && response.items) || [];
                    const hasPrint = items.some(item => item.label === "print");
                    const completions = items.filter(item => !(hasPrint && item.label === "kp")).map(completionItem);
                    return response && response.isIncomplete ? new vscode.CompletionList(completions, true) : completions;
                } catch (_) { return []; }
            }
        })
    );
    if (vscode.workspace.onDidGrantWorkspaceTrust) {
        context.subscriptions.push(vscode.workspace.onDidGrantWorkspaceTrust(schedule));
    }
    return schedule();
}

function deactivate() {
    disposed = true;
    const session = current;
    current = null;
    return session ? session.stop() : Promise.resolve();
}

module.exports = { activate, deactivate };
