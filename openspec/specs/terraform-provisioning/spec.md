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
behaviour, template/ISO reference, and the SSH key seeded at creation are Terraform's
responsibility.

Ansible SHALL NOT create, resize, or delete Proxmox guests. No Ansible role or
playbook may call a Proxmox API module for guest lifecycle.

#### Scenario: A new container is added
- **WHEN** an operator adds an entry to `lxc_hosts` in `hosts.auto.tfvars` and runs `terraform apply`
- **THEN** the container is created on the node with the declared vmid, IP, sizing, and SSH key, and is started

#### Scenario: An existing container is resized
- **WHEN** an operator changes `memory` or `disk_gb` for an already-created host and runs `terraform plan`
- **THEN** the plan shows an in-place update for that container and no change to any other host
- **AND** `terraform apply` applies the new sizing to the running container

#### Scenario: A container is decommissioned
- **WHEN** an operator removes a host's entry from `lxc_hosts` and runs `terraform apply`
- **THEN** Terraform destroys that container on the node and removes it from state

#### Scenario: Drift is detected
- **WHEN** a guest's provider-modelled configuration is changed outside Terraform and `terraform plan` is run
- **THEN** the plan reports the difference between the declared configuration and the live state
- **AND** the container `description` is excluded, because PVE folds the comment markers written by the host-level TUN role into it

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
remains Ansible's responsibility.

#### Scenario: Post-boot configuration is needed
- **WHEN** a newly created container needs its `ansible` user, sudo rule, and baseline hardening
- **THEN** those are applied by an Ansible playbook run after `terraform apply`, not by Terraform

#### Scenario: A raw LXC config key is required
- **WHEN** a guest needs configuration the provider does not model, such as `/dev/net/tun` passthrough via `lxc.mount.entry`
- **THEN** it is applied by a host-level Ansible role delegated to the Proxmox node, and the ordering requirement is documented

### Requirement: Terraform authenticates with a dedicated least-privilege credential

Terraform SHALL authenticate to the Proxmox API as a dedicated user with a
custom PVE role granting only the privileges its operations require. It SHALL
NOT use `root@pam` or a built-in administrator role.

Credentials SHALL be supplied through environment variables sourced from a file
outside the repository. No API token, password, or state file may be committed.

#### Scenario: Credentials are supplied
- **WHEN** an operator runs any Terraform command
- **THEN** the provider reads its endpoint and API token from environment variables
- **AND** no credential value appears anywhere in the repository

#### Scenario: State and secrets are excluded from version control
- **WHEN** `git status` is run after a `terraform apply`
- **THEN** no `*.tfstate`, `*.tfstate.*`, `.terraform/`, or secret-bearing `*.tfvars` file is listed as untracked or modified

#### Scenario: Guest root passwords are not managed
- **WHEN** a container or VM is created by Terraform
- **THEN** no root or cloud-init password is set, and the guest is reachable only by SSH key
- **AND** no `lxc_password` or `vm_ci_password` value remains anywhere in the repository

#### Scenario: The provider version is reproducible
- **WHEN** the repository is cloned and `terraform init` is run
- **THEN** the provider version resolved matches the committed `.terraform.lock.hcl`

### Requirement: Terraform configuration passes formatting, validation, and security gates

Before committing, the Terraform tree SHALL pass `terraform fmt -check`,
`terraform validate`, `tflint`, and an IaC security scan. These gates are part
of the repository's pre-commit contract alongside `ansible-lint`.

#### Scenario: Pre-commit verification
- **WHEN** an operator prepares a commit touching `terraform/`
- **THEN** `terraform fmt -check`, `terraform validate`, `tflint`, and the security scan all report success
