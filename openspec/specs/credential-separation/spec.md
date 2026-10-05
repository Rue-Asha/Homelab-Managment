# credential-separation Specification

## Purpose
TBD - created by archiving change golden-template-and-runner-terraform. Update Purpose after archive.
## Requirements
### Requirement: Each purpose has its own credential

The homelab SHALL use four distinct credentials: a node key (workstation to
`root@proxmox1`), a guest key (workstation to `ansible` on `proxmox_guest`
hosts), a deploy key (runner to `ansible` on `proxmox_guest` hosts), and runner
Terraform credentials (its own PVE API token). No
credential SHALL be accepted for more than its own purpose, and the old
`~/.ssh/Proxmox` key SHALL be removed from the node and every guest.

#### Scenario: Guest key against the node
- **WHEN** the guest key is used to SSH to `proxmox1`
- **THEN** authentication is refused
- **proof:** manual (needs the live node)

#### Scenario: Node key against a guest
- **WHEN** the node key is used to SSH to any guest as `ansible` or `root`
- **THEN** authentication is refused
- **proof:** manual (needs live guests)

#### Scenario: The retired key is used
- **WHEN** `~/.ssh/Proxmox` (if it still exists) is used against the node or any guest
- **THEN** authentication is refused
- **proof:** manual (needs live hosts)

### Requirement: Credentials are named for their purpose and configured explicitly

Terraform variables, `ansible.cfg` and role defaults SHALL reference the node,
guest and deploy keys by purpose-specific names, and no file in the repository
SHALL reference `~/.ssh/Proxmox`.

#### Scenario: The old path is searched for
- **WHEN** `rg 'ssh/Proxmox'` is run over the repository
- **THEN** no match is found in code, configuration or docs
- **proof:** unit (rg check in `scripts/proof.sh`)

### Requirement: The runner's Terraform credentials are separate from the workstation's

The runner SHALL authenticate to the Proxmox API as its own PVE user and token,
distinct from the workstation's, with a custom role carrying only guest
lifecycle privileges. Revoking one token SHALL NOT affect the other. The runner
SHALL hold no SSH credential for `proxmox1` unless a documented provider
operation cannot be performed through the API, in which case it SHALL be a
non-root node user with scoped sudo.

#### Scenario: The workstation token is revoked
- **WHEN** the workstation's API token is deleted
- **THEN** the runner's `terraform plan` still succeeds
- **proof:** manual (needs the live PVE API)

#### Scenario: The runner token is revoked
- **WHEN** the runner's API token is deleted
- **THEN** the runner's `terraform plan` fails and the workstation's token is unaffected
- **proof:** manual (needs the live PVE API)

#### Scenario: The runner is inspected for node SSH
- **WHEN** `~github-runner/.ssh` and its Terraform environment file are listed
- **THEN** no key authorised on `proxmox1` is present, or the only one authorises a non-root user limited by sudo
- **proof:** manual (inspects the live runner)

