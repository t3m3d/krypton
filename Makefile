# Krypton — Cross-platform Makefile
# Works on Linux, macOS, and Windows (with MSYS2/Git Bash)
#
# Targets:
#   make              — build everything (auto-detects OS)
#   make run F=x.k    — compile and run a .k file
#   make interp F=x.k — run a .k file via the interpreter (no compile step)
#   make test         — run the test suite
#   make clean        — remove build artifacts
#   make help         — show this message

# ── OS detection ─────────────────────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    PLATFORM   := windows
    EXE        := .exe
    RM         := del /Q
    SLASH      := \\
    NULL       := nul
    SHELL_TYPE := cmd
else
    PLATFORM   := unix
    EXE        :=
    RM         := rm -f
    SLASH      := /
    NULL       := /dev/null
    SHELL_TYPE := sh
endif

# ── Tools ────────────────────────────────────────────────────────────────────
CC        ?= gcc
CFLAGS    := -lm -w

# ── Paths ────────────────────────────────────────────────────────────────────
KRUN       := ./krun$(EXE)
KCC        := ./kcc$(EXE)
KOPTIMIZE  := ./koptimize$(EXE)
KLLVMBE    := ./kllvmbe$(EXE)

RUNTIME_C  := archive/c/run.c
COMPILE_K  := kompiler/compile.k
OPTIMIZE_K := kompiler/optimize.k
LLVM_K     := kompiler/llvm.k
KR_RUNTIME := runtime/krypton_runtime.c

# Windows bootstrap binary (ships in repo)
KCC_WIN    := versions/kcc_v100.exe

# Temp files
TMP_C      := _build_tmp.c
TMP_BIN    := _build_tmp$(EXE)

# ── File to run (for `make run` and `make interp`) ───────────────────────────
F ?= examples/hello.k

# ── Default target ────────────────────────────────────────────────────────────
.PHONY: all
all:
ifeq ($(PLATFORM),windows)
	@$(MAKE) build-windows
else
	@$(MAKE) build-unix
endif

# ── Unix build ────────────────────────────────────────────────────────────────
.PHONY: build-unix
build-unix: krun kcc koptimize kllvmbe verify
	@echo ""
	@echo "Build complete. Run 'make help' for usage."

krun: $(RUNTIME_C)
	@echo "[1/4] Building interpreter (krun)..."
	$(CC) $(RUNTIME_C) -o $(KRUN) $(CFLAGS)
	@echo "      krun ready"

# kcc depends on krun existing so we can run the compiler through the interpreter
kcc: krun $(COMPILE_K)
	@echo "[2/4] Self-hosting: compiling compile.k (this may take a minute)..."
	$(KRUN) $(COMPILE_K) $(COMPILE_K) > $(TMP_C)
	$(CC) $(TMP_C) -o $(KCC) $(CFLAGS)
	@$(RM) $(TMP_C)
	@echo "      kcc ready"

koptimize: kcc $(OPTIMIZE_K)
	@echo "[3/4] Building optimizer (koptimize)..."
	$(KCC) $(OPTIMIZE_K) > $(TMP_C)
	$(CC) $(TMP_C) -o $(KOPTIMIZE) $(CFLAGS)
	@$(RM) $(TMP_C)
	@echo "      koptimize ready"

kllvmbe: kcc $(LLVM_K)
	@echo "[4/4] Building LLVM backend (kllvmbe)..."
	$(KCC) $(LLVM_K) > $(TMP_C)
	$(CC) $(TMP_C) -o $(KLLVMBE) $(CFLAGS)
	@$(RM) $(TMP_C)
	@echo "      kllvmbe ready"

.PHONY: verify
verify: kcc
	@echo "Verifying self-host..."
	@$(KCC) examples/fibonacci.k > _ver_a.c
	@$(KCC) $(COMPILE_K) > _ver_kcc2.c
	@$(CC) _ver_kcc2.c -o _ver_kcc2 $(CFLAGS)
	@./_ver_kcc2 examples/fibonacci.k > _ver_b.c
	@diff -q _ver_a.c _ver_b.c > $(NULL) && echo "  Self-host verified" || echo "  Warning: self-host output differs"
	@$(RM) _ver_a.c _ver_b.c _ver_kcc2.c _ver_kcc2$(EXE)

# ── Windows build ─────────────────────────────────────────────────────────────
.PHONY: build-windows
build-windows:
	@echo "Windows build: using pre-built $(KCC_WIN)"
	@if not exist $(KCC_WIN) (echo ERROR: $(KCC_WIN) not found & exit /b 1)
	$(KCC_WIN) $(OPTIMIZE_K) > $(TMP_C)
	$(CC) $(TMP_C) -o koptimize.exe $(CFLAGS)
	$(KCC_WIN) $(LLVM_K) > $(TMP_C)
	$(CC) $(TMP_C) -o kllvmbe.exe $(CFLAGS)
	@del /Q $(TMP_C) 2>nul || true
	@echo Build complete.

# ── Run a .k file ─────────────────────────────────────────────────────────────
.PHONY: run
run:
	@if [ ! -f "$(F)" ]; then echo "File not found: $(F)"; exit 1; fi
	@echo "Compiling $(F)..."
	@$(KCC) $(F) > $(TMP_C)
	@$(CC) $(TMP_C) -o $(TMP_BIN) $(CFLAGS)
	@$(RM) $(TMP_C)
	@echo "Running..."
	@./$(TMP_BIN)
	@$(RM) $(TMP_BIN)

# ── Interpret a .k file (no compile step, slower but works before kcc is built)
.PHONY: interp
interp:
	@if [ ! -f "$(F)" ]; then echo "File not found: $(F)"; exit 1; fi
	@$(KRUN) kompiler/run.k $(F)

# ── LLVM native pipeline ──────────────────────────────────────────────────────
# Usage: make native F=hello.k
.PHONY: native
native: kcc koptimize kllvmbe
	@if [ ! -f "$(F)" ]; then echo "File not found: $(F)"; exit 1; fi
	$(eval BASE := $(basename $(F)))
	@echo "Compiling $(F) to IR..."
	$(KCC) --ir $(F) > $(BASE).kir
	@echo "Optimizing IR..."
	$(KOPTIMIZE) $(BASE).kir > $(BASE)_opt.kir
	@echo "Generating LLVM IR..."
	$(KLLVMBE) $(BASE)_opt.kir > $(BASE).ll
	@echo "Compiling to native..."
	$(CC) -c $(KR_RUNTIME) -o _kruntime.o $(CFLAGS)
	clang -c $(BASE).ll -o $(BASE)_ll.o
	$(CC) $(BASE)_ll.o _kruntime.o -o $(BASE)_native $(CFLAGS)
	@$(RM) _kruntime.o
	@echo "Built: $(BASE)_native"
	@echo "Running..."
	@./$(BASE)_native

# ── Test suite ────────────────────────────────────────────────────────────────
.PHONY: test
test: kcc
	@echo ""
	@echo "Running tests..."
	@echo "────────────────────────────────────────────"
	@PASSED=0; FAILED=0; \
	for T in tests/test_*.k; do \
	    NAME=$$(basename $$T); \
	    if $(KCC) $$T > $(TMP_C) 2>$(NULL) && \
	       $(CC) $(TMP_C) -o $(TMP_BIN) $(CFLAGS) 2>$(NULL) && \
	       ./$(TMP_BIN) >$(NULL) 2>&1; then \
	        echo "  PASS  $$NAME"; PASSED=$$((PASSED+1)); \
	    else \
	        echo "  FAIL  $$NAME"; FAILED=$$((FAILED+1)); \
	    fi; \
	done; \
	$(RM) $(TMP_C) $(TMP_BIN) 2>$(NULL) || true; \
	echo "────────────────────────────────────────────"; \
	echo "  Passed: $$PASSED   Failed: $$FAILED"; \
	[ $$FAILED -eq 0 ]

# ── Clean ─────────────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	$(RM) krun kcc koptimize kllvmbe 2>$(NULL) || true
	$(RM) krun.exe kcc.exe koptimize.exe kllvmbe.exe 2>$(NULL) || true
	$(RM) $(TMP_C) $(TMP_BIN) 2>$(NULL) || true
	$(RM) _ver_* 2>$(NULL) || true
	$(RM) *.kir *.ll *.o *_native *_llvm 2>$(NULL) || true
	@echo "Clean."

# ── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo ""
	@echo "Krypton — Build targets"
	@echo ""
	@echo "  make              Build everything (krun, kcc, koptimize, kllvmbe)"
	@echo "  make run F=x.k    Compile + run a .k file"
	@echo "  make interp F=x.k Run a .k file via interpreter (no kcc needed)"
	@echo "  make native F=x.k Compile to native binary via LLVM"
	@echo "  make test         Run the test suite"
	@echo "  make clean        Remove build artifacts"
	@echo ""
	@echo "  CC=clang make     Use a different C compiler"
	@echo ""
	@echo "  Direct usage after build:"
	@echo "    ./kcc source.k > source.c    compile to C"
	@echo "    gcc source.c -o prog -lm     link"
	@echo ""
