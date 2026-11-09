#!/usr/bin/env python3
"""Fail unless an xccov JSON report covers the named target at or above the percent."""
import json
import sys

path, name, minimum = sys.argv[1], sys.argv[2], float(sys.argv[3])
report = json.load(open(path))
targets = report.get("targets", [])
match = next((item for item in targets if name in item.get("name", "")), None)
if match is None:
    names = [item.get("name", "") for item in targets]
    raise SystemExit(f"coverage target {name} not in {names}")
covered = float(match.get("lineCoverage", 0)) * 100
print(f"{name} line coverage {covered:.2f}%")
if covered < minimum:
    raise SystemExit(f"{name} line coverage {covered:.2f}% is below {minimum:.0f}%")
