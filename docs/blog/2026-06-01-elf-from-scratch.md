# Linux x86_64: writing your own ELF (no linker, no libc)

**Free sample chapter from "Building a Self-Hosting Compiler"** ·
[full course details](/kcode.html)

This is the chapter most people skip in compiler books. You write the
parser, the IR, maybe a little code-gen, and then you reach for LLVM —
or worse, you emit C and call `gcc`. What if you didn't? What if you
emitted the bytes of an ELF executable directly, fed it to the Linux
kernel, and watched it run? The answer is that ELF is small,
documented, and friendly. Three sections, a couple of headers, and a
single program-header type get you "Hello, World" in under 200 bytes of
machine code. No `ld`, no libc, no glibc lifestyle decisions about
pthread.

This chapter walks through how Krypton's Linux backend (`elf.k`) emits
a working binary from `.kir` (Krypton IR), step by step. The whole
backend is under 800 lines of Krypton. You'll see every byte.

## The 30-second tour of ELF

A statically-linked Linux ELF executable is, at minimum:

```
+-------------------+
| ELF header        |  64 bytes
+-------------------+
| Program headers   |  56 bytes per segment
+-------------------+
| Loadable code +   |  your program
| data segment      |
+-------------------+
```

That's it. No dynamic loader, no PT_INTERP, no relocations, no
`.rela.plt`. The kernel reads the ELF header, walks the program
headers, finds the one with `p_type = PT_LOAD`, copies the bytes into
memory at the requested virtual address, and jumps to the entry point.

You can skip:

- Section headers (only the linker reads them).
- `.dynamic`, `.got`, `.plt` (only the dynamic loader reads them).
- Symbol tables (only debuggers and linkers read them).
- libc, glibc, musl, anything ending in `.so`.

We talk straight to the kernel with `int 0x80` — no, wait, that's
32-bit. On x86_64 we use `syscall`. The three we need for "Hello,
World":

| Syscall | RAX | Args                    | What it does            |
|---------|-----|-------------------------|-------------------------|
| write   | 1   | RDI=fd, RSI=buf, RDX=len | write bytes to fd     |
| exit    | 60  | RDI=status              | terminate process     |
| brk     | 12  | RDI=new break           | grow heap (used later) |

That's the whole "runtime."

## ELF header, byte by byte

The ELF header is 64 bytes on x86_64. Here's what Krypton's elf.k emits:

```
00-03  7f 45 4c 46     // magic: "\x7fELF"
04     02              // EI_CLASS:  ELFCLASS64
05     01              // EI_DATA:   ELFDATA2LSB (little-endian)
06     01              // EI_VERSION: 1
07     00              // EI_OSABI:  System V
08-0f  00 00 00 00 00 00 00 00  // padding
10-11  02 00           // e_type:    ET_EXEC
12-13  3e 00           // e_machine: EM_X86_64
14-17  01 00 00 00     // e_version: 1
18-1f  78 00 40 00 00 00 00 00  // e_entry:    0x400078 (start of code)
20-27  40 00 00 00 00 00 00 00  // e_phoff:    64 (program headers right after header)
28-2f  00 00 00 00 00 00 00 00  // e_shoff:    0  (no section headers)
30-33  00 00 00 00     // e_flags:   0
34-35  40 00           // e_ehsize:  64
36-37  38 00           // e_phentsize: 56 bytes per program header
38-39  01 00           // e_phnum:   1 program header
3a-3b  00 00           // e_shentsize: 0
3c-3d  00 00           // e_shnum:   0
3e-3f  00 00           // e_shstrndx: 0
```

That's it. The Krypton code that emits this is one function:

```krypton
func elfHeader(entry) {
    let h = sbNew()
    h = sbAppend(h, "x7Fx45x4CxFE")            // magic
    h = sbAppend(h, "x02x01x01x00")            // class, data, version, osabi
    h = sbAppend(h, "x00x00x00x00x00x00x00x00") // padding
    h = sbAppend(h, hexWord(2))                 // e_type: ET_EXEC
    h = sbAppend(h, hexWord(0x3e))              // e_machine: x86_64
    h = sbAppend(h, hexDword(1))                // e_version: 1
    h = sbAppend(h, hexQword(entry))            // e_entry
    h = sbAppend(h, hexQword(64))               // e_phoff
    h = sbAppend(h, hexQword(0))                // e_shoff
    h = sbAppend(h, hexDword(0))                // e_flags
    h = sbAppend(h, hexWord(64))                // e_ehsize
    h = sbAppend(h, hexWord(56))                // e_phentsize
    h = sbAppend(h, hexWord(1))                 // e_phnum
    h = sbAppend(h, hexWord(0))                 // e_shentsize
    h = sbAppend(h, hexWord(0))                 // e_shnum
    h = sbAppend(h, hexWord(0))                 // e_shstrndx
    emit sbToString(h)
}
```

(The `hexWord` / `hexDword` / `hexQword` helpers encode integers as
`xHH` hex pairs so `writeBytes()` can emit raw bytes, including null
bytes. That's the only Krypton-specific trick in this chapter.)

## The program header

One program header tells the kernel: "load this much memory at this
virtual address, with these permissions, from this file offset." For
"Hello, World":

```
00-03  01 00 00 00     // p_type:   PT_LOAD
04-07  05 00 00 00     // p_flags:  PF_X | PF_R  (executable + readable)
08-0f  00 00 00 00 00 00 00 00  // p_offset: 0
10-17  00 00 40 00 00 00 00 00  // p_vaddr:  0x400000
18-1f  00 00 40 00 00 00 00 00  // p_paddr:  0x400000
20-27  c0 00 00 00 00 00 00 00  // p_filesz: 192 bytes
28-2f  c0 00 00 00 00 00 00 00  // p_memsz:  192 bytes
30-37  00 10 00 00 00 00 00 00  // p_align:  0x1000 (page size)
```

The kernel maps 192 bytes at virtual address `0x400000` with read +
execute permissions. The first 64 bytes of the mapping are the ELF
header (which the kernel reads twice — once to find the program
header, once as part of the load segment), the next 56 bytes are the
program header itself, and bytes 120 onward are our code.

`p_vaddr = 0x400000` is the conventional Linux load address for static
ELF binaries. It works because the kernel hands us virtual memory,
and the address has to be page-aligned, and `0x400000` is the lowest
"clean" page address that's outside the kernel's reserved areas. Use
something different and `execve` will refuse to load the binary.

## The "Hello, World" code

x86_64 machine code for `write(1, "Hello\n", 6); exit(0)`:

```
48 c7 c0 01 00 00 00     // mov rax, 1     ; syscall: write
48 c7 c7 01 00 00 00     // mov rdi, 1     ; fd: stdout
48 c7 c6 96 00 40 00     // mov rsi, 0x400096  ; ptr to "Hello\n"
48 c7 c2 06 00 00 00     // mov rdx, 6     ; len
0f 05                    // syscall
48 c7 c0 3c 00 00 00     // mov rax, 60    ; syscall: exit
48 c7 c7 00 00 00 00     // mov rdi, 0     ; status: 0
0f 05                    // syscall
48 65 6c 6c 6f 0a        // "Hello\n"
```

42 bytes of code + 6 bytes of data. The address `0x400096` is the file
offset of the string ("Hello\n") plus the load base — `0x400000 +
(192 - 6) = 0x400096`. Hand-calculated; the real backend computes it
during emission.

Compare what Krypton's elf.k builds for the actual `emit "Hello"`
case:

```krypton
// elf.k:980 (paraphrased)
func emitWrite(buf, len) {
    let code = sbNew()
    code = sbAppend(code, "x48xC7xC0x01x00x00x00")  // mov rax, 1
    code = sbAppend(code, "x48xC7xC7x01x00x00x00")  // mov rdi, 1
    code = sbAppend(code, "x48xC7xC6")               // mov rsi, imm64
    code = sbAppend(code, hexQword(buf))
    code = sbAppend(code, "x48xC7xC2")               // mov rdx, imm64
    code = sbAppend(code, hexQword(len))
    code = sbAppend(code, "x0Fx05")                  // syscall
    emit sbToString(code)
}
```

That's it. One function per Krypton operation. No instruction
scheduling, no register allocation — every value goes through RAX, the
stack is used for temporaries, and the kernel does the rest.

## Putting it together

The full elf.k driver pseudocode:

```krypton
just run {
    let entry = 0x400078    // ELF header (64) + program header (56) = 0x78
    let body = compileIR(readFile(arg("0")))  // → x86_64 bytes
    let fileSize = 64 + 56 + len(body) / 3    // /3 because hex-encoded

    let header = elfHeader(entry)
    let phdr = programHeader(fileSize)
    let payload = header + phdr + body

    writeBytes(arg("1"), payload)
}
```

Run it:

```
$ kcc compiler/linux_x86/elf.k input.kir output.elf
$ chmod +x output.elf
$ ./output.elf
Hello
```

That's a working Linux executable. No linker. No libc. No assembler.

## What this gives you (and what comes next)

By the end of this chapter you have:

- A binary that runs on Linux x86_64 with no external dependencies.
- A clear mental model for what an ELF file actually is.
- A backend pattern that mirrors what kcc does today: build a hex-encoded
  byte sequence, write it with `writeBytes`, run it.

The chapter goes deeper than this sample — the full version covers:

- Multiple segments (separating code from read-only data, dealing with
  alignment).
- Calling functions across translation units inside one ELF (PC-relative
  jumps, RIP-relative addressing for data).
- Adding a `brk`-based heap so dynamic allocation works.
- The dance of writing your own debug info (DWARF-lite) so a backtrace
  shows function names.
- When sectionless ELF stops working (when you start needing TLS, when
  you want to be loaded by ld.so for debug-info reasons).

Then chapter 5 does the same exercise on Windows (PE/COFF), and chapter
6 takes you through the part of Mach-O that nobody documents publicly:
how to emit an arm64 binary that runs under macOS Tahoe AMFI **without
calling `codesign`**. We hand-emit the SHA-256 code signature blob from
Krypton. It's 60 lines of Krypton and zero Apple tooling.

## Get the book

The full book is in progress. Sample chapters land monthly. Pre-order
gets you:

- Every chapter as it's drafted (we're in the middle of chapter 8 right
  now — stdlib internals).
- Source-code links to the exact lines in the
  [Krypton repo](https://github.com/t3m3d/krypton) for every example.
- Author Q&A access via the sponsor channel.

[Pre-order on Gumroad →](#preorder-coming-soon)  
[Sponsor on GitHub →](https://github.com/sponsors/t3m3d)

If you'd rather just read more, the public
[dev log](https://krypton-lang.org/blog.html) covers each week's progress
on the compiler, the framework, and the WASM backend that's underway.

---

*Krypton is built solo by Brian. The book is a record of how, and why
some of these decisions were stranger than they look. The free chapter
above is the same shape as the rest — code-heavy, deep, with the actual
hex bytes you'll find in your `output.elf`.*
