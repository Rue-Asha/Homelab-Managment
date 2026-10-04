# deploy-runner Specification

## Purpose

`runner01` is the self-hosted GitHub Actions runner that executes deploys: an
LXC declared like every other guest, registered to this repository only, running
unprivileged with its own SSH key, verifying guest host keys, and firewalled so
it can reach guests and the internet but not the Proxmox node. Archived from
`cd-homelab`.

## Requirements

### Requirement: The runner host is declared like every other guest

The runner SHALL run in an LXC named `runner01`, declared in
`terraform/environments/homelab/hosts.auto.tfvars` with the inventory group
`github_runner`, and configured by an `ansible/roles/github_runner` role
applied from a playbook under `ansible/playbooks/02_BASE_CONFIGURATION/`. The
runner playbook SHALL NOT live under `03_SERVICES`, so a deploy never
reconfigures the runner executing it.

#### Scenario: Runner role changes are merged
- **WHEN** a merge changes a file under `ansible/roles/github_runner/`
- **THEN** no deploy playbook runs for it, and the change reaches `runner01` only through a manual playbook run

### Requirement: The runner serves this repository only

The runner SHALL be registered as a repository runner on
`Rue-Asha/Homelab-Managment` and on no other repository, with the label
`homelab-deploy`. It SHALL run as an unprivileged `github-runner` user with no
sudo rights, as a systemd service, and SHALL clean its workspace before each
job.

#### Scenario: Another repo asks for the label
- **WHEN** a workflow in `Rue-Asha/Life-Manager` requests `runs-on: [self-hosted, homelab-deploy]`
- **THEN** the job stays queued and never reaches `runner01`

#### Scenario: A job tries to escalate
- **WHEN** a job step runs `sudo -n true` on the runner
- **THEN** the step fails

### Requirement: The runner deploys with its own least-privilege credentials

The runner SHALL authenticate to guests with a dedicated SSH key pair
generated on `runner01`, never with the workstation's key. Its public key SHALL
be authorised for the `ansible` user on `proxmox_guest` hosts and SHALL NOT be
authorised on `proxmox_node` hosts or on the runner itself, where `ansible`'s
sudo would let a job drop the egress firewall. The private key and the Ansible vault
password file SHALL be readable only by `github-runner`, and SHALL be supplied
to jobs through the runner's environment, not through GitHub secrets.

#### Scenario: Repository secrets are inspected
- **WHEN** the repository's Actions and environment secrets are listed
- **THEN** none exist

#### Scenario: Runner key against the Proxmox node
- **WHEN** the runner's key is used to SSH to `proxmox1`
- **THEN** authentication is refused

### Requirement: Host keys are verified on deploy

Deploy runs SHALL verify guest SSH host keys against a `known_hosts` file
maintained on the runner by the `github_runner` role, overriding the repo's
`host_key_checking = False`. A guest whose host key is missing or different
SHALL fail the deploy for that host.

#### Scenario: A guest's host key changes
- **WHEN** `life-manager01` is recreated with a new host key and a deploy targets it
- **THEN** the deploy fails with a host-key verification error until the runner playbook is re-run

### Requirement: The runner's network reach is restricted

`runner01` SHALL drop outbound traffic except DNS, TCP 22 to `proxmox_guest`
hosts, TCP 80 and 443 to addresses outside the local network (80 because
Debian's apt sources are plain http), and the ICMPv6 neighbour discovery and
MLD reports IPv6 needs to stay reachable. Traffic to
`proxmox_node` hosts SHALL be dropped. Because the runner user has no root,
jobs SHALL NOT be able to change these rules.

#### Scenario: A job reaches for the Proxmox API
- **WHEN** a job runs `curl -k https://192.168.0.22:8006`
- **THEN** the connection fails

#### Scenario: A job reaches GitHub
- **WHEN** a job downloads a release asset from `github.com`
- **THEN** the download succeeds
