# FreeBSD x86_64 Backend

Status: scaffolded, parses on macOS, needs first FreeBSD seed pass.

## Files

- `elf.k`: FreeBSD x86_64 ELF emitter.
- expected seed: `bootstrap/kcc_seed_freebsd_x86_64`
- expected driver: `bootstrap/kcc_driver_freebsd_x86_64`
- expected backend host: `bootstrap/elf_host_freebsd_x86_64`
- optional optimizer host: `bootstrap/optimize_host_freebsd_x86_64`

## Smoke Pass On FreeBSD

From repo root:

```sh
./build.sh
./kcc -e 'kp("freebsd ok")'
./kcc examples/hello.k -o /tmp/hello.krypton
/tmp/hello.krypton
```

Then test file IO:

```sh
./kcc -e 'writeFile("/tmp/krbsd.txt", "ok"); kp(readFile("/tmp/krbsd.txt"))'
```

## Notes

- No C fallback is wired.
- Raw syscall ABI uses `RDI, RSI, RDX, R10, R8, R9`; FreeBSD kernel stores
  `R10` as the fourth arg.
- `memfdCreate` maps to FreeBSD `shm_open2(SHM_ANON, O_RDWR, 0600, 0, NULL)`
  plus `ftruncate`, because FreeBSD exposes `memfd_create()` through libc but
  not as a direct syscall number.
- ELF header uses `ELFOSABI_FREEBSD` (`EI_OSABI = 9`).
