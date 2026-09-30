#!/usr/bin/env bash
set -euo pipefail

marker="${RUNNER_TEMP:?RUNNER_TEMP must be set}/unity-license-activated-by-this-job"

license_active() {
  env -u UNITY_SERVICE_ACCOUNT_ID -u UNITY_SERVICE_ACCOUNT_SECRET \
    unity license status --format json 2>/dev/null \
    | jq -e '.success == true and .data.active == true' >/dev/null 2>&1
}

editor_batch() {
  timeout "${UNITY_LICENSE_TIMEOUT:-300}" "${UNITY_EDITOR_PATH:?UNITY_EDITOR_PATH must be set}" \
    -batchmode -nographics -quit -logFile - "$@"
}

has_account() {
  [ -n "${UNITY_EMAIL:-}" ] && [ -n "${UNITY_PASSWORD:-}" ]
}

has_service_account() {
  [ -n "${UNITY_SERVICE_ACCOUNT_ID:-}" ] && [ -n "${UNITY_SERVICE_ACCOUNT_SECRET:-}" ]
}

ready() {
  echo "mode=$1" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "Unity license ready: $1."
}

activate() {
  if license_active; then
    ready preexisting
    return 0
  fi

  if [ -z "${UNITY_SERIAL:-}" ]; then
    echo "::error::No Unity license is active on this machine and UNITY_SERIAL is empty. Set UNITY_SERIAL, UNITY_EMAIL and UNITY_PASSWORD, or use a runner that already holds a license."
    return 1
  fi
  echo "::add-mask::$UNITY_SERIAL"
  touch "$marker"

  if has_service_account; then
    timeout 120 unity license activate --serial "$UNITY_SERIAL" || true
    if license_active; then
      ready cli-serial
      return 0
    fi
    echo "::warning::unity license activate --serial left no active license."
  fi

  if has_account; then
    echo "::add-mask::$UNITY_PASSWORD"
    editor_batch -serial "$UNITY_SERIAL" -username "$UNITY_EMAIL" -password "$UNITY_PASSWORD" || true
    if license_active; then
      ready editor-serial
      return 0
    fi
  fi

  echo "::error::Unity license activation failed. Check UNITY_SERIAL, UNITY_EMAIL and UNITY_PASSWORD, and that the account has not reached its activation limit."
  return 1
}

return_license() {
  if [ ! -f "$marker" ]; then
    echo "This job activated no Unity license, so there is nothing to return."
    return 0
  fi

  if timeout 120 unity license return --yes; then
    rm -f "$marker"
    echo "Unity license returned."
    return 0
  fi

  if has_account && [ -x "${UNITY_EDITOR_PATH:-}" ]; then
    echo "::add-mask::$UNITY_PASSWORD"
    if editor_batch -returnlicense -username "$UNITY_EMAIL" -password "$UNITY_PASSWORD"; then
      rm -f "$marker"
      echo "Unity license returned by the Editor."
      return 0
    fi
  fi

  echo "::warning::The Unity license could not be returned. The activation stays registered to this runner's machine identity."
}

case "${1:-}" in
  activate) activate ;;
  return) return_license ;;
  *)
    echo "usage: unity_license.sh activate|return" >&2
    exit 2
    ;;
esac
