## ADDED Requirements

### Requirement: Dedicated LXC guest

The dashboard web service SHALL run in its own dedicated Proxmox LXC container
(`life-dashboard01`), provisioned by the existing `01_PROVISIONING/lxc_proxmox.yml`
playbook and registered under the `lxc_container_proxmox` inventory group. The
container SHALL NOT share a host with any other service.

#### Scenario: Container is provisioned from inventory

- **WHEN** the LXC provisioning playbook is run for the `life-dashboard` group
- **THEN** a Debian LXC named `life-dashboard01` is created on the Proxmox node with the
  sizing declared in `host_vars/life-dashboard01` (cores, memory, swap, disk) and a
  static LAN IP

#### Scenario: Container is reachable only over LAN or VPN

- **WHEN** the service is running
- **THEN** it is reachable from the homelab LAN or over VPN
- **AND** it is never exposed to the public internet (no inbound :443, no Let's
  Encrypt)

### Requirement: Build-on-host release lifecycle

The service SHALL be deployed by checking out a pinned git version of the
separate dashboard application repository and building it on the host. Each
deploy SHALL produce a new timestamped release directory under
`/opt/life-dashboard/releases/<ts>/`; the build SHALL run a clean dependency install,
the app build command, and a production-only dependency prune.

#### Scenario: New pinned version is deployed

- **WHEN** the service playbook is run and the requested version differs from the
  currently deployed version
- **THEN** the pinned ref is checked out into a fresh timestamped release
  directory
- **AND** dependencies are installed, the app is built, and dev dependencies are
  pruned

#### Scenario: Redeploy of the already-live version is a no-op

- **WHEN** the service playbook is run and the requested version equals the
  currently deployed version
- **THEN** no new release is checked out or built and the running service is left
  untouched

### Requirement: Atomic go-live and rollback

Activating a release SHALL be a single atomic `current` symlink swap pointing at
the target release directory. Rollback SHALL be achievable by repointing the
`current` symlink at a previous release (or re-running at the previous version).
Old releases SHALL be pruned, retaining a configurable number of the most recent
plus the active one.

#### Scenario: Release is activated atomically

- **WHEN** a freshly built release is ready
- **THEN** the `current` symlink is repointed to it in a single operation and the
  service is restarted

#### Scenario: Old releases are pruned

- **WHEN** the number of release directories exceeds the retention count
- **THEN** the oldest releases beyond the retention count are removed, never
  deleting the currently active release

### Requirement: Persistent SQLite storage

The service SHALL persist its data in a SQLite database file located outside the
release directories (under `/var/lib/life-dashboard/`), owned by the service user. A
redeploy SHALL NOT touch, move, or wipe the database file. Database migrations
SHALL be applied against this persistent file on deploy when a migration command
is configured.

#### Scenario: Database survives a redeploy

- **WHEN** a new release is deployed and activated
- **THEN** the existing SQLite database file under `/var/lib/life-dashboard/` is left
  intact and continues to hold prior data

#### Scenario: Migrations run against the persistent database

- **WHEN** a new release is deployed and a migration command is configured
- **THEN** migrations are applied against the persistent database file, not
  against any per-release copy

### Requirement: systemd-supervised runtime

The service SHALL run as an unprivileged, no-login system user under a `systemd`
unit that starts the adapter-node server from the `current` release, restarts on
failure, starts on boot, and reads configuration from an env file. The unit
SHALL bind the backend to loopback only and apply filesystem hardening that
still permits writes to the data directory.

#### Scenario: Service starts on boot and restarts on failure

- **WHEN** the host boots or the service process exits unexpectedly
- **THEN** `systemd` starts (or restarts) the service automatically

#### Scenario: Backend binds to loopback only

- **WHEN** the service is running
- **THEN** the Node process listens on `127.0.0.1:<port>` and is not directly
  reachable on the LAN address

### Requirement: nginx reverse proxy front end

An nginx reverse proxy on the same LXC SHALL terminate the LAN/VPN network on
`:80` and forward to the backend on `127.0.0.1:<port>`, reusing the existing
`nginx` role enabled through host_vars. TLS SHALL default to disabled (plain
HTTP on the trusted network), with self-signed TLS left as a later opt-in.

#### Scenario: Requests are proxied to the backend

- **WHEN** a client on the LAN or VPN requests the service on `:80`
- **THEN** nginx forwards the request to the loopback backend and returns its
  response

### Requirement: Private app repository access

The service SHALL clone the private dashboard application repository over SSH
using a read-only deploy key supplied from the host vault. The deploy key
SHALL be installed with restrictive permissions and never logged. When no deploy
key is provided, the key installation and SSH-specific clone options SHALL be
skipped (supporting a public HTTPS repo).

#### Scenario: Private repo is cloned with the deploy key

- **WHEN** a deploy key is provided in the vault and a new version is deployed
- **THEN** the key is installed with `0600` permissions and used to clone the
  pinned ref, without the key contents appearing in any log output
