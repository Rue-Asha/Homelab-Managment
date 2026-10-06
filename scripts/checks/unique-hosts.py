#!/usr/bin/env python3
"""Fails if two hosts in hosts.auto.tfvars share a vmid or an address. Terraform
cannot catch this at validate time: for_each keys are hostnames, so a clash
only surfaces as a failed apply (or two guests answering on one IP).

    scripts/checks/unique-hosts.py [hosts.auto.tfvars]
"""

import collections
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "terraform/environments/homelab/hosts.auto.tfvars"

seen = {"vmid": collections.defaultdict(list), "ipv4": collections.defaultdict(list)}
host = None
for line in open(path):
    if line.lstrip().startswith("#"):
        continue
    m = re.match(r'\s*"?([\w.-]+)"?\s*=\s*\{', line)
    if m:
        host = m.group(1)
        continue
    m = re.match(r'\s*(vmid|ipv4)\s*=\s*"?([\w./]+)"?', line)
    if m and host:
        value = m.group(2).split("/")[0]
        seen[m.group(1)][value].append(host)

violations = [
    f"{path}: {key} {value} is declared by {', '.join(hosts)}"
    for key, values in seen.items()
    for value, hosts in values.items()
    if len(hosts) > 1
]
if violations:
    print("\n".join(violations))
sys.exit(1 if violations else 0)
