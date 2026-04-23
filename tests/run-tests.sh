#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(dirname "$(realpath "$0")")"

# VCL files are copied to a temporary location in order to apply some minimal
# adjustments needed for testing.
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Copy VCL files to a temporary location with these tweaks:
#   - Uncomment 'akamai.vcl' (might be handy for some tests).
#   - Use 'replication-disabled.vcl' as the replication option.
#   - Inject calls to subroutines defined in VTCs for extra instrumentation:
#     + vtc_post_init_environment.
#     + vtc_post_init.
#     + vtc_pre_recv.
cp -r "$ROOT/../vcl"/. "$TMPDIR"/
sed -i \
    -e 's/^# \(include "akamai.vcl";\)/\1/' \
    -e 's/^\(include "replication-.*\.vcl"\);/# \1;/' \
    -e "s/^# \(include \"replication-disabled.vcl\";\)/\1/" \
    -e '0,/sub vcl_recv {/s//sub vcl_recv { call vtc_pre_recv; } sub vcl_recv {/' \
    "$TMPDIR/main.vcl"
echo 'sub vcl_init { call vtc_post_init; }' >> "$TMPDIR/main.vcl"
echo 'sub vcl_init { call vtc_post_init_environment; }' >> "$TMPDIR/environment.vcl"

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


