#!/usr/bin/env bash
# Set up the Krypton linux_x86 build inside WSL2 (Exherbo, or any x86_64 distro).
#
# Run this INSIDE the WSL distro — never from /mnt/c (that path is slow over the
# 9p bridge AND is the vector by which a stray rm/script deletes real Windows
# files; clone into the WSL native FS, e.g. ~/krypton).
#
# The Krypton Linux toolchain is statically-linked, syscall-only ELF (the C-free
# runtime) — NO libc, ld-linux, gcc, or distro packages are needed to build/run
# Krypton. The only host requirement is `git` to fetch the repo.
#
# Usage (from inside WSL):
#   # first time, if you don't already have the repo:
#   git clone https://github.com/t3m3d/krypton.git ~/krypton && cd ~/krypton
#   ./scripts/setup-wsl-exherbo.sh
#   # or point it at a destination:
#   ./scripts/setup-wsl-exherbo.sh ~/work/krypton
set -uo pipefail

# ── Guards ───────────────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Linux" ]; then
    echo "setup-wsl-exherbo: not Linux (uname=$(uname -s)). Run inside the WSL distro." >&2
    exit 1
fi
if [ "$(uname -m)" != "x86_64" ]; then
    echo "setup-wsl-exherbo: WSL2 is an x86_64 kernel; got $(uname -m). The committed" >&2
    echo "  Linux host targets linux_x86 (compiler/linux_x86/elf.k). linux_arm64 can't" >&2
    echo "  be tested here." >&2
    exit 1
fi
case "$PWD" in
    /mnt/*) echo "setup-wsl-exherbo: REFUSING to run under /mnt/* — clone into the WSL" >&2
            echo "  native filesystem (~) instead. /mnt/c is slow and is the Windows-nuke vector." >&2
            exit 1 ;;
esac

REPO="${KRYPTON_REPO:-https://github.com/t3m3d/krypton.git}"

# ── git (Exherbo: cave; fall back per distro; skip if present) ────────────────
if ! command -v git >/dev/null 2>&1; then
    echo "setup-wsl-exherbo: git not found; attempting install..."
    if   command -v cave    >/dev/null 2>&1; then sudo cave resolve -x dev-scm/git
    elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y git
    elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --noconfirm git
    else echo "  no known package manager — install git manually, then re-run." >&2; exit 1; fi
fi

# ── Locate or clone the repo into the native FS ───────────────────────────────
if [ -f "compiler/linux_x86/kcc-x64" ] && [ -d ".git" ]; then
    DEST="$PWD"                       # already inside a checkout
elif [ "${1:-}" != "" ]; then
    DEST="$1"
else
    DEST="$HOME/krypton"
fi
case "$DEST" in /mnt/*) echo "setup-wsl-exherbo: DEST under /mnt — refusing (see above)." >&2; exit 1;; esac

if [ -d "$DEST/.git" ]; then
    echo "setup-wsl-exherbo: repo at $DEST — pulling latest"
    git -C "$DEST" pull --ff-only || echo "  (pull skipped — local changes; continuing)"
else
    echo "setup-wsl-exherbo: cloning into $DEST"
    git clone "$REPO" "$DEST"
fi
cd "$DEST"

# ── Ensure the committed Linux binaries are executable (git usually preserves) ─
chmod +x compiler/linux_x86/kcc-x64 2>/dev/null || true
chmod +x bootstrap/kcc_driver_linux_x86_64 bootstrap/elf_host_linux_x86_64 \
         bootstrap/kcc_seed_linux_x86_64 bootstrap/optimize_host_linux_x86_64 2>/dev/null || true

# ── Sanity: the binaries must be ELF x86_64 and runnable here ─────────────────
if ! ./compiler/linux_x86/kcc-x64 --version >/dev/null 2>&1; then
    # --version may not exist; just confirm it executes without "exec format"/"no such file"
    if ! ./compiler/linux_x86/kcc-x64 >/dev/null 2>&1; then
        rc=$?
        # rc 1/2 (usage) is fine; 126/127 = not executable / format error = real problem
        if [ "$rc" = "126" ] || [ "$rc" = "127" ]; then
            echo "setup-wsl-exherbo: kcc-x64 won't execute (rc=$rc). WSL2 should run static" >&2
            echo "  ELF fine — check the file isn't a git-LFS pointer or corrupt." >&2
            exit 1
        fi
    fi
fi

# ── Smoke build (fibonacci) via the native C-free pipeline ────────────────────
echo "setup-wsl-exherbo: running ./build.sh smoke..."
./build.sh || echo "  (build.sh returned non-zero — read the output above)"

cat <<EOF

setup-wsl-exherbo: done. Krypton linux_x86 build ready at $DEST
  full test suite:  ./build.sh test     (NOTE: a known set of tests fail — read counts)
  build one file:   ./build.sh run path/to/file.k
  Agent L work queued in:
    handoffs/handoff_m2l_gc_full_port_plan.md   (GC stage 0-6 port to elf.k)
    handoffs/handoff_m2wl_a1_float.md           (A1 float mirror to linux_x86/elf.k)

Disk guard (Exherbo source builds + WSL2 vhdx never shrinks):
  keep an eye on Windows C: free space; if the distro vhdx balloons, on Windows run
  'wsl --shutdown' then compact the vhdx (diskpart: select vdisk file=...; compact vdisk).
  Better: move the distro to a non-system drive (wsl --export / --import --version 2).
EOF
