#!/usr/bin/env bash
set -euo pipefail

root="${1:?usage: validate_webgl_payload.sh <player-root> [label]}"
label="${2:-$root}"

fail() {
  echo "::error::$label: $1"
  exit 1
}

[ -d "$root" ] || fail "'$root' does not exist."
[ -f "$root/index.html" ] || fail "missing required WebGL file: index.html"
[ -s "$root/index.html" ] || fail "index.html is empty."
[ -d "$root/Build" ] || fail "missing required WebGL directory: Build/"

for fragment in ".loader.js" ".framework.js" ".wasm"; do
  if [ -z "$(find "$root/Build" -type f -size +0c -iname "*${fragment}*" -print -quit)" ]; then
    fail "Build/ has no non-empty *${fragment}* payload."
  fi
done

payload_files=$(find "$root/Build" -type f | wc -l)
payload_bytes=$(du -sb "$root/Build" | cut -f1)
echo "$label: validated WebGL player - Build/ has $payload_files file(s), $((payload_bytes / 1024 / 1024)) MiB"
find "$root" -mindepth 1 -maxdepth 1 -printf '  %y %10s %p\n' | sort
