# Import paths

Krypton uses Odin-style import prefixes — short namespace aliases that
encode both the source folder and the file extension, so you never type
`.k` or `.krh` in an import line.

```krypton
import "k:gui"           // → <install>/stdlib/gui.k
import "core:gui"        // long-form alias for k:
import "head:user32"     // → <install>/headers/user32.krh
import "headers:user32"  // long-form alias for head:
```

## Prefix table

| Prefix     | Resolves to                  | What lives there                                |
|------------|-------------------------------|------------------------------------------------|
| `k:`       | `<install>/stdlib/foo.k`     | Krypton stdlib modules — `gui`, `fs`, `proc`, `json_emit`, `csv`, `path`, etc. |
| `core:`    | `<install>/stdlib/foo.k`     | Long-form alias for `k:`. Use whichever reads better. |
| `head:`    | `<install>/headers/foo.krh`  | C-binding headers — `user32`, `gdi32`, `windows`, `winsock`, `math`, `conio`, `process`, etc. |
| `headers:` | `<install>/headers/foo.krh`  | Long-form alias for `head:`. |

`<install>` is the Krypton install root — `C:\krypton` on Windows.

## What's in `stdlib/` vs `headers/`

- **`stdlib/*.k`** — pure Krypton modules. Implement higher-level functionality
  (GUI widgets, JSON encoding, file system helpers) using Krypton itself plus
  whatever low-level primitives they need.
- **`headers/*.krh`** — Krypton-flavoured *binding* files. Each one declares
  external functions inside a `jxt { }` block, mapping a Win32 / POSIX / CRT
  API surface into Krypton call sites. They're written in Krypton syntax —
  not C — but their contents resolve to native code at link time (via the
  IAT for Win32, via gcc link line for the C-emit path).

Example `.krh` (excerpt from `head:user32`):

```krypton
jxt {
    c "windows.h"
    func CreateWindowExA(exStyle, className, title, style, x, y, w, h,
                         parent, menu, instance, lpParam)
    func DestroyWindow(hwnd)
    func ShowWindow(hwnd, cmd)
}
```

Krypton code that imports it gets `CreateWindowExA(...)` etc. as if they
were ordinary functions.

## Backwards compatibility

The old un-prefixed forms still resolve, so existing code keeps building:

```krypton
import "stdlib/gui.k"   // legacy — still works, finds <install>/stdlib/gui.k
import "windows.krh"    // legacy — still works, finds <install>/headers/windows.krh
```

Migration is opt-in. Touch a file, swap to the new form when convenient.

## Source-relative imports (project-local code)

Imports without a prefix and without an extension that maps to a known
folder are resolved **relative to the importing file**:

```krypton
import "lib/utils.k"      // <this-file's-dir>/lib/utils.k
import "../shared/log.k"  // sibling-dir lookup
```

This is for code that belongs to your own project (not stdlib, not a
Win32 binding). No prefix needed.

## What's *not* a prefix

The colon-prefix system reserves the leading `<short>:` syntax. Avoid
collisions with other uses of colon:

- Windows drive letters: `C:\foo\bar.k` is fine — the resolver requires
  the prefix part to be at most 7 characters AND not match a recognised
  prefix. `C:` and `D:` etc. fall through to the legacy resolution path.
- Future: `vendor:` (third-party libs vendored into project) and `local:`
  (project's own modules) are not yet shipped but reserved for that
  meaning. Don't use them as your own prefixes.

## Adding a new official prefix

Edit `compiler/compile.k` — search for `Odin-style \`prefix:name\` imports`
and add a new branch:

```krypton
if prefix == "vendor" { fullPath = projectRoot + "/vendor/" + sub + ".k" }
```

Then rebuild kcc (canonical path is in `project_v181_shipped.md`).

## Removed: `--headers` flag

Versions through 1.8.3 accepted `kcc --headers PATH source.k` to override
the headers location. As of 1.8.4 the install root is fixed at
`C:\krypton` and there is no `--headers` flag. The `head:` / `headers:`
prefixes resolve relative to it. (If you genuinely need a different
install root, install Krypton there and the resolver finds it; the layout
is not configurable per invocation.)
