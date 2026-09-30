#!/usr/bin/env bash
set -euo pipefail

validator="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate_webgl_payload.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

make_complete_player() {
  local root="$1"
  local suffix="${2:-}"
  mkdir -p "$root/Build"
  printf '<html><body>player</body></html>\n' > "$root/index.html"
  printf payload > "$root/Build/player.loader.js"
  printf payload > "$root/Build/player.framework.js${suffix}"
  printf payload > "$root/Build/player.wasm${suffix}"
  printf payload > "$root/Build/player.data${suffix}"
}

expect_pass() {
  "$validator" "$2" "$1" >/dev/null
  echo "PASS: $1"
}

expect_fail() {
  if "$validator" "$2" "$1" >/dev/null 2>&1; then
    echo "FAIL: $1 unexpectedly validated" >&2
    exit 1
  fi
  echo "PASS: $1 rejected"
}

root="$sandbox/complete"
make_complete_player "$root"
expect_pass complete "$root"

root="$sandbox/brotli"
make_complete_player "$root" .br
expect_pass brotli "$root"

root="$sandbox/gzip"
make_complete_player "$root" .gz
expect_pass gzip "$root"

root="$sandbox/case-insensitive"
make_complete_player "$root"
mv "$root/Build/player.loader.js" "$root/Build/PLAYER.LOADER.JS"
mv "$root/Build/player.framework.js" "$root/Build/PLAYER.FRAMEWORK.JS"
mv "$root/Build/player.wasm" "$root/Build/PLAYER.WASM"
expect_pass case-insensitive "$root"

expect_fail missing-root "$sandbox/missing-root"

root="$sandbox/missing-index"
make_complete_player "$root"
rm "$root/index.html"
expect_fail missing-index "$root"

root="$sandbox/empty-index"
make_complete_player "$root"
: > "$root/index.html"
expect_fail empty-index "$root"

root="$sandbox/index-directory"
make_complete_player "$root"
rm "$root/index.html"
mkdir "$root/index.html"
expect_fail index-directory "$root"

root="$sandbox/missing-build"
make_complete_player "$root"
rm -rf "$root/Build"
expect_fail missing-build "$root"

root="$sandbox/build-file"
make_complete_player "$root"
rm -rf "$root/Build"
printf payload > "$root/Build"
expect_fail build-file "$root"

root="$sandbox/zero-byte-payload"
make_complete_player "$root"
find "$root/Build" -type f -exec sh -c ': > "$1"' _ {} \;
expect_fail zero-byte-payload "$root"

for fragment in loader.js framework.js wasm; do
  root="$sandbox/missing-$fragment"
  make_complete_player "$root"
  rm "$root/Build/player.$fragment"
  expect_fail "missing-$fragment" "$root"
done

echo "WebGL payload validator contract passed."
