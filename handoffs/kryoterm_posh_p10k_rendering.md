# Rendering posh / powerlevel10k prompts in kryoterm — recipe (Agent M → W)

Solved this for macOS kryoterm 2026-06-07. oh-my-posh and powerlevel10k are the
same problem (powerline segments + Nerd Font icons + colour backdrops). If your
Windows renderer looks "terrible" it's almost certainly one of the items below —
each was a real, distinct bug I had to fix. The **term.k grid engine is shared
Krypton** (already in the kryoterm repo, all fixes landed), so most of this is
free if you build on term.k; the rest is on the platform renderer (your Win32
side, my Cocoa shim).

## term.k engine — already fixed in the repo (pull latest kryoterm)
These were the prompt-breakers, in rough order of impact:

1. **Deferred wrap (auto-margin).** A glyph printed at the LAST column must NOT
   move the cursor — set a pending-wrap flag and wrap only when the NEXT glyph
   arrives. Without it, zsh/posh's `PROMPT_EOL_MARK` pad-spaces spill to the next
   row and you get a stray "%"/"∎" on its own line above the prompt, plus general
   misalignment. (term.k: `pw` in the packed state.)
2. **EL/ED honour their param.** `ESC[K` is NOT "erase whole line" — `0`=cursor→
   end, `1`=start→cursor, `2`=line. p10k/posh print the prompt then `ESC[0K` to
   trim; if you erase the whole line you wipe the just-drawn prompt → only a bare
   "%" survives. Same for `ESC[J` (0/1/2/3).
3. **256-colour per cell.** Parse `38;5;N` / `48;5;N`; store the index per cell;
   re-emit it. Basic 30-37/40-47/90-97/100-107 fold into indices 0-15. Without
   this the segment **backdrops vanish** (icons/text on bare bg).
4. **Cursor save/restore.** `ESC7`/`ESC8` (DECSC/DECRC) and `ESC[s`/`ESC[u`.
5. **gridSafeLen — carry partial sequences across reads.** A pty read can split
   an escape or a multi-byte UTF-8 char mid-way; feed only up to the last COMPLETE
   unit and prepend the remainder to the next read, or complex output (kryofetch,
   posh) corrupts. (This bit hard — looked like random garbage.)
6. **UTF-8 multi-byte cells.** A glyph occupies ONE display column; the char grid
   uses width-prefixed slots so `❯`/`✔`/powerline separators align.

## ⚠ TRUECOLOR — the likely posh-specific gap
oh-my-posh themes very commonly use **24-bit truecolor** `ESC[48;2;r;g;b` (not
256-colour). term.k currently handles only `48;5;N` (256). A 1-byte-per-cell
attr can't hold 24-bit, so posh truecolor segments are dropped/approximated. To
fix: either (a) approximate `48;2;r;g;b` → nearest xterm-256 index in `_applySgr`
(cheap, 1-byte storage unchanged — recommended first), or (b) store full rgb per
cell (wider attr cells). Check what the user's posh theme emits:
`oh-my-posh print primary | xxd | grep '48;2'`.

## Frame protocol (engine ↔ renderer) — match this on Windows
- Interactive bridge emits per settled frame: `SOH "row,col" SOH <grid-text> FF`.
  Renderer strips the SOH cursor header (draws the cursor there) and renders the
  grid up to the form-feed (0x0c) terminator.
- **Coalesce**: feed all available output into the grid, emit ONE frame after it
  settles (~2 idle poll cycles) → no flicker.
- **Full-write loop**: a frame is ~KBs; `write()` can be partial — loop or the
  frame (and its FF) truncate and the renderer never sees a complete frame.
- **Don't share one pty** for the bridge's stdin+stdout: dup'd fds share
  O_NONBLOCK, so non-blocking stdin makes stdout non-blocking → partial writes
  truncate frames. Use separate pipes (the shell still gets its own pty).

## Renderer (your Win32 side) must:
- Parse `38;5;N` / `48;5;N` (and ideally `48;2;r;g;b`) → fg + **background fill**.
  The backdrop is the whole point of posh — render bg, not just fg.
- Use a **Nerd Font** (e.g. the user has "JetBrainsMono Nerd Font Mono") or every
  icon is a missing-glyph box.
- Place the cursor from the frame header using the font's monospace advance +
  line height.
- Tell the pty the real size (`TIOCSWINSZ` equiv / `SetConsoleScreenBufferSize`)
  so the grid width matches; posh/p10k right-align RPROMPT to it.

## Windows platform path (W) — the architecture that worked on macOS
macOS kryoterm splits cleanly; mirror it:
- **Engine = pure Krypton, shared.** `term.k` (grid/ANSI/colour/wrap/cursor) and
  the interactive bridge loop in `run.k -i` are platform-independent. REUSE THEM
  unchanged — don't reimplement the VT parser in C. They already handle posh/p10k.
- **pty = platform-native, NOT a Krypton builtin on Windows.** On macOS I made
  ptyMaster/ptyForkExec/fdRead native macho `svc` builtins. Windows has no such
  syscalls — use **ConPTY**: `CreatePseudoConsole(size, hInPipeRead, hOutPipeWrite,
  0, &hPC)`, spawn the shell (pwsh) with `STARTUPINFOEX` +
  `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE_HANDLE`. ConPTY emits VT sequences on its
  output pipe — exactly what term.k eats. Write keystrokes to the in-pipe.
- **GUI + ConPTY live in the C/Win32 shim** (like my Obj-C shim). The shim: runs
  ConPTH, runs `kryoterm -i` (the Krypton bridge) wired to the ConPTY, reads the
  bridge's frames, draws them (Direct2D/GDI text + bg-fill rects), sends keys.
  OR simpler first cut: shim owns ConPTY + feeds raw VT straight to its own
  term.k-equivalent. Either way the rendering recipe above is the hard part.
- If you're stuck at "no rendered prompt at all" (not just ugly): check (1) ConPTY
  output pipe is actually being read + fed to the grid, (2) the shell is pwsh with
  oh-my-posh initialised, (3) you set the ConPTY size so posh lays out, (4) you're
  drawing **background** rects (posh is 90% backdrop), (5) Nerd Font.

— M (macOS). macOS kryoterm is fully working (live zsh, p10k prompt with icons +
256-colour backdrops, history, kryofetch, blink cursor, themed/config'd window).
Ping for exact term.k diffs; commits 2663325 (deferred wrap), 347289b (256-col),
73ae70b (EL/ED params), ac79cc7 (cursor), 7073c80 (bg colour + arrow keys).
