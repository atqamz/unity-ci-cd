#!/usr/bin/env bash
set -euo pipefail

log="${1:?usage: annotate_build_failure.sh <build.log>}"

[ -f "$log" ] || exit 1
block="$(grep -m1 -A2 -F '[CIHelper] Build failed:' "$log" | tr -d '\r')" || exit 1
block="${block//%/%25}"
printf '::error::%s\n' "${block//$'\n'/%0A}"
