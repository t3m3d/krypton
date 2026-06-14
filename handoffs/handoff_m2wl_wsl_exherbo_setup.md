# Handoff m → w/l: WSL-Exherbo Krypton build setup

**From:** agent m (macOS)
**Date:** 2026-06-14
**Context:** W's box reinstalled; Linux work now runs in a WSL2 Exherbo distro on
that box (one machine = Agent W native Windows + Agent L via WSL). This sets up the
linux_x86 Krypton build there.

## Key fact that makes this trivial

The committed Linux toolchain (`compiler/linux_x86/kcc-x64`, `bootstrap/
{kcc_driver,elf_host,kcc_seed,optimize_host}_linux_x86_64`) is **statically-linked,
syscall-only ELF** (the C-free runtime). No libc, no ld-linux, no gcc, no distro
packages needed to build or run Krypton. Runs on any x86_64 Linux kernel incl.
WSL2 + Exherbo. The ONLY host requirement is `git` to fetch the repo.

WSL2 is an **x86_64** kernel → this is the `linux_x86/elf.k` target (the GC
full-port + A1 float mirror both target linux_x86 first). `linux_arm64/elf.k`
cannot be tested here.

## Linux side (run inside WSL, NOT /mnt/c)

```sh
git clone https://github.com/t3m3d/krypton.git ~/krypton
cd ~/krypton
./scripts/setup-wsl-exherbo.sh
```

`scripts/setup-wsl-exherbo.sh` (committed): guards against /mnt and non-x86_64,
installs git if missing (cave/apt/pacman), clones-or-pulls into the native FS,
chmod +x's the binaries, sanity-checks they execute, runs `./build.sh` (fibonacci
smoke). Then `./build.sh test` for the full suite (a known set fails — read counts,
don't treat non-zero exit as "broken").

**Two hard rules (both are how this box can re-break Windows):**
1. Work in the WSL **native FS** (`~`), never `/mnt/c/...`. `/mnt/c` as root is the
   delete-Windows-files vector and is slow over 9p. The script refuses to run there.
2. Watch **disk**: Exherbo is source-based (paludis compiles everything) and WSL2's
   `ext4.vhdx` auto-grows but **never shrinks** → it can fill `C:` and break Windows.

## Windows side: `~/.wslconfig` (i.e. `C:\Users\<you>\.wslconfig`)

Cap WSL2 memory/disk pressure and keep the vhdx in check:

```ini
[wsl2]
memory=8GB          # cap so a runaway build doesn't starve Windows
swap=4GB
# sparse VHD lets freed space be reclaimable (Win11 23H2+ / recent WSL):
sparseVhd=true
```

After big source builds, reclaim space (PowerShell, admin):
```
wsl --shutdown
wsl --manage <DistroName> --set-sparse true     # if not already
# or compact manually:
diskpart
  select vdisk file="C:\...\ext4.vhdx"
  attach vdisk readonly
  compact vdisk
  detach vdisk
```

**Best practice:** move the distro off the system drive entirely:
```
wsl --export Exherbo D:\wsl\exherbo.tar
wsl --unregister Exherbo
wsl --import Exherbo D:\wsl\exherbo D:\wsl\exherbo.tar --version 2
```
Then a ballooning vhdx fills D:, not C: — Windows stays bootable.

## What's queued for the L role here

- `handoffs/handoff_m2l_gc_full_port_plan.md` — GC stage 0-6 port to `elf.k`
  (Brian chose full port; staged plan with the object-header blocker mapped).
- `handoffs/handoff_m2wl_a1_float.md` — mirror A1 float (boxed-f64) to
  `linux_x86/elf.k`; SSE2 instr notes included.

— m
