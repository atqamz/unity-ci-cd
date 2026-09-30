#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unity_license.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/bin"
cat > "$sandbox/bin/unity" <<'STUB'
#!/usr/bin/env bash
echo "unity $*" >> "$STUB/calls"
case "$1 $2" in
  "license status")
    [ -z "${UNITY_SERVICE_ACCOUNT_ID:-}" ] || echo "service account leaked into status" >> "$STUB/calls"
    if [ -f "$STUB/active" ]; then active=true; else active=false; fi
    printf '{"success":true,"data":{"active":%s}}\n' "$active"
    ;;
  "license activate")
    [ -f "$STUB/cli-activates" ] && touch "$STUB/active"
    [ -f "$STUB/cli-activates" ]
    ;;
  "license return")
    [ -f "$STUB/cli-returns" ] && rm -f "$STUB/active"
    [ -f "$STUB/cli-returns" ]
    ;;
esac
STUB
cat > "$sandbox/bin/editor" <<'STUB'
#!/usr/bin/env bash
echo "editor $*" >> "$STUB/calls"
case " $* " in
  *" -serial "*)
    [ -f "$STUB/editor-activates" ] && touch "$STUB/active"
    exit 0
    ;;
  *" -returnlicense "*)
    [ -f "$STUB/editor-returns" ] && rm -f "$STUB/active"
    [ -f "$STUB/editor-returns" ]
    ;;
esac
STUB
chmod +x "$sandbox/bin/unity" "$sandbox/bin/editor"

case_number=0
start_case() {
  case_number=$((case_number + 1))
  export STUB="$sandbox/case-$case_number"
  export RUNNER_TEMP="$STUB/runner-temp"
  export GITHUB_OUTPUT="$STUB/output"
  mkdir -p "$RUNNER_TEMP"
  : > "$STUB/calls"
  : > "$GITHUB_OUTPUT"
  for flag in "$@"; do touch "$STUB/$flag"; done
}

fail() {
  echo "FAIL case $case_number: $1"
  echo "calls:"
  cat "$STUB/calls"
  exit 1
}

run() {
  local action="$1"
  shift
  env PATH="$sandbox/bin:$PATH" UNITY_EDITOR_PATH="$sandbox/bin/editor" "$@" bash "$script" "$action" > "$STUB/stdout" 2>&1
}

marker() {
  [ -f "$RUNNER_TEMP/unity-license-activated-by-this-job" ]
}

account=(UNITY_SERIAL=SERIAL-1 UNITY_EMAIL=ci@example.com UNITY_PASSWORD=hunter2)
service_account=(UNITY_SERVICE_ACCOUNT_ID=key-id UNITY_SERVICE_ACCOUNT_SECRET=key-secret)

start_case active
run activate "${account[@]}" "${service_account[@]}" || fail "preexisting license failed"
grep -qx 'mode=preexisting' "$GITHUB_OUTPUT" || fail "preexisting license not reported"
! grep -q 'activate' "$STUB/calls" || fail "preexisting license was re-activated"
! marker || fail "preexisting license marked for return"
run return "${account[@]}" || fail "return after preexisting failed"
! grep -q 'return' "$STUB/calls" || fail "preexisting license was returned"
[ -f "$STUB/active" ] || fail "preexisting license disappeared"

start_case
if run activate UNITY_EMAIL=ci@example.com UNITY_PASSWORD=hunter2; then fail "activated without a serial"; fi
grep -q '::error::No Unity license is active' "$STUB/stdout" || fail "missing serial not explained"

start_case cli-activates cli-returns
run activate "${account[@]}" "${service_account[@]}" || fail "CLI activation failed"
grep -qx 'mode=cli-serial' "$GITHUB_OUTPUT" || fail "CLI activation not reported"
! grep -q '^editor' "$STUB/calls" || fail "Editor ran after CLI activation succeeded"
marker || fail "CLI activation not marked for return"
run return "${account[@]}" || fail "CLI return failed"
! marker || fail "marker left after CLI return"
[ ! -f "$STUB/active" ] || fail "license still active after CLI return"

start_case editor-activates editor-returns
run activate "${account[@]}" "${service_account[@]}" || fail "Editor fallback failed"
grep -qx 'mode=editor-serial' "$GITHUB_OUTPUT" || fail "Editor activation not reported"
grep -q '^unity license activate --serial SERIAL-1' "$STUB/calls" || fail "CLI activation not tried first"
grep -q '^editor .*-serial SERIAL-1 -username ci@example.com -password hunter2' "$STUB/calls" || fail "Editor not given the account"
run return "${account[@]}" || fail "Editor return failed"
grep -q '^editor .*-returnlicense' "$STUB/calls" || fail "Editor return not tried after CLI return failed"
! marker || fail "marker left after Editor return"

start_case editor-activates
run activate "${account[@]}" || fail "Editor activation without service account failed"
! grep -q '^unity license activate' "$STUB/calls" || fail "CLI activation tried without a service account"
grep -qx 'mode=editor-serial' "$GITHUB_OUTPUT" || fail "Editor activation not reported"

start_case
if run activate "${account[@]}"; then fail "activation reported success with no license"; fi
grep -q '::error::Unity license activation failed' "$STUB/stdout" || fail "activation failure not explained"
marker || fail "failed activation not marked for return"
run return "${account[@]}" || fail "return must not fail the job"
grep -q '::warning::The Unity license could not be returned' "$STUB/stdout" || fail "failed return not warned"

! grep -rq 'service account leaked' "$sandbox"/case-*/calls || { grep -r 'leaked' "$sandbox"/case-*/calls; exit 1; }

if bash "$script" > /dev/null 2>&1; then echo "FAIL usage accepted"; exit 1; fi

echo "unity_license contract passed ($case_number cases)"
