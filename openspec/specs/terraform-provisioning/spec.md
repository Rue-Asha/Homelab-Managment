# terraform-provisioning Specification

## Purpose

Proxmox guest lifecycle — existence, identity, sizing, network, and the SSH key
seeded at creation — is declared in Terraform and reconciled from state,
replacing the stateless Ansible provisioning layer. Archived from
`add-terraform-provisioning`.
## Requirements
### Requirement: Guest infrastructure is declared in Terraform

All Proxmox guests (LXC containers and VMs) SHALL be declared in the
`terraform/` tree and reconciled from Terraform state. Guest existence, vmid,
hostname, CPU, memory, swap, disk, network interface, IP configuration, boot
behaviour, and the template/ISO reference are Terraform's responsibility.
Terraform SHALL NOT seed any SSH key into a container's `root` account; access
comes from the template.

Ansible SHALL NOT create, resize, or delete Proxmox guests. No Ansible role or
playbook may call a Proxmox API module for guest lifecycle.

#### Scenario: A new container is added
- **WHEN** an operator adds an entry to `lxc_hosts` in `hosts.auto.tfvars` and the change is applied
- **THEN** the container is created from the homelab template with the declared vmid, IP and sizing, and is started
- **AND** `root` has no authorised key

#### Scenario: An existing container is resized
- **WHEN** an operator changes `memory` or `disk_gb` for an already-created host and runs `terraform plan`
- **THEN** the plan shows an in-place update for that container and no change to any other host
- **AND** applying it changes the running container
- **proof:** manual (plan against live state)

#### Scenario: A container is decommissioned
- **WHEN** an operator removes a host's entry from `lxc_hosts` and the change is applied
- **THEN** Terraform destroys that container on the node and removes it from state
- **proof:** manual (live apply)

#### Scenario: Drift is detected
- **WHEN** a guest's provider-modelled configuration is changed outside Terraform and `terraform plan` is run
- **THEN** the plan reports the difference between the declared configuration and the live state
- **AND** the container `description` and operating system block are excluded
- **proof:** manual (plan against live state)

### Requirement: Host declarations use a keyed map, not positional indexing

Guest declarations SHALL be iterated with `for_each` over a map keyed by
hostname. `count` SHALL NOT be used for guest resources.

#### Scenario: A host is removed from the middle of the catalogue
- **WHEN** an operator deletes one host's entry from the map and runs `terraform plan`
- **THEN** the plan proposes destroying only that host
- **AND** no other host is proposed for replacement or recreation

### Requirement: vmid and IP address are independent declarations

Each guest SHALL declare its vmid and its IPv4 address as separate explicit
fields. Neither SHALL be derived from the other.

#### Scenario: A host is re-addressed
- **WHEN** a host's IPv4 address is changed while its vmid is left unchanged
- **THEN** the plan shows only a network configuration change and the container ID is unaffected

### Requirement: Terraform does not configure guest internals

Terraform configuration SHALL NOT contain `provisioner`, `remote-exec`, or
`local-exec` blocks for guest configuration. Everything inside a guest — users,
sudo, SSH hardening, packages, runtimes, services, application releases —
remains Ansible's responsibility; the template is a seed for first contact, and
Ansible remains the source of truth that converges and rotates it.

#### Scenario: Post-boot configuration is needed
- **WHEN** a newly created container needs baseline hardening
- **THEN** it is applied by an Ansible playbook run, not by Terraform
- **AND** the `ansible` user, sudo rule and keys already exist from the template
- **proof:** manual (needs a live container)

#### Scenario: A raw LXC config key is required
- **WHEN** a guest needs configuration the provider does not model, such as `/dev/net/tun` passthrough via `lxc.mount.entry`
- **THEN** it is applied by a host-level Ansible role delegated to the Proxmox node, and the ordering requirement is documented
- **proof:** manual (needs the live node)

### Requirement: Terraform authenticates with a dedicated least-privilege credential

Terraform SHALL authenticate to the Proxmox API as a dedicated user with a
custom PVE role granting only the privileges its operations require. It SHALL
NOT use `root@pam` or a built-in administrator role. The workstation and the
runner SHALL each use their own user and token.

Credentials SHALL be supplied through environment variables sourced from a file
outside the repository. No API token, password, or state file may be committed.

#### Scenario: Credentials are supplied
- **WHEN** an operator or the runner runs any Terraform command
- **THEN** the provider reads its endpoint and API token from environment variables
- **AND** no credential value appears anywhere in the repository
- **proof:** unit (secrets scan in `scripts/proof.sh`)

#### Scenario: State and secrets are excluded from version control
- **WHEN** `git status` is run after a `terraform apply`
- **THEN** no `*.tfstate`, `*.tfstate.*`, `.terraform/`, `*.tfplan`, or secret-bearing `*.tfvars` file is listed as untracked or modified
- **proof:** manual (needs a live apply)

#### Scenario: Guest root passwords are not managed
- **WHEN** a container or VM is created by Terraform
- **THEN** no root or cloud-init password is set, and the guest is reachable only by SSH key
- **AND** no `lxc_password` or `vm_ci_password` value remains anywhere in the repository
- **proof:** unit (rg check in `scripts/proof.sh`)

#### Scenario: The provider version is reproducible
- **WHEN** the repository is cloned and `terraform init` is run
- **THEN** the provider version resolved matches the committed `.terraform.lock.hcl`
- **proof:** unit (`terraform init -lockfile=readonly` in `scripts/proof.sh`)

### Requirement: Terraform configuration passes formatting, validation, and security gates

Before committing, the Terraform tree SHALL pass `terraform fmt -check`,
`terraform validate`, `tflint`, and an IaC security scan. These gates are part
of the repository's pre-commit contract alongside `ansible-lint`.

#### Scenario: Pre-commit verification
- **WHEN** an operator prepares a commit touching `terraform/`
- **THEN** `terraform fmt -check`, `terraform validate`, `tflint`, and the security scan all report success

### Requirement: Terraform state lives on the runner only

Terraform state SHALL be held by `runner01` at a path outside the job workspace,
and `runner01` SHALL be the only machine that plans or applies. No copy of the
state SHALL exist in the repository or in a GitHub artifact.

#### Scenario: A job wipes its workspace
- **WHEN** a job starts and wipes `$GITHUB_WORKSPACE`
- **THEN** the next `terraform plan` still sees the existing state and proposes no changes for unchanged hosts
- **proof:** manual (needs the live runner)

#### Scenario: The workstation needs the inventory
- **WHEN** an operator runs `scripts/fetch-inventory.sh`
- **THEN** `ansible/inventory/00-terraform.yml` is written from the runner's copy without any Terraform command on the workstation
- **proof:** manual (needs the live runner)

### Requirement: Infrastructure changes apply from the runner after approval

A push to `main` that changes files under `terraform/` SHALL run a plan on
`runner01`, then wait for approval in the `infrastructure` environment (allowed
branch `main`, required reviewer), then apply exactly the saved plan. Terraform
SHALL NOT run on `pull_request` events or anywhere other than `runner01`.
The public job log SHALL show only each resource's address and action, never
attribute values.

#### Scenario: A host is added and merged
- **WHEN** a PR adding an `lxc_hosts` entry is merged to `main`
- **THEN** a plan runs, the run waits for `infrastructure` approval, and after approval the container is created from the saved plan
- **proof:** manual (needs the live runner and GitHub environment)

#### Scenario: A pull request touches Terraform
- **WHEN** a PR changing `terraform/` is opened
- **THEN** no job runs Terraform against the Proxmox API
- **proof:** unit (`scripts/checks/workflow-triggers.py` on the workflow)

#### Scenario: The plan goes stale before approval
- **WHEN** state changes between the plan and the approval
- **THEN** the apply step refuses the saved plan and applies nothing
- **proof:** manual (needs live state)

#### Scenario: The log is read
- **WHEN** the public log of a plan job is read
- **THEN** it lists `<address> <action>` lines and contains no IP addresses or attribute values
- **proof:** manual (inspect a real run)

### Requirement: Terraform never destroys its own runner

A plan that deletes or replaces `runner01` SHALL fail before approval is
requested, because `runner01` runs Terraform and holds its state.

#### Scenario: A protected host would be replaced
- **WHEN** a plan JSON contains a `delete` or `replace` action for `runner01`
- **THEN** `scripts/checks/plan-protected.sh` exits non-zero and no approval is requested
- **proof:** unit ("Scenario: A protected host would be replaced")

#### Scenario: An unprotected host is replaced
- **WHEN** a plan JSON contains a `replace` action only for a non-protected host
- **THEN** `scripts/checks/plan-protected.sh` exits zero
- **proof:** unit ("Scenario: An unprotected host is replaced")

