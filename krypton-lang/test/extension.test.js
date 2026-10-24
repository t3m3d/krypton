"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const cp = require("node:child_process");
const { EventEmitter } = require("node:events");
const { pathToFileURL } = require("node:url");

const extensionPath = process.env.KRYPTON_EXTENSION_ROOT || path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(extensionPath, "extension.js"), "utf8");
const turn = () => new Promise(resolve => setImmediate(resolve));

function frame(message) {
    const body = Buffer.from(JSON.stringify(message));
    return Buffer.concat([Buffer.from("Content-Length: " + body.length + "\r\n\r\n"), body]);
}

class FakeChild extends EventEmitter {
    constructor(options) {
        super();
        this.options = options;
        this.exitCode = null;
        this.sent = [];
        this.stdout = new EventEmitter();
        this.stderr = new EventEmitter();
        this.stdin = new EventEmitter();
        this.stdin.end = () => {};
        this.stdin.write = bytes => {
            const end = bytes.indexOf("\r\n\r\n");
            const message = JSON.parse(bytes.subarray(end + 4).toString());
            this.sent.push(message);
            if (message.method === "initialize" && options.delayInitialize) {
                this.initialize = () => this.reply(message.id, { capabilities: {} });
            } else if (message.method === "initialize") {
                setImmediate(() => options.initializeError
                    ? this.stdout.emit("data", frame({ jsonrpc: "2.0", id: message.id,
                        error: { code: -32603, message: "fixture rejected initialization" } }))
                    : this.reply(message.id, { capabilities: {} }));
            } else if (message.method === "shutdown") {
                setImmediate(() => this.reply(message.id, null));
            } else if (message.method === "exit") {
                setImmediate(() => this.finish(0));
            } else if (message.method === "textDocument/completion" && !options.deferCompletion) {
                setImmediate(() => this.reply(message.id, options.completions || [
                    { label: "kp", kind: 3 }, { label: "print", kind: 3, insertText: "print($1)", insertTextFormat: 2 }
                ]));
            } else if (message.method === "textDocument/documentSymbol") {
                setImmediate(() => this.reply(message.id, [{
                    name: "Counter", kind: 5, range: positionRange(), selectionRange: positionRange(),
                    children: [{ name: "score", kind: 6, range: positionRange(), selectionRange: positionRange() }]
                }]));
            }
            return true;
        };
    }
    reply(id, result) {
        const bytes = frame({ jsonrpc: "2.0", id, result });
        this.stdout.emit("data", bytes.subarray(0, 7));
        this.stdout.emit("data", bytes.subarray(7, 24));
        this.stdout.emit("data", bytes.subarray(24));
    }
    finish(code) {
        if (this.exitCode !== null) return;
        this.exitCode = code;
        this.emit("exit", code);
    }
    kill() { this.killed = true; this.finish(1); return true; }
}
function positionRange() {
    return { start: { line: 0, character: 0 }, end: { line: 0, character: 5 } };
}

function harness(options = {}) {
    const hooks = {};
    const children = [];
    const messages = [];
    const warnings = [];
    const published = new Map();
    const uri = {
        scheme: "file", fsPath: "/tmp/brain-krypton-extension-test.k",
        toString() { return "file:///tmp/brain-krypton-extension-test.k"; }
    };
    const document = { languageId: "krypton", uri, version: 1, text: 'print("🦋")',
        getText() { return this.text; } };
    const configuration = { "kls.path": options.binary || process.execPath,
        "kls.enabled": true, "kls.trace": false };
    const listen = name => callback => { hooks[name] = callback; return { dispose() {} }; };
    const vscode = {
        workspace: {
            isTrusted: options.trusted !== false, textDocuments: [document], workspaceFolders: [],
            getConfiguration() { return { get(key, fallback) {
                return Object.hasOwn(configuration, key) ? configuration[key] : fallback;
            } }; },
            onDidOpenTextDocument: listen("open"), onDidChangeTextDocument: listen("change"),
            onDidCloseTextDocument: listen("close"), onDidChangeConfiguration: listen("configuration"),
            onDidGrantWorkspaceTrust: listen("trust")
        },
        window: {
            createOutputChannel() { return { appendLine(text) { messages.push(text); }, dispose() {} }; },
            showWarningMessage(text) { warnings.push(text); }
        },
        languages: {
            createDiagnosticCollection() {
                return { set(uri, items) { published.set(uri.toString(), items); },
                    clear() { published.clear(); }, delete(uri) { published.delete(uri.toString()); }, dispose() {} };
            },
            registerDocumentSymbolProvider(selector, provider) { hooks.symbols = provider; return { dispose() {} }; },
            registerCompletionItemProvider(selector, provider) { hooks.completions = provider; return { dispose() {} }; }
        },
        commands: { registerCommand(name, handler) { hooks.restart = handler; return { dispose() {} }; } },
        Range: class { constructor(a, b, c, d) { Object.assign(this, { a, b, c, d }); } },
        Diagnostic: class { constructor(range, message, severity) { Object.assign(this, { range, message, severity }); } },
        DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2, Hint: 3 },
        CompletionItemKind: { Text: 0 }, SymbolKind: { Function: 11 },
        CompletionItem: class { constructor(label, kind) { Object.assign(this, { label, kind }); } },
        SnippetString: class { constructor(value) { this.value = value; } },
        DocumentSymbol: class { constructor(name) { this.name = name; this.children = []; } },
        CompletionList: class { constructor(items, isIncomplete) { Object.assign(this, { items, isIncomplete }); } },
        Uri: { parse(value) { return { toString() { return value; } }; } }
    };
    const realCp = options.real ? cp : {
        spawn(binary, args, spawnOptions) {
            const child = new FakeChild(options);
            child.binary = binary;
            child.spawnOptions = spawnOptions;
            children.push(child);
            if (options.spawnError) setImmediate(() => {
                child.emit("error", new Error("fixture ENOENT"));
                child.finish(1);
            });
            return child;
        }
    };
    const module = { exports: {} };
    const sandbox = {
        module, exports: module.exports, Buffer, process, setTimeout, clearTimeout,
        require(name) {
            if (name === "vscode") return vscode;
            if (name === "child_process") return realCp;
            if (name === "./package.json") return JSON.parse(fs.readFileSync(path.join(extensionPath, "package.json"), "utf8"));
            return require(name);
        }
    };
    vm.runInNewContext(source, sandbox, { filename: path.join(extensionPath, "extension.js") });
    const context = { extensionPath, subscriptions: [] };
    return { api: module.exports, context, hooks, children, messages, warnings, published,
        document, vscode, configuration, activate() { return module.exports.activate(context); } };
}

test("initialization sends latest Unicode document once, never before handshake", async () => {
    const h = harness({ delayInitialize: true });
    const activating = h.activate();
    await turn();
    assert.equal(h.children.length, 1);
    const child = h.children[0];
    h.document.text = 'print("updated 🦋")';
    h.document.version = 2;
    h.hooks.change({ document: h.document });
    assert.deepEqual(child.sent.map(item => item.method), ["initialize"]);
    child.initialize();
    await activating;
    const opened = child.sent.filter(item => item.method === "textDocument/didOpen");
    assert.equal(opened.length, 1);
    assert.equal(opened[0].params.textDocument.text, h.document.text);
    assert.equal(opened[0].params.textDocument.version, 2);
    const items = await h.hooks.completions.provideCompletionItems(h.document, { line: 0, character: 0 });
    assert.deepEqual(Array.from(items, item => item.label), ["print"]);
    assert.equal(items[0].insertText.value, "print($1)");
    const symbols = await h.hooks.symbols.provideDocumentSymbols(h.document);
    assert.equal(symbols[0].children[0].name, "score");
    await h.api.deactivate();
    assert.equal(child.exitCode, 0);
});

test("old kls kp completion becomes canonical print", async () => {
    const h = harness({ completions: [{ label: "kp", kind: 3, insertText: "kp($1)", insertTextFormat: 2 }] });
    await h.activate();
    const items = await h.hooks.completions.provideCompletionItems(h.document, { line: 0, character: 0 });
    assert.equal(items[0].label, "print");
    assert.equal(items[0].insertText.value, "print($1)");
    await h.api.deactivate();
});

test("stale and closed-document diagnostics do not reappear", async () => {
    const h = harness(); await h.activate();
    h.document.version = 3; h.hooks.change({ document: h.document });
    const diagnostic = { range: positionRange(), message: "fixture 🦋", severity: 2 };
    const publish = version => h.children[0].stdout.emit("data", frame({
        jsonrpc: "2.0", method: "textDocument/publishDiagnostics",
        params: { uri: h.document.uri.toString(), version, diagnostics: [diagnostic] }
    }));
    publish(2); assert.equal(h.published.size, 0);
    publish(3); assert.equal(h.published.values().next().value[0].severity, 1);
    h.hooks.close(h.document); publish(3); assert.equal(h.published.size, 0);
    await h.api.deactivate();
});

test("server exit settles pending completion immediately", async () => {
    const h = harness({ deferCompletion: true }); await h.activate();
    const pending = h.hooks.completions.provideCompletionItems(h.document, { line: 0, character: 0 });
    h.children[0].finish(1);
    assert.equal((await pending).length, 0);
    await h.api.deactivate();
});

test("malformed oversized frame terminates server rather than buffering indefinitely", async () => {
    const h = harness(); await h.activate();
    h.children[0].stdout.emit("data", Buffer.from("Content-Length: 999999999\r\n\r\n"));
    assert.equal(h.children[0].killed, true);
    await h.api.deactivate();
});

test("Restricted Mode never starts kls; granting trust starts it", async () => {
    const h = harness({ trusted: false }); await h.activate();
    assert.equal(h.children.length, 0);
    h.vscode.workspace.isTrusted = true; await h.hooks.trust();
    assert.equal(h.children.length, 1);
    await h.api.deactivate();
});

test("restart shuts down old server before opening replacement", async () => {
    const h = harness(); await h.activate(); await h.hooks.restart();
    assert.equal(h.children.length, 2);
    assert.equal(h.children[0].exitCode, 0);
    assert.equal(h.children[1].sent.filter(item => item.method === "textDocument/didOpen").length, 1);
    await h.api.deactivate();
});

test("invalid configured path warns and preserves syntax-only operation", async () => {
    const h = harness({ binary: "/no-such-krypton-fixture/kls" }); await h.activate();
    assert.equal(h.children.length, 0); assert.equal(h.warnings.length, 1);
    assert.equal((await h.hooks.completions.provideCompletionItems(h.document, { line: 0, character: 0 })).length, 0);
    await h.api.deactivate();
});

test("spawn error does not leave pending initialization requests", async () => {
    const h = harness({ delayInitialize: true, spawnError: true }); await h.activate();
    assert.equal(h.warnings.length, 1);
    await h.api.deactivate();
});

test("rejected initialization shuts down the child and allows restart", async () => {
    const options = { initializeError: true };
    const h = harness(options); await h.activate();
    assert.equal(h.warnings.length, 1);
    assert.equal(h.children[0].exitCode, 0);
    options.initializeError = false;
    await h.hooks.restart();
    assert.equal(h.children.length, 2);
    assert(h.children[1].sent.some(item => item.method === "textDocument/didOpen"));
    await h.api.deactivate();
});

test("automatic discovery chooses a matching bundled server", async t => {
    const binary = path.join(extensionPath, "server", process.platform + "-" + process.arch,
        process.platform === "win32" ? "kls.exe" : "kls");
    if (!fs.existsSync(binary)) return t.skip("No matching bundled server in source tree");
    const h = harness(); h.configuration["kls.path"] = "";
    await h.activate();
    assert.equal(h.children[0].binary, binary);
    await h.api.deactivate();
});

test("real installed kls handshake, completion, symbols, Unicode, shutdown", {
    skip: !process.env.KRYPTON_TEST_KLS, timeout: 15000
}, async () => {
    const h = harness({ real: true, binary: process.env.KRYPTON_TEST_KLS });
    h.document.uri = { scheme: "file", fsPath: "/tmp/brain-extension-real.k",
        toString() { return pathToFileURL(this.fsPath).toString(); } };
    h.document.text = 'objk protocol Scoreable { require score() -> int }\nobjk object Counter conforms Scoreable { method score() -> int = counterScore }\nfunc counterScore(runtime, self) { emit 42 }\njust run { print("🦋") }\n';
    await h.activate();
    assert.equal(h.warnings.length, 0, h.warnings.join("\n"));
    const items = await h.hooks.completions.provideCompletionItems(h.document, { line: 1, character: 12 });
    assert(items.some(item => item.label === "print"));
    assert(!items.some(item => item.label === "kp"));
    const symbols = await h.hooks.symbols.provideDocumentSymbols(h.document);
    assert(symbols.some(item => item.name === "counterScore"));
    assert(!Array.from(h.published.values()).flat().some(item => item.severity === 0), "Objective-K fixture should not produce errors");
    await h.api.deactivate();
    assert(h.messages.some(message => message === "kls ready"));
    assert(h.messages.some(message => message === "kls exited (0)"));
});
