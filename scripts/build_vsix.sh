#!/bin/sh
# Compatibility entry point. Package explicit files, never Git metadata.
set -eu
exec python3 "$(dirname "$0")/build_vsix.py" "$@"
