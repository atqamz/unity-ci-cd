#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unity_repair_modules.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

editor="$sandbox/Editor/Unity"
engines="$sandbox/Editor/Data/PlaybackEngines"
mkdir -p "$engines/WebGLSupport/Editor/Data/PlaybackEngines/WebGLSupport/BuildTools" "$engines/LinuxStandaloneSupport/Variations"
touch "$editor"
printf dll > "$engines/WebGLSupport/Editor/Data/PlaybackEngines/WebGLSupport/UnityEditor.WebGL.Extensions.dll"
printf hidden > "$engines/WebGLSupport/Editor/Data/PlaybackEngines/WebGLSupport/.version"
printf keep > "$engines/LinuxStandaloneSupport/Variations/player"

RUNNER_TEMP="$sandbox" bash "$script" "$editor" > "$sandbox/out"

[ -f "$engines/WebGLSupport/UnityEditor.WebGL.Extensions.dll" ] || { echo "FAIL module not moved"; exit 1; }
[ -f "$engines/WebGLSupport/.version" ] || { echo "FAIL dotfile not moved"; exit 1; }
[ -d "$engines/WebGLSupport/BuildTools" ] || { echo "FAIL subdirectory not moved"; exit 1; }
[ ! -e "$engines/WebGLSupport/Editor" ] || { echo "FAIL nested tree left behind"; exit 1; }
[ -f "$engines/LinuxStandaloneSupport/Variations/player" ] || { echo "FAIL correct module touched"; exit 1; }
grep -q '1 module(s) repaired' "$sandbox/out" || { echo "FAIL repair not counted"; cat "$sandbox/out"; exit 1; }

RUNNER_TEMP="$sandbox" bash "$script" "$editor" | grep -q '0 module(s) repaired' || { echo "FAIL second run not a no-op"; exit 1; }
RUNNER_TEMP="$sandbox" bash "$script" "$sandbox/missing/Unity" | grep -q 'no module to repair' || { echo "FAIL missing editor not tolerated"; exit 1; }

echo "unity_repair_modules contract passed"
