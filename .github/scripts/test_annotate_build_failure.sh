#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/annotate_build_failure.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

cat > "$sandbox/failed.log" <<'LOG'
[Licensing::Module] Error: Access token is unavailable; failed to update
Refreshing native plugins compatible for Editor in 12.34 ms
[CIHelper] Build failed: System.ArgumentException: Pass -buildOutput <directory>. 100%
  at CIHelper.BuildOrThrow (System.String outputDirectory) [0x0012d] in Assets/Editor/CIHelper.cs:27
  at CIHelper.Build () [0x00000] in Assets/Editor/CIHelper.cs:15
UnityEngine.Debug:ExtractStackTraceNoAlloc (byte*,int,string)
LOG

cat > "$sandbox/green.log" <<'LOG'
[Licensing::Module] Error: Access token is unavailable; failed to update
[CIHelper] Built WebGL into Builds/webgl (13123813 bytes).
LOG

expected='::error::[CIHelper] Build failed: System.ArgumentException: Pass -buildOutput <directory>. 100%25%0A  at CIHelper.BuildOrThrow (System.String outputDirectory) [0x0012d] in Assets/Editor/CIHelper.cs:27%0A  at CIHelper.Build () [0x00000] in Assets/Editor/CIHelper.cs:15'
actual="$(bash "$script" "$sandbox/failed.log")"
[ "$actual" = "$expected" ] || { echo "FAIL failed.log: got: $actual"; exit 1; }

if bash "$script" "$sandbox/green.log" > "$sandbox/out"; then echo "FAIL green.log matched"; exit 1; fi
[ ! -s "$sandbox/out" ] || { echo "FAIL green.log printed output"; exit 1; }

if bash "$script" "$sandbox/missing.log" > /dev/null; then echo "FAIL missing log matched"; exit 1; fi

echo "annotate_build_failure contract passed"
