## ADDED Requirements

### Requirement: The check runner is declared like every other guest

The check runner SHALL run in an LXC named `check01`, declared in
`terraform/environments/homelab/hosts.auto.tfvars` with the inventory group
`check_runner`, and configured by an `ansible/roles/check_runner` role applied
from a playbook in the base-configuration directory, never from the services
directory.

#### Scenario: Check-runner role changes are merged
- **WHEN** a merge changes a file under `ansible/roles/check_runner/`
- **THEN** no deploy playbook runs for it
- **proof:** unit ("Scenario: deploy-targets ignores the check runner" in `scripts/tests/deploy-targets.sh`)

### Requirement: The check runner serves this repository only, under its own label

The runner SHALL be registered as a repository runner on
`Rue-Asha/Homelab-Managment` only, with the label `homelab-check` and not
`homelab-deploy`. It SHALL run as an unprivileged user with no sudo rights, as a
systemd service with `NoNewPrivileges`, and SHALL have its work directory
cleaned before each job.

#### Scenario: A job requests the deploy label
- **WHEN** a job requests `runs-on: [self-hosted, homelab-deploy]`
- **THEN** it never runs on `check01`
- **proof:** manual (needs the live runner)

#### Scenario: A job tries to escalate
- **WHEN** a job step runs `sudo -n true` on the runner
- **THEN** the step fails
- **proof:** manual (needs the live runner)

### Requirement: The check runner holds no credentials

`check01` SHALL hold no deploy key, vault password, Terraform environment file,
PVE token or GitHub token other than the one the runner agent itself keeps. No
key on `check01` SHALL be authorised on any other host. The role SHALL NOT
reference the variables or files `github_runner` uses for those credentials.

#### Scenario: The runner is inspected
- **WHEN** the runner user's home and `/etc` on `check01` are searched for private keys and `*.env` files other than the runner agent's own
- **THEN** none are found
- **proof:** manual (inspects the live runner)

#### Scenario: The role is searched for deploy credentials
- **WHEN** `ansible/roles/check_runner` is searched for `deploy_ed25519`, `vault_pass` and `terraform.env`
- **THEN** no match is found
- **proof:** unit ("Scenario: check runner role has no deploy credentials" in `scripts/proof.sh`)

### Requirement: The check runner's network reach is restricted

`check01` SHALL drop outbound traffic except DNS, TCP 80 and 443 to addresses
outside the private networks, and the ICMPv6 neighbour discovery and MLD reports
IPv6 needs. It SHALL NOT be able to open SSH or any other connection to a guest,
`proxmox_node` hosts or `runner01`. Because the runner user has no root, jobs
SHALL NOT be able to change these rules.

#### Scenario: A job reaches for a guest
- **WHEN** a job runs `ssh ansible@192.168.0.223 true`
- **THEN** the connection fails
- **proof:** manual (needs the live runner)

#### Scenario: A job reaches for the Proxmox node
- **WHEN** a job runs `curl -k https://192.168.0.22:8006`
- **THEN** the connection fails
- **proof:** manual (needs the live runner)

#### Scenario: A job installs its tools
- **WHEN** a job downloads a Terraform provider or a collection from the internet
- **THEN** the download succeeds
- **proof:** manual (needs the live runner)

### Requirement: The toolchain is pinned and owned by root

Every tool `scripts/proof.sh --all` needs SHALL be installed on `check01` at a
pinned version, in a location the runner user cannot write. Terraform and
tflint versions SHALL be role defaults; ansible-core, ansible-lint and checkov
SHALL come from `ci/requirements.txt`.

#### Scenario: A job tries to replace a tool
- **WHEN** a job step overwrites `/usr/local/bin/terraform`
- **THEN** the step fails
- **proof:** manual (needs the live runner)

#### Scenario: A pinned version is bumped
- **WHEN** a version in `ci/requirements.txt` changes
- **THEN** the next run of the check-runner playbook installs it
- **proof:** manual (needs the live runner)

### Requirement: A missing check runner has a documented fallback

`docs/check-runner.md` SHALL describe how to run `proof` on a GitHub-hosted
runner when `check01` is unavailable, without changing the required check name.

#### Scenario: The runner is down
- **WHEN** `check01` is offline and a PR is waiting on `proof`
- **THEN** the documented one-line `runs-on` change makes `proof` run on a hosted runner
- **proof:** manual (documentation walkthrough)
