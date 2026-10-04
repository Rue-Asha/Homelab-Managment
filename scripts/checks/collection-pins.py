#!/usr/bin/env python3
"""Fails unless every collection in the given requirements files is pinned to
an exact version, so a deploy installs the same collection code CI linted.

    scripts/checks/collection-pins.py <requirements.yml>...
"""

import re
import sys

import yaml

EXACT = re.compile(r"\d+\.\d+\.\d+")

violations = []
for path in sys.argv[1:]:
    with open(path) as f:
        requirements = yaml.safe_load(f) or {}
    for entry in requirements.get("collections") or []:
        name = entry if isinstance(entry, str) else entry.get("name")
        version = None if isinstance(entry, str) else entry.get("version")
        if not (isinstance(version, str) and EXACT.fullmatch(version)):
            violations.append(f"{path}: {name} is not pinned to an exact version (version: {version!r})")

if violations:
    print("\n".join(violations))
sys.exit(1 if violations else 0)
