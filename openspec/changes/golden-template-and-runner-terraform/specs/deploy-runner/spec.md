## MODIFIED Requirements

### Requirement: The runner deploys with its own least-privilege credentials

The runner SHALL authenticate to guests with a dedicated SSH key pair
generated on `runner01`, never with the workstation's key. Its public key SHALL
be authorised for the `ansible` user on `proxmox_guest` hosts and SHALL NOT be
authorised on `proxmox_node` hosts or on the runner itself, where `ansible`'s
sudo would let a job drop the egress firewall. A guest created from the
template carries the deploy public key, so `guest_bootstrap` SHALL remove it
from `runner01`. The private key, the Ansible vault password file and the
runner's Terraform environment file SHALL be readable only by `github-runner`,
and SHALL be supplied to jobs through the runner's environment, not through
GitHub secrets.

#### Scenario: Repository secrets are inspected
- **WHEN** the repository's Actions and environment secrets are listed
- **THEN** none exist
- **proof:** manual (GitHub settings)

#### Scenario: Runner key against the Proxmox node
- **WHEN** the runner's key is used to SSH to `proxmox1`
- **THEN** authentication is refused
- **proof:** manual (needs the live node)

#### Scenario: Runner key against the runner
- **WHEN** `guest_bootstrap` has run against `runner01`
- **THEN** the deploy public key is absent from `ansible`'s `authorized_keys` on `runner01`
- **proof:** manual (needs the live runner)

### Requirement: Host keys are verified on deploy

Deploy runs SHALL verify guest SSH host keys against a `known_hosts` file
maintained on the runner, overriding the repo's `host_key_checking = False`. The
file is seeded by the `github_runner` role and extended by the `apply` job with
the host keys of guests that apply created. A key SHALL never be overwritten by
the `apply` job. A guest whose host key is missing or different SHALL fail the
deploy for that host.

#### Scenario: A guest's host key changes
- **WHEN** `life-manager01` is recreated with a new host key outside the `apply` job and a deploy targets it
- **THEN** the deploy fails with a host-key verification error until the runner playbook is re-run
- **proof:** manual (needs a live recreated guest)

#### Scenario: A new guest is created by the apply job
- **WHEN** `apply` creates a new guest and a service deploy targets it in the same run
- **THEN** the deploy connects without a host-key prompt and without a manual runner playbook run
- **proof:** manual (needs a live guest and the runner)

### Requirement: The runner's network reach is restricted

`runner01` SHALL drop outbound traffic except DNS, TCP 22 to the declared guest
range excluding `proxmox_node` hosts and the runner itself, TCP 8006 to
`proxmox_node` hosts, TCP 80 and 443 to addresses outside the local network (80
because Debian's apt sources are plain http), and the ICMPv6 neighbour discovery
and MLD reports IPv6 needs to stay reachable. All other traffic to
`proxmox_node` hosts, including SSH, SHALL be dropped. Because the runner user
has no root, jobs SHALL NOT be able to change these rules.

#### Scenario: A job reaches for the Proxmox API
- **WHEN** a job runs `curl -k https://192.168.0.22:8006`
- **THEN** the connection succeeds
- **proof:** manual (needs the live runner)

#### Scenario: A job reaches for the Proxmox node over SSH
- **WHEN** a job runs `ssh root@192.168.0.22 true`
- **THEN** the connection fails
- **proof:** manual (needs the live runner)

#### Scenario: A job reaches GitHub
- **WHEN** a job downloads a release asset from `github.com`
- **THEN** the download succeeds
- **proof:** manual (needs the live runner)

#### Scenario: A new guest inside the guest range
- **WHEN** a guest is created with an address inside the declared guest range
- **THEN** the runner can open SSH to it without the firewall being reconfigured
- **proof:** manual (needs the live runner)
