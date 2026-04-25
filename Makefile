# Krypton — Makefile
#
# Thin wrapper around build.sh (Linux/macOS/WSL) and build_v137.bat (Windows).
# All real build logic lives in those scripts; this file just provides familiar
# `make` targets for users who prefer them.
#
# Targets:
#   make              build kcc from bootstrap/kcc_seed.c
#   make install      build + symlink kcc into /usr/local/bin (sudo)
#   make run F=x.k    compile and run a .k file
#   make test         run the test suite
#   make clean        remove build artifacts
#   make seed         regenerate bootstrap/kcc_seed.c (requires existing ./kcc)
#   make help         show this message

ifeq ($(OS),Windows_NT)
    BUILD_CMD := build_v137.bat
else
    BUILD_CMD := ./build.sh
endif

F ?= examples/hello.k

.PHONY: all
all:
	$(BUILD_CMD)

.PHONY: install
install: all
	./install.sh

.PHONY: run
run:
	$(BUILD_CMD) run $(F)

.PHONY: test
test:
	$(BUILD_CMD) test

.PHONY: seed
seed:
	@if [ ! -x ./kcc ] && [ ! -x ./kcc.exe ]; then \
	    echo "ERROR: need an existing ./kcc (or ./kcc.exe) to regenerate the seed"; \
	    echo "       run 'make' first, then 'make seed'"; \
	    exit 1; \
	fi
	@if [ -x ./kcc ]; then KCC=./kcc; else KCC=./kcc.exe; fi; \
	    $$KCC kompiler/compile.k > bootstrap/kcc_seed.c && \
	    echo "regenerated bootstrap/kcc_seed.c ($$(wc -l < bootstrap/kcc_seed.c) lines)"

.PHONY: clean
clean:
	rm -f kcc kcc.exe 2>/dev/null || true
	rm -f kompiler/optimize_host.exe kompiler/x64_host.exe 2>/dev/null || true
	rm -f *.kir *.ll *.o 2>/dev/null || true
	@echo "Clean."

.PHONY: help
help:
	@echo ""
	@echo "Krypton — Make targets"
	@echo ""
	@echo "  make              Build kcc from bootstrap seed + self-rebuild + smoke test"
	@echo "  make install      Build, then symlink kcc into /usr/local/bin (sudo)"
	@echo "  make run F=x.k    Compile and run a .k file"
	@echo "  make test         Run the test suite"
	@echo "  make seed         Regenerate bootstrap/kcc_seed.c from compile.k"
	@echo "  make clean        Remove build artifacts"
	@echo ""
	@echo "  Direct usage after build:"
	@echo "    ./kcc source.k > source.c    transpile .k → C"
	@echo "    gcc source.c -o prog -lm     link"
	@echo ""
	@echo "  Native pipelines (Windows only):"
	@echo "    ./kcc.sh --native source.k -o source.exe   PE backend, no gcc"
	@echo "    ./kcc.sh --llvm source.k -o source.ll      LLVM IR backend"
	@echo ""
