## ADDED Requirements

### Requirement: A custom LXC template makes a new guest immediately manageable

The repository SHALL provide `scripts/build-lxc-template.sh`, which builds a
versioned Debian 13 LXC template `homelab-debian-13-<version>.tar.zst` from the
stock template on the Proxmox node. The template SHALL contain the `ansible`
user, a `visudo`-validated passwordless sudo rule, `python3`, and the guest and
deploy **public** keys authorised for `ansible`. It SHALL contain no private key,
no password and no authorised key for `root`, and SHALL disable root and
password SSH login.

#### Scenario: A guest is created from the template
- **WHEN** a container is created from the template by `terraform apply`
- **THEN** `ssh ansible@<ip> true` succeeds from the workstation with the guest key and from the runner with the deploy key, with no Ansible run in between
- **AND** `ssh root@<ip>` is refused
- **proof:** manual (needs a real Proxmox node and a booted container)

#### Scenario: The build is repeated for an existing version
- **WHEN** the build script is run for a version whose template file already exists
- **THEN** it exits non-zero and leaves the existing file untouched
- **proof:** manual (needs the Proxmox node's template storage)

### Requirement: Guests created from the template have unique host identity

Every guest created from the template SHALL generate its own SSH host keys and
`machine-id` on first boot. The template SHALL NOT ship host keys or a
`machine-id`.

#### Scenario: Two guests from one template
- **WHEN** two containers are created from the same template version
- **THEN** their SSH host key fingerprints differ
- **proof:** manual (needs two booted containers)

### Requirement: Template version bumps do not replace existing containers

The `proxmox_lxc` module SHALL ignore changes to a container's operating system
block after creation. Re-imaging a host SHALL be an explicit `-replace` of that
host.

#### Scenario: The template reference is bumped
- **WHEN** `lxc_template_file_id` is changed to a newer template version and `terraform plan` is run
- **THEN** the plan proposes no change to any existing container
- **proof:** manual (plan against live state)

### Requirement: Public keys are the single source for authorised keys

The guest and deploy public keys SHALL be committed under `ansible/keys/` and
read from there by both the template build script and the `guest_bootstrap`
role. Private keys SHALL NOT be committed.

#### Scenario: A public key file is replaced
- **WHEN** `ansible/keys/guest_ed25519.pub` changes and `guest_bootstrap` is run against an existing guest
- **THEN** the guest's `ansible` `authorized_keys` contains exactly the keys in `ansible/keys/` and no others
- **proof:** manual (needs a live guest)
