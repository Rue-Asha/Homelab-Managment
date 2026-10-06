# check-runner Specification

## Purpose
`check01` is the self-hosted GitHub Actions runner the CI `proof` check runs
on: an LXC declared like every other guest, registered to this repository only
under the label `homelab-check`, running unprivileged with a root-owned pinned
toolchain, holding no credentials and firewalled so it reaches the internet but
no guest, node or other runner. Archived from `add-check-runner`.
## Requirements
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

### Requirement: The check runner holds no credentials

`check01` SHALL hold no deploy key, vault password, Terraform environment file,
PVE token, GitHub token or registration token other than the credential each
runner instance's agent keeps for itself. No key on `check01` SHALL be
authorised on any other host. The role SHALL NOT reference the variables or
files `github_runner` uses for those credentials. The `gh` login used to mint
registration tokens SHALL stay on the workstation.

#### Scenario: The runner is inspected
- **WHEN** every instance user's home and `/etc` on `check01` are searched for private keys, `*.env` files and `gh` configuration other than the runner agents' own files
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
pinned version, in a location no instance user can write. Terraform and tflint
versions SHALL be role defaults; ansible-core, ansible-lint and checkov SHALL
come from `ci/requirements.txt`. The system libraries that headless Chromium
needs for Playwright SHALL be installed by the role as an apt package list, so
a job never needs `--with-deps`. Per-repo runtimes such as Node SHALL NOT be
baked into the host; jobs install them into their own instance's tool cache.

#### Scenario: A job tries to replace a tool
- **WHEN** a job step overwrites `/usr/local/bin/terraform`
- **THEN** the step fails
- **proof:** manual (needs the live runner)

#### Scenario: A pinned version is bumped
- **WHEN** a version in `ci/requirements.txt` changes
- **THEN** the next run of the check-runner playbook installs it
- **proof:** manual (needs the live runner)

#### Scenario: A Node repo runs its e2e tests
- **WHEN** a `Life-Manager` PR check runs `npx playwright install chromium` and its e2e suite on `check01`
- **THEN** the browser starts without missing shared libraries and without sudo
- **proof:** manual (needs the live runner and the app repo's PR)

### Requirement: A missing check runner has a documented fallback

`docs/check-runner.md` SHALL describe, for every repo in `check_runner_repos`,
how to run its PR check on a GitHub-hosted runner while `check01` is
unavailable, without changing the required check name.

#### Scenario: The runner is down
- **WHEN** `check01` is offline and a PR in any listed repo is waiting on its check
- **THEN** the documented one-line `runs-on` change in that repo makes the check run on a hosted runner
- **proof:** manual (documentation walkthrough)

### Requirement: The check host runs one runner instance per listed repository

The `check_runner` role SHALL read a list `check_runner_repos`, set in
`group_vars/check_runner`. For each entry it SHALL configure one runner
instance, registered as a repository runner on that repo only, with the label
`homelab-check` and never `homelab-deploy`. Adding a repo SHALL need nothing
but a new list entry and one run of `01_BASE_CONFIGURATION/check_runner.yml`.
Removing an entry SHALL stop and disable that instance's unit on the next run.

#### Scenario: A repo is added to the list
- **WHEN** a repo is appended to `check_runner_repos` and the playbook runs
- **THEN** a new instance for it is registered and online in that repo's Settings → Actions → Runners with label `homelab-check`, and the other instances are not restarted
- **proof:** manual (needs the live runner and GitHub)

#### Scenario: The playbook runs again with nothing changed
- **WHEN** the playbook runs a second time with the same list
- **THEN** no registration token is minted and no task reports a change
- **proof:** manual (needs the live runner and GitHub)

#### Scenario: A job requests the deploy label
- **WHEN** a job in any listed repo requests `runs-on: [self-hosted, homelab-deploy]`
- **THEN** it never runs on `check01`
- **proof:** manual (needs the live runner)

#### Scenario: Two entries would share an instance
- **WHEN** `check_runner_repos` contains two entries that resolve to the same instance name
- **THEN** the play fails before it changes anything on the host
- **proof:** manual (assert in the role; exercised by a `--check` run with a duplicated entry)

### Requirement: Every instance is isolated from the others

Each instance SHALL run under its own unprivileged unix user, with no sudo
rights. Its runner directory, work directory and tool cache SHALL sit in that
user's home, and the home directory SHALL have mode `0700`. It SHALL run as its
own systemd unit with `NoNewPrivileges`. Its workspace SHALL be emptied before
each job by a root-owned hook.

#### Scenario: A job reads another repo's runner
- **WHEN** a job in one repo runs `ls` on another instance's home directory
- **THEN** the step fails with permission denied
- **proof:** manual (needs the live runner)

#### Scenario: A job tries to escalate
- **WHEN** a job step runs `sudo -n true` on any instance
- **THEN** the step fails
- **proof:** manual (needs the live runner)

### Requirement: Registration needs a fork-approval policy and a workstation-minted token

Before it registers an instance, the playbook SHALL read the repo's fork-PR
contributor approval policy from the GitHub API and fail unless it is
`all_external_contributors`. The registration token SHALL be minted with `gh`
on the controller (`delegate_to: localhost`), only for instances that aren't
registered yet, and passed straight to `config.sh` without being logged or
written to a file on `check01`. The playbook SHALL NOT change any GitHub
setting.

#### Scenario: A repo still lets outside contributors run without approval
- **WHEN** a listed repo's approval policy is anything other than `all_external_contributors`
- **THEN** the play fails for that repo before any token is minted, naming the repo
- **proof:** manual (needs GitHub)

#### Scenario: Token handling leaves nothing behind
- **WHEN** a registration has completed
- **THEN** the play output shows no token, and searching `check01` for the token string finds nothing outside the runner agent's own credential files
- **proof:** manual (inspects the live runner)

### Requirement: Release builds never run on the check host

Release builds SHALL run on a GitHub-hosted runner: any workflow that builds
an artifact which gets deployed (a release tarball). Only PR and `main` checks SHALL request
`homelab-check`. A repo whose check job is also called by its release workflow
SHALL split the two before the check moves to `check01`.

#### Scenario: A release tag is pushed
- **WHEN** a release tag is pushed in `Life-Manager` or `Rues-Arcade`
- **THEN** every job that produces the release tarball runs on `ubuntu-24.04`
- **proof:** manual (inspects the app repo's release run)

