# objk demos — pure-Krypton native GUI

Native Cocoa apps written in pure Krypton, no Obj-C source, on the objk FFI
(`compiler/macos_arm64/macho_arm64_self.k` + `stdlib/cocoa.k` + `stdlib/objc.k`).

Build + run (dev tree):

    KRYPTON_ROOT="$PWD" compiler/macos_arm64/kcc-arm64 examples/objk/kryedit.ks > /tmp/x.kir
    compiler/macos_arm64/macho_host --ir /tmp/x.kir /tmp/x   # (host built by `kcc`)
    chmod +x /tmp/x && /tmp/x src/buf.k

- **kryedit.ks** — a syntax-highlighting text editor (open a file as arg, edit, Save).
- **kshell.ks** — kcode-style shell: menu + file-table sidebar + editor, row-click loads the editor (Krypton data source + delegate).
- **highlight.ks** — colored ranges on an NSTextView via NSTextStorage.
- **term_grid.ks** — custom NSView drawRect: a terminal grid (colored cells + glyphs).
- **table.ks** — NSTableView driven by a pure-Krypton multi-method data source.
- **human_ui.ks** — `k:okui` app-facing Objective-K style: plain words for window, fields, buttons, state, clipboard, defaults, and URL open.
- **controls.ks** — `k:objk` facade: checkbox, combo box, slider, progress, defaults, clipboard, URL open.
- **windows_controls.ks** — `stdlib/objkwin.k` facade: Windows-native controls, events, shell open, text fields, theme color.
- **choc_window.ks** — `stdlib/choc.k` native UI kit smoke app, currently Windows-backed.

Note: every callback/delegate method is a plain Krypton func used as an Obj-C method
IMP — objc passes (self, _cmd, …) in x0/x1/… = Krypton's register convention.

Windows uses the same Objective-K naming style without Cocoa/libobjc. App code
should prefer `k:okui`; macOS uses `stdlib/okui.k`, Windows routes `k:okui` to
`stdlib/okui_win.k`, and both load the shared app-facing API in
`stdlib/okui_core.k`. Windows then resolves `k:objk` through
`stdlib/objkwin.k` so OKUI sits on Forge's Choc/Win32 backend. Click dispatch
passes Obj-K-shaped args: `(self, cmd, sender)`, and old no-arg handlers still
work.

Focused OKUI check:

    KRYPTON_ROOT="$PWD" bootstrap/kcc_driver_macos_aarch64 -r scripts/check_okui.ks

Windows parity check:

    kcc.exe -r scripts/check_okui.ks

## Objective-K Focus

`objective_k_focus.ks` is a macOS app built on the K-owned additions. It uses:

- `Scoreable` protocol with required methods
- runtime-checked `combine(Focus) -> Focus` dispatch
- owned work/rest models in application state
- weak peer links that do not form a cycle
- reference-counted K-owned text names
- cleanup hooks released through Quit
- OKUI controls following system theme

Build:

```sh
export KRYPTON_ROOT="$PWD"
./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-objk-app.ks \
  examples/objk/objective_k_focus.ks objective_k_focus
open dist/objective_k_focus.app
```

Run native integration smoke through `scripts/check_objk_runtime_macos.ks --gui`.

## macOS K-Owned Counter

`k_owned_counter_macos.ks` uses `k:objk_runtime_macos` for its model and
`k:okui` for native controls. `.ks` and `.k` compile with the same compiler;
this demo introduces no new class syntax.

From checkout root on macOS arm64:

```sh
export KRYPTON_ROOT="$PWD"
./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-objk-app.ks \
  examples/objk/k_owned_counter_macos.ks objk_counter
open dist/objk_counter.app
```

K state owns the counter model. Buttons dispatch to it and update the native
label. `Quit`/Command-Q releases state and its model, then terminates the app.
Native controls stay outside K integer fields. Do not stringify window handles;
native selectors require pointer identity.

Check integration rather than relying only on a visible window:

```sh
./bootstrap/kcc_driver_macos_aarch64 -r scripts/check_objk_runtime_macos.ks --gui
```

This verifies actions reach value 1 and model cleanup runs exactly once.
Without `--gui`, it checks object behavior and stale-ID safety without opening
windows. Other examples may use older Apple-backed object APIs; they are not
proof that every object has migrated to the K-owned core.

Contracts and remaining work: [spec](../../spec.md),
[runtime guide](../../docs/objk_runtime_macos.md),
[grammar](../../docs/spec/grammar.md#objective-k-runtime-boundary).
