#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT="$(dirname "$(realpath "$0")")"

# When https://github.com/varnish/varnish-go adds support for Varnish Enterprise,
# that will be an alternative to 'varnishtest' and VTC files.
