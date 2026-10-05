## MODIFIED Requirements

### Requirement: Ansible derives its inventory from Terraform

Ansible SHALL obtain its host list and connection details from
`ansible/inventory/00-terraform.yml`, rendered on `runner01` from a Terraform
output by `scripts/render-inventory.sh` and fetched to the workstation by
`scripts/fetch-inventory.sh`. The file is generated, git-ignored and never
hand-edited, so applying on the runner does not
require a commit to `main`. A host's IP address, connection user and group
membership SHALL be declared exactly once, in Terraform.

#### Scenario: Inventory is resolved
- **WHEN** an operator runs `scripts/fetch-inventory.sh` and then `ansible-inventory --graph`
- **THEN** every guest declared in Terraform appears with its correct `ansible_host` and `ansible_user`
- **AND** no host list is read from a static `inventory/hosts` file
- **proof:** manual (needs the live runner)

#### Scenario: A host's address changes
- **WHEN** a host's IPv4 address is changed in Terraform and applied
- **THEN** the next Ansible run, after fetching the inventory, targets the new address with no edit to any Ansible file
- **proof:** manual (needs the live runner)

#### Scenario: A new host is provisioned by the runner
- **WHEN** the `apply` job creates a guest
- **THEN** the `deploy` job in the same run renders the inventory and finds the guest in its declared groups, and no commit is made
- **proof:** manual (needs the live runner)

#### Scenario: The proof gate runs without live state
- **WHEN** `scripts/proof.sh --all` runs in CI, where no state is available
- **THEN** syntax-check and lint pass without any inventory file present
- **proof:** unit (`scripts/proof.sh --all`)

### Requirement: The Terraform to Ansible run order is documented

The repository SHALL document that infrastructure is applied by Terraform
before any Ansible run, and SHALL name the post-apply Ansible steps Terraform
cannot perform: baseline `common` configuration and any host-level raw LXC
configuration. No root-connecting bootstrap step SHALL remain.

#### Scenario: An operator provisions a new service host
- **WHEN** an operator follows the documented procedure for a new service
- **THEN** the documented order is: declare in Terraform, merge and approve the apply, run baseline configuration, run any required host-level role, run the service playbook
- **proof:** manual (documentation review)

#### Scenario: The boundary is discoverable
- **WHEN** a contributor reads the repository conventions
- **THEN** the rule that Terraform owns Proxmox-API state and Ansible owns guest-internal state is stated explicitly, along with the ban on Terraform provisioners and the role of the template as first-contact seed
- **proof:** manual (documentation review)
