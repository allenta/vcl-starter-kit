#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(dirname "$(realpath "$0")")"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

compile-vcl() {
    local output="$TEMP/output"
    if ! varnishd \
        -C \
        -f "$TEMP/vcl/main.vcl" \
        -j none \
        -p "vcl_path=$TEMP/vcl:/usr/share/varnish-plus/vcl" \
        >"$output" 2>&1; then
        cat "$output"
        exit 1
    fi
}

check-vcl-syntax() {
    # Copy VCL files to a temporary location.
    cp -r "$ROOT/../vcl"/. "$TEMP/vcl/"

    # Discover existing replication and environment flavors.
    local -a replications=()
    mapfile -t replications < <(
        find "$TEMP/vcl" -maxdepth 1 -type f -name 'replication-*.vcl' -printf '%f\n' \
            | sed -E 's/^replication-(.*)\.vcl$/\1/' \
            | sort
    )
    local -a environments=()
    mapfile -t environments < <(
        find "$TEMP/vcl" -maxdepth 1 -type f -name 'environment-*.vcl' -printf '%f\n' \
            | sed -E 's/^environment-(.*)\.vcl$/\1/' \
            | sort
    )

    # Check syntax including 'akamai.vcl' and one replication strategy at a
    # time.
    local replication
    cp "$TEMP/vcl/main.vcl" "$TEMP/vcl/main.vcl.bak"
    for replication in "${replications[@]}"; do
        echo "  - replication-${replication}.vcl"
        sed -i \
            -e 's/^# \(include "akamai\.vcl";\)/\1/' \
            -e 's/^\(include "replication-.*\.vcl"\);/# \1;/' \
            -e "s/^# \(include \"replication-${replication}\.vcl\";\)/\1/" \
            "$TEMP/vcl/main.vcl"
        compile-vcl
    done
    mv "$TEMP/vcl/main.vcl.bak" "$TEMP/vcl/main.vcl"

    # Check syntax including one environment at a time.
    local environment
    cp "$TEMP/vcl/environment.vcl" "$TEMP/vcl/environment.vcl.bak"
    for environment in "${environments[@]}"; do
        echo "  - environment-${environment}.vcl"
        sed -i \
            -e "s/^include \"environment-.*\.vcl\";/include \"environment-${environment}.vcl\";/" \
            "$TEMP/vcl/environment.vcl"
        compile-vcl
    done
    mv "$TEMP/vcl/environment.vcl.bak" "$TEMP/vcl/environment.vcl"
}

echo '> Checking VCL syntax...'
check-vcl-syntax

echo
echo '> Running VTC tests...'
"$ROOT/vtc/run-tests.sh"

echo
echo '> Running Go tests...'
"$ROOT/go/run-tests.sh"
