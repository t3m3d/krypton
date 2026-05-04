# Krypton 1.5.0

**Released**: 2026-05-03

## Highlights

- **First-class booleans.** `true` / `false` literals now stringify to `"true"` and `"false"` instead of `"1"` and `"0"`. `kp(true)` finally prints `true`. Truthiness rules unchanged (`""`, `"0"`, `"false"`, `0` are falsy).
- **Native struct + env runtime on Linux.** `structNew`, `setField`, `getField`, `hasField`, `structFields`, `envNew`, `envSet`, `envGet`, and `reverse` all now produce real native machine code via the Linux ELF backend — no more `UNSUPPORTED` markers, no more crashes, no more falling back to the C path.
- **Windows runtime fixes.** `kp(...)` on Windows native binaries now appends a newline (matching Linux + spec), and `environ(name)` actually reads the environment via `GetEnvironmentVariableA` instead of always returning `""`. Both came out of getting kryofetch to render correctly.
- **Nested `func` declarations** inside `just run` are now hoisted to file scope automatically. Krypton has no closures, so this matches the C path's semantics; the previous code-path emitted garbage and crashed.
- **`stdlib/booleans.k`** — new module bridging the `"true"`/`"false"` literal form and the `"1"`/`"0"` comparison-result form when callers want consistent display or comparisons.
- **11 new algorithms** in `algorithms/`: quicksort, merge sort, heap sort, 0/1 knapsack, longest increasing subsequence, topological sort, Dijkstra, union-find, quickselect, KMP, and an env-backed singly-linked list.
- **18 new C standard / POSIX header bindings** in `headers/` — `stdlib`, `time`, `ctype`, `errno`, `assert`, `signal`, `setjmp`, `unistd`, `sys_stat`, `fcntl`, `dirent`, `sys_socket`, `netinet_in`, `arpa_inet`, `netdb`, `sys_mman`, `dlfcn`, `pthread`.
- **VS Code extension rebuilt** — `extensions/krypton-language-1.5.0.vsix` ships with the current TextMate grammar (every modern keyword, backtick interpolation, hex literals, full builtins list).
- **Documentation overhaul** — roadmap, function reference, grammar spec, type spec, and the EBNF grammar all rewritten against current reality. Tagged each builtin native vs C-path.

## Coverage

| Suite | Result |
|---|---|
| `tests/` | **38 / 38 native** (test_dll_exports skipped on non-Windows) |
| `examples/` | 79 / 84 native |
| `algorithms/` | **35 / 35 native** |
| `stdlib/` | 35 / 35 IR-parses |
| `tools/` | 20 / 20 native |
| `headers/` | 29 / 29 parse |

## Upgrading

End users: `git pull`, then `./build.sh` (Linux/macOS) or `bootstrap.bat` (Windows). The prebuilt 1.5.0 seed is shipped in `bootstrap/`.

Source-edit users: if you've edited `compiler/compile.k`, `compiler/linux_x86/elf.k`, or `compiler/windows_x86/x64.k`, see `bootstrap/REBUILD_SEED.md` for the rebuild recipe (the doc was also rewritten this release).

## Breaking changes

- **`true` / `false` literals now stringify differently** (`"true"`/`"false"` instead of `"1"`/`"0"`). Code that compared a literal `true`/`false` against a comparison-op result via `==` now sees a difference (`true == (5 > 3)` is now `"0"` because `"true"` ≠ `"1"`). No existing code in the repo did this — verified via grep — but if your program relies on it, use `stdlib/booleans.k`'s `boolEq(a, b)` for truthy-equality comparison.
- **Stdlib functions removed** because they shadowed native builtins of the same name and were silently dead on the native pipeline:
  - `stdlib/string_utils.k` — `repeat`, `contains`, `endsWith`, `toUpper`, `trim`, `reverse`, `replaceAll`
  - `stdlib/char_utils.k` — `isDigit`, `isAlpha`
  - `stdlib/math_utils.k` — `abs`
- **`stdlib/csv.k`'s `getField` renamed to `fieldAt`** — the new native struct builtin `getField(env, name)` was shadowing it.
- **`stdlib/task_manager.k` moved to `examples/task_manager.k`** — it had a `just run` block, so it's an example, not a library.
- **`headers/memory.krh` deleted** — bare `func` decls outside a `jxt` block silently failed to parse; nothing imported it; the runtime primitives it documented (`rawAlloc` etc.) work without any header.

## Known gaps

- The Windows native runtime's typed-struct table covers five C structs (`SYSTEM_INFO`, `MEMORYSTATUSEX`, `ULARGE_INTEGER`, `CONSOLE_SCREEN_BUFFER_INFO`, `SYSTEM_POWER_STATUS`). Programs that need `PROCESSENTRY32` or `WIN32_FIND_DATAA` get a wrong-size buffer and the corresponding Win32 APIs fail. Tracked for 1.6 — see `docs/roadmap.md`.
- Native module imports (`import "stdlib/result.k"` working through `kcc --native`) is the dominant remaining gap for the example suite. Five examples still fall back to the C path because of it.

## Full changelog

See [CHANGELOG.md](CHANGELOG.md#150---2026-05-03) for the complete entry.
