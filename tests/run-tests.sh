#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# Initializations.
ROOT="$(dirname "$(realpath "$0")")"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

# Copy VCL files to a temporary location and apply some tweaks:
#   - Include 'akamai.vcl' (might be handy for some tests).
#   - Use 'replication-disabled.vcl' as the replication option.
#   - Activate calls to subroutines defined in VTCs for extra instrumentation.
VCL_PATH="$TEMP/vcl"
mkdir -p "$VCL_PATH"
cp -r "$ROOT/../vcl"/. "$VCL_PATH"/
sed -i \
    -e 's/^# \(include "akamai.vcl";\)/\1/' \
    -e 's/^\(include "replication-.*\.vcl"\);/# \1;/' \
    -e "s/^# \(include \"replication-disabled.vcl\";\)/\1/" \
    "$VCL_PATH/main.vcl"
sed -i \
    -e 's/^\s*# \(call vtc_.*;\)$/\1/' \
    "$VCL_PATH/main.vcl" \
    "$VCL_PATH/environment-local.vcl"

# Discover VTC files to run.
if [[ $# -gt 0 ]]; then
    VTCS=("$@")
else
    mapfile -t VTCS < <(find "$ROOT" -name '*.vtc' -type f | sort)
fi

# Run VTC tests until the first failure is encountered. Use a separate temporary
# directory for each test.
for vtc in "${VTCS[@]}"; do
    TMP_PATH="$TEMP/tmp/$(basename "$vtc" .vtc)"
    mkdir -p "$TMP_PATH"
    varnishtest \
        -Dvcl_path="$VCL_PATH" \
        -Dtmp_path="$TMP_PATH" \
        "$vtc"
done
