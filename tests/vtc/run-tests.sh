#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# Initializations.
ROOT="$(dirname "$(realpath "$0")")"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

# Prepare a base copy of VCL files with common tweaks:
#   - Include 'akamai.vcl' (might be handy for some tests).
#   - Use 'replication-disabled.vcl' as the replication option.
cp -r "$ROOT/../../vcl"/. "$TEMP/vcl/"
sed -i \
    -e 's/^# \(include "akamai.vcl";\)/\1/' \
    -e 's/^\(include "replication-.*\.vcl"\);/# \1;/' \
    -e "s/^# \(include \"replication-disabled.vcl\";\)/\1/" \
    "$TEMP/vcl/main.vcl"

# Discover VTC files to run.
if [[ $# -gt 0 ]]; then
    VTCS=("$@")
else
    mapfile -t VTCS < <(find "$ROOT" -name '*.vtc' -type f | sort)
fi

# Run VTC tests until the first failure is encountered. For each test, create a
# per-test copy of the VCL files and only uncomment the instrumentation points
# declared in the VTC file via the '# VTC_SUBS: sub1 sub2 ...' comment.
for VTC in "${VTCS[@]}"; do
    VCL_PATH="$TEMP/$(basename "$VTC" .vtc)/vcl"
    TMP_PATH="$TEMP/$(basename "$VTC" .vtc)/tmp"

    mkdir -p "$VCL_PATH" "$TMP_PATH"
    cp -r "$TEMP/vcl"/. "$VCL_PATH"

    mapfile -t VTC_SUBS < <(grep -oP '(?<=^# VTC_SUBS:)\s.*' "$VTC" | grep -oP '\S+' || true)
    for sub in "${VTC_SUBS[@]}"; do
        find "$VCL_PATH" -name '*.vcl' -exec \
            sed -i \
                -e "s/^\(\s*\)# \(call ${sub};\)$/\1\2/" \
                {} +
    done

    varnishtest \
        -Dvcl_path="$VCL_PATH" \
        -Dtmp_path="$TMP_PATH" \
        "$VTC"
done
