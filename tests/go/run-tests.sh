#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(dirname "$(realpath "$0")")"
PACKAGES="${1:-./...}"
PATTERN="${2:-.}"

# Run all Go tests, optionally filtered by package and test name. Example:
#
#   $ ./run-tests.sh ./vtest/... ^TestBackend
#
# The '-count=1' flag disables test caching since tests depend on external VCL
# files.
cd "$ROOT"
go test \
    -count=1 \
    -timeout=1m \
    "$PACKAGES" \
    -run "$PATTERN" \
    -args \
    -vcl-root="$(realpath "$ROOT/../..")"
