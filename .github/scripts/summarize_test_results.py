#!/usr/bin/env python3
import html
import os
import sys
import xml.etree.ElementTree as ET


def command_value(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def command_property(text):
    return command_value(text).replace(":", "%3A").replace(",", "%2C")


def summarize(path):
    if not os.path.isfile(path):
        return [f"No test results at `{path}`: the Editor never reached a verdict. Read the uploaded Editor log."]

    run = ET.parse(path).getroot()
    counts = {key: run.get(key, "0") for key in ("total", "passed", "failed", "skipped", "inconclusive")}
    lines = [
        f"{counts['passed']} passed, {counts['failed']} failed, {counts['skipped']} skipped, "
        f"{counts['inconclusive']} inconclusive, {counts['total']} total."
    ]
    failed = [case for case in run.iter("test-case") if case.get("result") == "Failed"]
    if failed:
        lines += ["", "| Failing test | Message |", "|---|---|"]
    for case in failed:
        name = case.get("fullname", case.get("name", "?"))
        message = (case.findtext("failure/message") or "").strip()
        print(f"::error title={command_property(name)}::{command_value(message)}")
        cell = html.escape(" ".join(message.split())).replace("|", "\\|")
        lines.append(f"| `{name}` | {cell} |")
    return lines


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: summarize_test_results.py <nunit-results.xml> [title]")
    title = sys.argv[2] if len(sys.argv) == 3 else "Test results"
    report = "\n".join([f"## {title}", "", *summarize(sys.argv[1])]) + "\n"
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(report)
    else:
        sys.stdout.write(report)


if __name__ == "__main__":
    main()
