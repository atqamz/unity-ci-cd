#!/usr/bin/env bash
set -euo pipefail

editor_path="${1:?usage: unity_repair_modules.sh <editor-binary>}"
playback_engines="$(dirname "$editor_path")/Data/PlaybackEngines"

if [ ! -d "$playback_engines" ]; then
  echo "No PlaybackEngines directory at $playback_engines; no module to repair."
  exit 0
fi

repaired=0
for module_root in "$playback_engines"/*/; do
  module_root="${module_root%/}"
  module_name="$(basename "$module_root")"
  nested="$module_root/Editor/Data/PlaybackEngines/$module_name"
  [ -d "$nested" ] || continue

  echo "::warning::The $module_name module was unpacked one tree too deep. Moving it to $module_root."
  staged="$(mktemp -d "${RUNNER_TEMP:-/tmp}/unity-module-repair.XXXXXX")"
  rmdir "$staged"
  mv "$nested" "$staged"
  rm -rf "$module_root/Editor"
  (shopt -s dotglob && mv "$staged"/* "$module_root"/)
  rmdir "$staged"
  repaired=$((repaired + 1))
done

for module_root in "$playback_engines"/*/; do
  module_root="${module_root%/}"
  if [ -d "$module_root/Editor/Data/PlaybackEngines/$(basename "$module_root")" ]; then
    echo "::error::$(basename "$module_root") still has a duplicated Editor/Data/PlaybackEngines tree."
    exit 1
  fi
done

echo "Module layout checked: $repaired module(s) repaired."
