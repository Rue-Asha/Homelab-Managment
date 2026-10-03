# terraform-ansible-handoff Specification

## Purpose

Terraform is the single source of host identity; Ansible reads its inventory
from what Terraform declares, and the run order between the two layers is
documented. Archived from `add-terraform-provisioning`.

## Requirements

### Requirement: Ansible derives its inventory from Terraform

Ansible SHALL obtain its host list and connection details from an inventory
file that Terraform renders on every apply, `ansible/inventory/00-terraform.yml`.
The file is generated and committed, never hand-edited. The static
`inventory/hosts` file SHALL be removed. A host's IP address, connection user,
and group membership SHALL be declared exactly once, in Terraform.

#### Scenario: Inventory is resolved
- **WHEN** an operator runs `ansible-inventory --graph`
- **THEN** every guest declared in Terraform appears with its correct `ansible_host` and `ansible_user`
- **AND** no host list is read from a static `inventory/hosts` file

#### Scenario: A host's address changes
- **WHEN** a host's IPv4 address is changed in Terraform and applied
- **THEN** the next Ansible run targets the new address with no edit to any Ansible file

#### Scenario: A new host is provisioned
- **WHEN** a new guest is created by `terraform apply`
- **THEN** it appears in the Ansible inventory in its declared groups without any manual inventory edit

### Requirement: Existing group and host variable files continue to apply unchanged

The generated inventory SHALL preserve the current host names and the group
hierarchy — service groups nested under `lxc_container_proxmox` or `vm_proxmox`,
both nested under `proxmox_guest` — so that every existing file under
`ansible/inventory/group_vars/` and `ansible/inventory/host_vars/` continues to resolve to the
same hosts.

#### Scenario: Group hierarchy is preserved
- **WHEN** the generated inventory is compared against the pre-migration static inventory
- **THEN** the set of hosts, group names, and group nesting are identical

#### Scenario: Vaulted host variables still resolve
- **WHEN** a service playbook runs against a host with vaulted `host_vars`
- **THEN** those variables resolve exactly as before the migration

### Requirement: Inventory variables are not hand-maintained

Connection variables produced by Terraform SHALL NOT be duplicated into
`group_vars/` or `host_vars/`. Variables describing infrastructure that
Terraform now owns — container ID derivation, LXC sizing, VM sizing, template
references — SHALL be removed from the Ansible inventory.

#### Scenario: Obsolete inventory variables are gone
- **WHEN** the Ansible inventory is inspected after migration
- **THEN** no variable derives a vmid from an IP address
- **AND** no LXC or VM sizing, template, bridge, or gateway variable remains in `group_vars/`

### Requirement: The Terraform to Ansible run order is documented

The repository SHALL document that infrastructure is applied by Terraform
before any Ansible run, and SHALL name the post-apply Ansible steps that
Terraform cannot perform, including baseline guest bootstrap and any host-level
raw LXC configuration.

#### Scenario: An operator provisions a new service host
- **WHEN** an operator follows the documented procedure for a new service
- **THEN** the documented order is: declare in Terraform, `terraform apply`, run baseline configuration, run any required host-level role, run the service playbook

#### Scenario: The boundary is discoverable
- **WHEN** a contributor reads the repository conventions
- **THEN** the rule that Terraform owns Proxmox-API state and Ansible owns guest-internal state is stated explicitly, along with the ban on Terraform provisioners
