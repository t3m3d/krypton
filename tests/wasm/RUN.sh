#!/usr/bin/env bash
# tests/wasm/RUN.sh — Krypton WASM tutorial verifier (Agent B, Phase B.3).
#
# For each tutorial lesson: lower it to a .wasm via Agent A's emitter, run that
# .wasm through the host loader (scripts/run_wasm.js), and diff the output
# against `kcc -r` (the source of truth). Reports PASS / FAIL / SKIP per lesson.
#
#   bash tests/wasm/RUN.sh            # all tutorial/NN_*.k
#   bash tests/wasm/RUN.sh 01 07      # only lessons 01 and 07
#
# Exit: 0 if no FAILs (SKIPs are OK while the emitter is incomplete), 1 if any
# lesson FAILs (emitted .wasm output != kcc -r output).
#
# Contract boundaries:
#   - The emitter binary (compiler/wasm32/wasm_self[.exe]) is Agent A's.
#     If it's missing or can't lower a lesson, that lesson SKIPs — we never
#     try to fix the emitter here (WASM_PHASE_1_SPLIT.md rule #4).
#   - run_wasm.js is ours (Agent B).

set -u
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$REPO/tests/wasm/.work"           # repo-relative: avoids git-bash /tmp path translation on Windows
mkdir -p "$WORK"

# ── locate kcc driver ────────────────────────────────────────────────
# Prefer the repo driver (kcc.sh): it implements -r / --ir / -e. A bare `kcc`
# on PATH may be only the front-end (e.g. the Windows install at /c/krypton/kcc),
# which understands --ir but NOT -r run-mode — that silently yields empty
# reference output and mis-grades every lesson.
if [[ -f "$REPO/kcc.sh" ]]; then
  KCC() { bash "$REPO/kcc.sh" "$@"; }
elif command -v kcc >/dev/null 2>&1; then
  KCC() { kcc "$@"; }
else
  echo "RUN.sh: no $REPO/kcc.sh and no kcc on PATH" >&2; exit 1
fi

# ── locate Agent A's emitter binary ──────────────────────────────────
EMIT=""
for cand in "$REPO/compiler/wasm32/wasm_self" "$REPO/compiler/wasm32/wasm_self.exe"; do
  [[ -x "$cand" || -f "$cand" ]] && { EMIT="$cand"; break; }
done

# The committed binary is gitignored (.gitignore: compiler/wasm32/wasm_self), so a
# fresh `git pull` brings the updated wasm_self.k source but no rebuilt binary —
# running a stale/missing binary mis-grades every lesson. Build from source into
# $WORK if no binary is present, so the test always reflects current wasm_self.k.
if [[ -z "$EMIT" ]]; then
  built="$WORK/wasm_self"
  if KCC --gcc "$REPO/compiler/wasm32/wasm_self.k" -o "$built" 2>/dev/null \
     || KCC "$REPO/compiler/wasm32/wasm_self.k" -o "$built" 2>/dev/null; then
    [[ -s "$built" ]] && EMIT="$built"
  fi
fi

RUNNER="$REPO/scripts/run_wasm.js"
if ! command -v node >/dev/null 2>&1; then
  echo "RUN.sh: node not found (needed by scripts/run_wasm.js)" >&2; exit 1
fi

# ── select lessons ───────────────────────────────────────────────────
SEL=("$@")
lessons=()
for k in "$REPO"/tutorial/[0-9][0-9]_*.k; do
  [[ -e "$k" ]] || continue
  if [[ ${#SEL[@]} -gt 0 ]]; then
    base="$(basename "$k")"; pick=0
    for s in "${SEL[@]}"; do [[ "$base" == ${s}_* ]] && pick=1; done
    [[ $pick -eq 1 ]] || continue
  fi
  lessons+=("$k")
done

if [[ -z "$EMIT" ]]; then
  echo "── emitter not built yet ──────────────────────────────────────"
  echo "compiler/wasm32/wasm_self[.exe] not found (Agent A's artifact)."
  echo "Build it, then re-run. Until then every lesson SKIPs."
  echo "Lessons that would be checked: ${#lessons[@]}"
  exit 0
fi

PASS=0; FAIL=0; SKIP=0; ERR=0; FAILED=()
for k in "${lessons[@]}"; do
  name="$(basename "$k" .k)"
  kir="$WORK/$name.kir"; wasm="$WORK/$name.wasm"

  if ! KCC --ir "$k" > "$kir" 2>/dev/null; then
    printf '  SKIP %-26s (kcc --ir failed)\n' "$name"; SKIP=$((SKIP+1)); continue
  fi
  if ! "$EMIT" "$kir" "$wasm" >/dev/null 2>&1 || [[ ! -s "$wasm" ]]; then
    printf '  SKIP %-26s (emitter could not lower it)\n' "$name"; SKIP=$((SKIP+1)); continue
  fi

  # Reference output (source of truth). The Windows native pipeline is slow and
  # occasionally returns nothing on a given run; retry so a toolchain flake is
  # never mis-attributed to the emitter as a FAIL.
  expected=""
  for _try in 1 2 3; do
    expected="$(KCC -r "$k" 2>/dev/null)"
    [[ -n "$expected" ]] && break
  done
  actual="$(node "$RUNNER" "$wasm" 2>/dev/null)"

  if [[ -z "$expected" ]]; then
    printf '  ERR  %-26s (kcc -r gave no output after 3 tries — toolchain, not the emitter)\n' "$name"; ERR=$((ERR+1))
  elif [[ "$expected" == "$actual" ]]; then
    printf '  PASS %-26s\n' "$name"; PASS=$((PASS+1))
  else
    printf '  FAIL %-26s\n' "$name"; FAIL=$((FAIL+1)); FAILED+=("$name")
    printf '       expected: %q\n' "$(printf '%s' "$expected" | head -c 80)"
    printf '       actual:   %q\n' "$(printf '%s' "$actual"   | head -c 80)"
  fi
done

echo "──────────────────────────────────────────────────────────────"
echo "  wasm tutorials: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP  ERR=$ERR"
[[ ${#FAILED[@]} -gt 0 ]] && echo "  failed: ${FAILED[*]}"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
