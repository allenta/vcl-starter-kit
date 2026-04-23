#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(dirname "$(realpath "$0")")"

# VCL files are copied to a temporary location in order to apply some minimal
# adjustments needed for testing.
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Copy VCL files to a temporary location with these tweaks:
#   - Include 'akamai.vcl' (might be handy for some tests).
#   - Use 'replication-disabled.vcl' as the replication option.
#   - Activate calls to subroutines defined in VTCs for extra instrumentation.
cp -r "$ROOT/../vcl"/. "$TMPDIR"/
sed -i \
    -e 's/^# \(include "akamai.vcl";\)/\1/' \
    -e 's/^\(include "replication-.*\.vcl"\);/# \1;/' \
    -e "s/^# \(include \"replication-disabled.vcl\";\)/\1/" \
    "$TMPDIR/main.vcl"
sed -i \
    -e 's/^\s*# \(call vtc_.*;\)$/\1/' \
    "$TMPDIR/main.vcl" \
    "$TMPDIR/environment.local.vcl"

# Discover VTC files to run.
if [[ $# -gt 0 ]]; then
    VTCS=("$@")
else
    mapfile -t VTCS < <(find "$ROOT" -name '*.vtc' -type f | sort)
fi

# Run VTC tests until the first failure is encountered.
for vtc in "${VTCS[@]}"; do
    varnishtest -Dvcl_path="$TMPDIR" "$vtc"
done


