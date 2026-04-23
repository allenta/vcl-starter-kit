#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(dirname "$(realpath "$0")")"
VCL="$ROOT/../vcl"

# VCL files are copied to a temporary location in order to apply some minimal
# adjustments needed for testing.
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Copy VCL files to temporary location and apply the following adjustments:
#   - Do not include 'environment.vcl' from 'main.vcl'. VTCs need that to
#     customize the environment for testing (e.g., location of mocked backends,
#     etc.).
#   - Uncomment the inclusion of 'akamai.vcl', which might be useful for some
#     tests.
#   - Ensure 'replication-disabled.vcl' is the included replication option.
cp -r "$ROOT/../vcl"/. "$TMPDIR"/
sed -i \
    -e 's/^\(include "environment.vcl";\)/# \1/' \
    -e 's/^# \(include "akamai.vcl";\)/\1/' \
    -e 's/^\(include "replication-.*\.vcl"\);/# \1;/' \
    -e "s/^# \(include \"replication-disabled.vcl\";\)/\1/" \
    "$TMPDIR/main.vcl"

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
