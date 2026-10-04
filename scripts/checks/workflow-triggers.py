#!/usr/bin/env python3
"""Fails any workflow that a non-collaborator can trigger and that requests a
self-hosted runner. The homelab runner must only ever run code already on main.

    scripts/checks/workflow-triggers.py <workflow.yml>...
"""

import sys

import yaml

UNTRUSTED = {"pull_request", "pull_request_target", "issues", "issue_comment", "fork", "watch", "workflow_run"}


def untrusted(event):
    return event in UNTRUSTED or event.startswith("discussion")


def labels(runs_on):
    if isinstance(runs_on, dict):
        runs_on = [runs_on.get("group"), *(runs_on.get("labels") or [])]
    if not isinstance(runs_on, list):
        runs_on = [runs_on]
    return [str(label) for label in runs_on if label is not None]


violations = []
for path in sys.argv[1:]:
    with open(path) as f:
        workflow = yaml.safe_load(f) or {}
    # YAML 1.1 reads a bare `on:` key as the boolean true.
    on = workflow.get("on", workflow.get(True))
    events = [on] if isinstance(on, str) else list(on or [])
    bad_events = sorted(e for e in events if untrusted(e))
    if not bad_events:
        continue
    for job_id, job in (workflow.get("jobs") or {}).items():
        # An expression could resolve to self-hosted at run time, so it counts.
        if any("self-hosted" in label or "${{" in label for label in labels(job.get("runs-on"))):
            violations.append(
                f"{path}: job '{job_id}' requests a self-hosted runner but the workflow "
                f"triggers on {', '.join(bad_events)}"
            )

if violations:
    print("\n".join(violations))
sys.exit(1 if violations else 0)
