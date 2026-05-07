# Krypton GUI — Tier Roadmap

How `stdlib/gui.k` evolves from "Krypton + embedded C" to "pure
Krypton GUI bindings". Each tier moves more code out of `cfunc { }`
and into Krypton, eventually depending only on `jxt { }` Win32
declarations.

| Tier | Krypton / C ratio | What blocks the next tier |
|------|------------------:|---------------------------|
| 1 (today) | ~12 / 150 lines | Krypton wrappers only; cfunc owns everything |
| 2 | ~80 / 70 lines | Message pump + struct setup move to Krypton; cfunc keeps WindowProc + class registration |
| 3 | ~150 / 0 lines | Pure Krypton; cfunc gone |

---

## Tier 1 — current state (shipped)

`stdlib/gui.k` as written. Krypton side has 12 single-line wrappers
that delegate to a 150-line `cfunc { }` block which:

- Maintains the control-id → callback table
- Implements WindowProc
- Registers the window class
- Calls `CreateWindowExA`, `SetWindowTextA`, `MessageBoxA`, etc.
- Handles `DwmSetWindowAttribute` for dark titlebar

**What's pure Krypton:**
- The user-facing API (`guiInit`, `guiWindow`, `guiButton`, ...)
- Public callback registration via `funcptr()`

**What's C:**
- Everything else.

**Why this tier first:** ships now without language changes. Lets us
validate the API surface, ergonomics, and demo-quality look.

---

## Tier 2 — Krypton owns the loop + structs (1 session)

Move what's already possible into Krypton. The win_*.k examples in
`examples/` already operate at this tier — pure-Krypton message
pumps that call jxt-declared `GetMessageA` / `DispatchMessageA`.

**Code that moves to Krypton:**

| Currently in cfunc | After Tier 2 |
|---|---|
| Message loop (`GetMessageA` etc.) | pure Krypton `guiRun()` |
| `WNDCLASSEXA` / `MSG` setup | `structNew("WNDCLASSEXA")` + `setField(...)` |
| `CreateWindowExA` per-control wrappers | direct jxt calls |
| `SetWindowTextA` / `GetWindowTextA` | direct jxt calls |
| Constants like `WS_CHILD | WS_VISIBLE` | numeric literals or pre-set Krypton constants |

**What stays in cfunc:**

- WindowProc (LRESULT CALLBACK) — Win32 demands a C function pointer with stdcall. No Krypton-side equivalent today.
- `RegisterClassExA` only because it stores a pointer to that WindowProc.
- `DwmSetWindowAttribute` — needs `LoadLibrary` + `GetProcAddress` because it isn't in stock headers; can be moved to a Krypton wrapper if we add `dwmapi.krh` and accept it failing on pre-Win10.

**Prereqs (already met):**
- jxt declarations for user32/gdi32 (have them)
- `structNew` / `setField` / `getField` (have them)
- `funcptr()` (works on C path)

**Concrete tasks:**

1. Add Krypton constants module `stdlib/win32_const.k` with at minimum:
   ```
   func WS_OVERLAPPEDWINDOW() { emit 0xCF0000 }
   func WS_CHILD() { emit 0x40000000 }
   func WS_VISIBLE() { emit 0x10000000 }
   func BS_PUSHBUTTON() { emit 0 }
   ...
   ```
   ~50 entries cover all `headers/*.krh`-declared APIs we currently use.

2. Rewrite `stdlib/gui.k` `krGuiButton` / `krGuiLabel` / `krGuiTextInput` etc. as pure Krypton wrapping `CreateWindowExA` jxt call.

3. Move message pump from `krGuiRun` into pure Krypton (already an example pattern).

4. Keep cfunc only for: WindowProc, class registration, dispatch table.

**Estimated effort:** 1 session.

---

## Tier 3 — pure Krypton (multi-session)

cfunc gone entirely. Requires Krypton language features that don't
exist yet.

**Language features to land first:**

1. **Native pipeline `funcptr()` support.** Today `funcptr(name)` only emits a C identifier reference, which works in the C-codegen path because the func is also a C identifier in the generated source. The native PE backend would need to:
   - Emit Krypton functions with a stable export name + C calling convention
   - Provide a `funcptr` operator that returns the absolute address

2. **stdcall calling convention support.** Win32 callbacks (WindowProc, hook procs, etc.) are stdcall on x86 / "Microsoft x64" on x64. The native backend already emits Microsoft x64 (it's the only x64 ABI on Windows), so x64 is technically free. x86 would need a new attribute on `func`.

3. **C-callable Krypton function definition.** Today every Krypton func returns `char*`. A WindowProc must return `LRESULT` (i.e. `int64_t` on x64). Either:
   - Add type annotations to func declarations (`func krWinProc(hwnd, msg, wp, lp) -> long_long`)
   - Or implicitly convert the `char*` return to `(LRESULT)` — works because Krypton functions return zero-encoded integers as strings; `atoi` at the boundary

4. **A `headers/win32_macros.krh` for ALL the constants** (WS_*, MB_*, BS_*, ES_*, SS_*, WM_*, ...) — generated from the Win32 SDK headers, ~500 entries.

**Concrete tasks (after language prereqs):**

1. Generate `headers/win32_macros.krh` from MinGW headers
2. Rewrite WindowProc as a Krypton `callback` func returning `long_long`
3. Rewrite `RegisterClassExA` setup using Krypton-level structNew + funcptr to the WindowProc
4. Drop the cfunc block

**Estimated effort:** 3-5 sessions split between language and stdlib.

---

## Tradeoff summary

| Tier | Self-host story | Time to ship | User-visible cost |
|------|---|---|---|
| 1 | "Krypton + cfunc" — honest mixed | 0 (done) | None |
| 2 | "Krypton with small C glue" | 1 session | None — same API, smaller C surface |
| 3 | "Pure Krypton GUI bindings" | 3-5 sessions | None — same API, requires kcc upgrades |

Recommended path: ship Tier 1 (already done), do Tier 2 next when GUI usage starts compounding, defer Tier 3 to the same epoch as native-callback support work for kls/kbackend.

---

## Cross-references

- `examples/win_*.k` — Tier-2-style example programs (pure-Krypton message pump, cfunc WindowProc only).
- `docs/v20_plan.md` — broader 2.0 roadmap; the native callback work belongs there.
- `headers/user32.krh`, `headers/gdi32.krh`, `headers/comctl32.krh` — jxt declarations Tier 2 leans on.
