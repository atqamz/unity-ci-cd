#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/summarize_test_results.py"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

cat > "$sandbox/results.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<test-run id="2" testcasecount="3" result="Failed(Child)" total="3" passed="1" failed="2" inconclusive="0" skipped="0">
  <test-suite type="TestFixture" name="SampleTests" fullname="SampleTests" result="Failed" site="Child">
    <failure>
      <message><![CDATA[One or more child tests had errors]]></message>
    </failure>
    <test-case name="Passes" fullname="SampleTests.Passes" result="Passed" />
    <test-case name="FailsOnPurpose" fullname="SampleTests.FailsOnPurpose" result="Failed">
      <failure>
        <message><![CDATA[  arithmetic drifted 100%
  Expected: 2
  But was:  3
]]></message>
        <stack-trace><![CDATA[at SampleTests.FailsOnPurpose () [0x00000] in Assets/Tests/Editor/SampleTests.cs:6
]]></stack-trace>
      </failure>
    </test-case>
    <test-case name="Throws(&quot;a,b&quot;)" fullname="SampleTests.Throws(&quot;a,b&quot;)" result="Failed" label="Error">
      <failure>
        <message><![CDATA[System.InvalidOperationException : boom | <bang>]]></message>
      </failure>
    </test-case>
  </test-suite>
</test-run>
XML

annotations="$(GITHUB_STEP_SUMMARY="$sandbox/summary.md" python3 "$script" "$sandbox/results.xml" "EditMode tests")"
expected_annotations='::error title=SampleTests.FailsOnPurpose::arithmetic drifted 100%25%0A  Expected: 2%0A  But was:  3
::error title=SampleTests.Throws("a%2Cb")::System.InvalidOperationException : boom | <bang>'
[ "$annotations" = "$expected_annotations" ] || { printf 'FAIL annotations:\n%s\n' "$annotations"; exit 1; }

expected_summary="$(cat <<'MD'
## EditMode tests

1 passed, 2 failed, 0 skipped, 0 inconclusive, 3 total.

| Failing test | Message |
|---|---|
| `SampleTests.FailsOnPurpose` | arithmetic drifted 100% Expected: 2 But was: 3 |
| `SampleTests.Throws("a,b")` | System.InvalidOperationException : boom \| &lt;bang&gt; |
MD
)"
[ "$(cat "$sandbox/summary.md")" = "$expected_summary" ] || { printf 'FAIL summary:\n%s\n' "$(cat "$sandbox/summary.md")"; exit 1; }

missing="$(GITHUB_STEP_SUMMARY='' python3 "$script" "$sandbox/absent.xml")"
case "$missing" in
  *"never reached a verdict"*) ;;
  *) printf 'FAIL missing results:\n%s\n' "$missing"; exit 1 ;;
esac

if python3 "$script" > /dev/null 2>&1; then echo "FAIL usage accepted"; exit 1; fi

echo "summarize_test_results contract passed"
