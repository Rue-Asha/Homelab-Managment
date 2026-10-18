# tailscale-subnet-router Specification

## Purpose
TBD - created by archiving change add-tailscale-subnet-router. Update Purpose after archive.
## Requirements
### Requirement: tailscale01 is declared in Terraform

`terraform/environments/homelab/hosts.auto.tfvars` SHALL declare `tailscale01` in `lxc_hosts` as an unprivileged LXC with the literal IPv4 `192.168.0.230/24`, group `tailscale`, tags including `terraform`, nesting on (the module default), 1 core, 512 MiB RAM, 512 MiB swap, 4 GiB disk and no declared vmid, so Proxmox assigns it. Applying the change SHALL create exactly one new container and change no existing guest. Because Terraform renders every LXC group under `lxc_container_proxmox` → `proxmox_guest`, `tailscale01` SHALL inherit `proxmox_node_ip` from `group_vars/proxmox_guest`.

#### Scenario: tailscale01 is declared with the agreed identity
- **WHEN** the `tailscale01` entry in `hosts.auto.tfvars` is read
- **THEN** it has `ipv4 = "192.168.0.230/24"`, `groups = ["tailscale"]`, tags including `terraform`, the sizing above, no `vmid`, no `features` override and no `count` or root password anywhere in the diff
- **proof:** manual (diff review of `terraform/`; no sensor distinguishes a literal from a derivation)

#### Scenario: Terraform sensors stay green with the new guest
- **WHEN** `scripts/proof.sh --all` runs with the new entry
- **THEN** `terraform fmt -check`, `terraform validate`, `tflint`, `checkov` and the unique-hosts sensor pass
- **proof:** unit (`scripts/proof.sh --all`: `PASS: terraform validate`, `PASS: Regression: arcade shares IP with check container`)

#### Scenario: An address or hostname collision fails the proof
- **WHEN** another `lxc_hosts` entry declares `192.168.0.230`
- **THEN** `scripts/proof.sh` fails with `DUPLICATE_HOST_ADDRESS`; a duplicate hostname is impossible because `lxc_hosts` is a map keyed by hostname
- **proof:** unit (existing fixture "duplicate ipv4 without vmids" in `scripts/tests/unique-hosts.sh`)

#### Scenario: The runner plan shows exactly one new container
- **WHEN** the PR is merged and `runner01` runs the plan
- **THEN** the plan log lists one `create` for `module.lxc["tailscale01"]` and no change to any other guest, before Rue approves `infrastructure`
- **proof:** manual (post-merge; only `runner01` plans against live state)

#### Scenario: tailscale01 chains to proxmox_guest
- **WHEN** after the apply Rue runs `scripts/fetch-inventory.sh` and `ansible-inventory --graph`
- **THEN** `tailscale01` appears under `tailscale` → `lxc_container_proxmox` → `proxmox_guest` with `ansible_host` `192.168.0.230` and an `lxc_ctid`
- **proof:** manual (post-merge; the inventory is rendered from runner state)

### Requirement: CD never configures the router

No playbook under `ansible/playbooks/02_SERVICES/` SHALL target the `tailscale` group, so a merge never runs the tailscale role or the operator playbook and never restarts the VPN. When the runner's `apply` creates `tailscale01`, `scripts/deploy-targets.sh` SHALL report `deploy-targets: tailscale01 has no 02_SERVICES playbook` on stderr, select nothing for it and exit 0; this warning is expected, as for the runners.

#### Scenario: A merge never runs the operator playbook
- **WHEN** a diff changes `ansible/roles/tailscale/`, `ansible/inventory/host_vars/tailscale01/` and `ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml`
- **THEN** `scripts/deploy-targets.sh` prints no playbook
- **proof:** unit ("Scenario: A merge never runs the operator playbook" in `scripts/tests/deploy-targets.sh`)

#### Scenario: A created tailscale01 gets no deploy
- **WHEN** `--created tailscale01` is passed with a terraform-only diff
- **THEN** stdout is empty, stderr is exactly `deploy-targets: tailscale01 has no 02_SERVICES playbook` and the exit status is 0
- **proof:** unit ("Scenario: A created tailscale01 gets no deploy" in `scripts/tests/deploy-targets.sh`)

#### Scenario: The first merge's deploy run shows the expected warning
- **WHEN** the PR's merge run applies and its `deploy` job starts
- **THEN** the log shows the `tailscale01 has no 02_SERVICES playbook` line, no playbook runs for `tailscale01` and the run is green
- **proof:** manual (post-merge; needs the live runner)

### Requirement: The operator playbook passes TUN through before Tailscale

`ansible/playbooks/01_BASE_CONFIGURATION/tailscale.yml` SHALL consist of two plays on `hosts: tailscale` only: first `proxmox_lxc_tun` with `gather_facts: false`, then `common` and `tailscale` with `become: true`. `ansible/inventory/host_vars/tailscale01/vars.yml` SHALL set `proxmox_lxc_tun_enabled: true`, and no `vault.yml` SHALL exist for `tailscale01`. The playbook SHALL be documented as run by hand from the workstation only, because the runner's key has no node access by design.

#### Scenario: TUN passthrough runs before Tailscale
- **WHEN** `tailscale.yml` and `host_vars/tailscale01/` are read
- **THEN** play 1 applies only `proxmox_lxc_tun` with `gather_facts: false`, play 2 applies `common` then `tailscale` with `become: true`, `proxmox_lxc_tun_enabled` is `true` and there is no `vault.yml`
- **proof:** unit ("Scenario: TUN passthrough runs before Tailscale" in `scripts/tests/tailscale.sh`)

#### Scenario: The operator playbook targets only the tailscale group
- **WHEN** every play in `tailscale.yml` is read
- **THEN** each has `hosts: tailscale`, none targets `github_runner` or `all`, and the file lives under `01_BASE_CONFIGURATION/`, not `02_SERVICES/`
- **proof:** unit ("Scenario: The operator playbook targets only the tailscale group" in `scripts/tests/tailscale.sh`)

#### Scenario: The TUN device exists after the first run
- **WHEN** Rue runs the operator playbook against a fresh `tailscale01`
- **THEN** `/etc/pve/lxc/<ctid>.conf` holds the passthrough block, the container was rebooted once, and `ls -l /dev/net/tun` inside it shows the character device
- **proof:** manual (post-merge; needs the live node)

#### Scenario: A rerun on a host with TUN does not reboot it
- **WHEN** the operator playbook runs again against a `tailscale01` that already has the passthrough
- **THEN** the `blockinfile` task reports `ok` and no reboot handler runs
- **proof:** manual (post-merge second run; part of the `changed=0` Done criterion)

#### Scenario: A recreated container gets the lines in its new config
- **WHEN** `tailscale01` has been recreated with a new CTID and the operator playbook runs
- **THEN** the passthrough block is written to the new `<ctid>.conf`, read from the freshly fetched inventory
- **proof:** manual (needs a live rebuild; exercised at the first rebuild, not part of Done)

### Requirement: The tailscale role installs Tailscale and enables forwarding

`ansible/roles/tailscale` SHALL be restored from `efa9f49^` and follow the repo's role conventions (import-only `tasks/main.yml`, FQCN, `tailscale_`-prefixed variables, no `lineinfile`). It SHALL install the `tailscale` package from the official APT repository for the guest's Debian release, taken from facts and defaulting to `trixie`, never hardcoded to `bookworm`. It SHALL enable and start `tailscaled`, and set `net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` to 1 persistently in `/etc/sysctl.d/`, then verify both live values and fail the play if either is not 1. No task SHALL silence a failed forwarding write.

#### Scenario: The repository URL names trixie when no release fact is known
- **WHEN** the role's defaults are rendered with no gathered facts
- **THEN** the key URL and list URL point at `https://pkgs.tailscale.com/stable/debian/trixie.*`
- **proof:** unit ("Scenario: The repository URL names trixie when no release fact is known" in `scripts/tests/tailscale.sh`)

#### Scenario: Tailscale is installed and running on the guest
- **WHEN** the operator playbook has run against `tailscale01`
- **THEN** `/etc/apt/sources.list.d/tailscale.list` names `trixie`, the `tailscale` package is installed, and `tailscaled` is enabled and active
- **proof:** manual (post-merge; needs the live guest)

#### Scenario: Forwarding is on and survives a restart
- **WHEN** the play has run and the container is restarted
- **THEN** `sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding` prints 1 for both and `/etc/sysctl.d/99-tailscale.conf` holds both keys
- **proof:** manual (post-merge; needs the live guest)

#### Scenario: Forwarding that cannot be set fails the play
- **WHEN** a forwarding sysctl is not writable inside the unprivileged container
- **THEN** the play fails on the sysctl or verify task and does not continue to the join
- **proof:** manual (R1: proven or refuted at the first live run; the diff review checks for no `ignore_errors` or `failed_when: false` on these tasks)

#### Scenario: A second run changes nothing
- **WHEN** the operator playbook runs a second time against a converged `tailscale01` with the key prompt left empty
- **THEN** the recap shows `changed=0`
- **proof:** manual (post-merge; Done criterion)

### Requirement: The router joins with a prompted, never-logged pre-auth key

On a host that is not logged in, the role SHALL run `tailscale up --auth-key=<key> --advertise-routes=192.168.0.0/24 --advertise-tags=tag:subnet-router --accept-dns=false` with `no_log: true`. The key SHALL come from a hidden `vars_prompt` named `tailscale_authkey` (default empty, overridable with `-e`) and SHALL NOT be stored in any tracked file. A logged-in host SHALL NOT be re-authenticated and SHALL need no key; a rerun SHALL converge it to `Running`, so a logged-in but `Stopped` node is brought back with `tailscale up` and the join flags without `--auth-key`. A host is not logged in when its `BackendState` is `NeedsLogin` or `NoState`, or when `tailscale status --json` exits non-zero (counted as `NoState`). A not-logged-in host with an empty key SHALL fail before `tailscale up` with a message that says how to create a tagged pre-auth key and, for `NoState`, that `tailscaled` may be down or unreachable on a node that is in fact logged in. A failed `tailscale up` SHALL fail the play with its error text visible and the key hidden. When the advertised routes or the accept-dns setting in vars differ from the running node's, the role SHALL converge them with `tailscale set` without re-authenticating. The role SHALL NOT disable Tailscale's subnet SNAT.

#### Scenario: Not logged in and no key fails before tailscale up
- **WHEN** the backend state is `NeedsLogin` and `tailscale_authkey` is empty
- **THEN** the play fails with a message naming `tag:subnet-router` and how to create a pre-auth key, and `tailscale up` is never called
- **proof:** unit ("Scenario: Not logged in and no key fails before tailscale up" in `scripts/tests/tailscale.sh`)

#### Scenario: An unreadable backend state counts as not logged in
- **WHEN** `tailscale status --json` reports `NoState` or exits non-zero, and `tailscale_authkey` is empty
- **THEN** the play fails before any `tailscale up` or `tailscale set` call, and the message names `NoState` and says `tailscaled` may be down or unreachable
- **proof:** unit ("Scenario: An unreadable backend state counts as not logged in" in `scripts/tests/tailscale.sh`)

#### Scenario: First join advertises the route and tag
- **WHEN** the backend state is `NeedsLogin` and a key is given
- **THEN** `tailscale up` is called once with `--auth-key=<key> --advertise-routes=192.168.0.0/24 --advertise-tags=tag:subnet-router --accept-dns=false`, and the key appears nowhere in the play output
- **proof:** unit ("Scenario: First join advertises the route and tag" in `scripts/tests/tailscale.sh`)

#### Scenario: A logged-in node is not re-authenticated
- **WHEN** the backend state is `Running`, the node's prefs match the vars and the key is empty
- **THEN** neither `tailscale up` nor `tailscale set` is called, the play succeeds and the join tasks report no change
- **proof:** unit ("Scenario: A logged-in node is not re-authenticated" in `scripts/tests/tailscale.sh`)

#### Scenario: A stopped node is brought back up without a key
- **WHEN** the backend state is `Stopped` (after `tailscale down`) and the key is empty
- **THEN** `tailscale up --advertise-routes=192.168.0.0/24 --advertise-tags=tag:subnet-router --accept-dns=false` is called once without `--auth-key`, and the play succeeds
- **proof:** unit ("Scenario: A stopped node is brought back up without a key" in `scripts/tests/tailscale.sh`)

#### Scenario: Changed advertise settings converge without re-auth
- **WHEN** the backend state is `Running` and the node advertises a route list or accept-dns value different from the vars
- **THEN** `tailscale set --advertise-routes=192.168.0.0/24 --accept-dns=false` is called, `tailscale up` is not, and no key is needed
- **proof:** unit ("Scenario: Changed advertise settings converge without re-auth" in `scripts/tests/tailscale.sh`)

#### Scenario: A rejected key fails the play visibly
- **WHEN** the backend state is `NeedsLogin`, a key is given and `tailscale up` exits non-zero with an error
- **THEN** the play fails, its output contains the error text and not the key, and no later task reports success
- **proof:** unit ("Scenario: A rejected key fails the play visibly" in `scripts/tests/tailscale.sh`)

#### Scenario: The router keeps Tailscale's default SNAT
- **WHEN** `tailscale up` or `tailscale set` is called by the role
- **THEN** neither call contains `--snat-subnet-routes=false`
- **proof:** unit ("Scenario: The router keeps Tailscale's default SNAT" in `scripts/tests/tailscale.sh`)

#### Scenario: The key is prompted hidden
- **WHEN** `tailscale.yml` is read
- **THEN** it declares a `vars_prompt` `tailscale_authkey` with `private: true` and an empty default, and no tracked file under `ansible/` assigns `tailscale_authkey` a non-empty value
- **proof:** unit ("Scenario: The key is prompted hidden" in `scripts/tests/tailscale.sh`)

#### Scenario: A committed auth key fails the proof
- **WHEN** any tracked file contains a string shaped like a real Tailscale key (`tskey-auth-…` or `tskey-client-…` with a key body)
- **THEN** `scripts/proof.sh` fails with `TAILSCALE_KEY_COMMITTED`
- **proof:** unit (sensor "no Tailscale auth key in the repo" in `scripts/proof.sh`, shown red once during the build with a throwaway staged file that is not committed)

#### Scenario: The live join is approved without a click
- **WHEN** Rue runs the operator playbook against the fresh `tailscale01` with a tagged pre-auth key and the policy snippet applied
- **THEN** `tailscale status` on the box shows it connected, and the admin console shows the node tagged `tag:subnet-router` with `192.168.0.0/24` approved and key expiry disabled
- **proof:** manual (post-merge; needs the live tailnet)

### Requirement: The docs carry the one-time tailnet policy snippet

`docs/tailscale-subnet-router.md` SHALL contain the policy snippet to paste once in the admin console: `tagOwners` for `tag:subnet-router` and `autoApprovers.routes` mapping `192.168.0.0/24` to `tag:subnet-router`. It SHALL state that applying it is a manual console step, and its troubleshooting section SHALL start with: route shows "awaiting approval" → the policy is not applied.

#### Scenario: The policy snippet is in the docs
- **WHEN** `docs/tailscale-subnet-router.md` is read
- **THEN** it contains a JSON/HuJSON snippet with `tagOwners` for `tag:subnet-router` and `autoApprovers.routes` `"192.168.0.0/24": ["tag:subnet-router"]`, and says it is pasted by hand once
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: A missing policy is the first troubleshooting line
- **WHEN** the troubleshooting section is read
- **THEN** its first entry maps "route awaiting approval" to the policy not being applied and links the snippet
- **proof:** manual (doc review at Gate 2; prose)

### Requirement: Off-LAN tailnet clients reach the homelab services by IP

With `tailscale01` up and its route approved, a tailnet client outside the home network that accepts subnet routes SHALL reach `http://192.168.0.223`, `http://192.168.0.227`, `http://192.168.0.225/admin` and `https://192.168.0.22:8006` without any static route on the home router. When `tailscale01` is down, only off-LAN access SHALL be lost.

#### Scenario: Services answer from an off-LAN client
- **WHEN** the GrapheneOS phone with Wi-Fi off and Tailscale subnets on opens the four URLs
- **THEN** each answers; the same holds from the E-Ink tablet
- **proof:** manual (post-merge; real devices on a foreign network, Done criterion)

#### Scenario: The laptop reaches a guest from a foreign network
- **WHEN** the Arch laptop is on a foreign network with `tailscale set --accept-routes=true`
- **THEN** `ssh` to a guest succeeds
- **proof:** manual (post-merge; real device on a foreign network, Done criterion)

#### Scenario: A stopped router only cuts off-LAN access
- **WHEN** `tailscale01` is stopped
- **THEN** off-LAN clients lose access to `192.168.0.0/24`, and LAN hosts and other guests keep working
- **proof:** manual (post-merge; needs the live node, checked together with the laptop Done criterion)

#### Scenario: Pi-hole answers queries arriving from the router
- **WHEN** a tailnet client sends a DNS query to `192.168.0.225` through the tunnel
- **THEN** Pi-hole sees it from `192.168.0.230` (SNAT) and answers
- **proof:** manual (post-merge; `dig @192.168.0.225 example.org` from the phone or laptop off-LAN)

### Requirement: The docs contain a client checklist with its reason

`docs/tailscale-subnet-router.md` SHALL contain a client checklist: GrapheneOS phone and E-Ink tablet (log in, enable "use Tailscale subnets"), Arch laptop (default `--accept-routes=false`; on the road `tailscale set --accept-routes=true`, back home `--accept-routes=false`). It SHALL state why: a LAN host that accepts the /24 route loses its LAN path when `tailscale01` stops (previous incident). It SHALL state that phone and tablet at home with Tailscale on hairpin through `tailscale01`, and that the app is switched off when `tailscale01` is down.

#### Scenario: The checklist covers all three devices and the reason
- **WHEN** the client checklist is read
- **THEN** it has steps for the phone, the tablet and the laptop, the laptop's default is `--accept-routes=false` with the on-the-road and back-home commands, and it names the lost-LAN-path incident as the reason
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: Phone at home with the router down is covered
- **WHEN** the checklist's at-home note is read
- **THEN** it says LAN traffic hairpins through `tailscale01` while it is up and to switch the app off when it is down
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: The laptop at home survives a stopped router
- **WHEN** the laptop is at home with `--accept-routes=false` and `tailscale01` is stopped
- **THEN** it still reaches the Proxmox node at `192.168.0.22`
- **proof:** manual (post-merge; real device, Done criterion)

### Requirement: Tailscale docs match the tree

`docs/tailscale-subnet-router.md` SHALL describe the first-rollout and rebuild flows of this change (policy edit, merge, runner plan and `infrastructure` approval, tagged pre-auth key, operator playbook with the key at the prompt; on rebuild, remove the stale node in the admin console first) and the rerun with an empty prompt. It SHALL NOT mention CT 230, `partygames01`, `03_SERVICES`, `02_SERVICES/tailscale.yml`, a manual bootstrap step, a workstation `terraform apply` or a vaulted key. It SHALL contain a post-merge runbook that lists the live rollout steps in order, marks each irreversible or live step ⚠ and names the spec scenario each step answers. It SHALL state that the operator playbook is workstation-only and that CD's `tailscale01 has no 02_SERVICES playbook` warning is expected. `README.md`, `terraform/README.md`, `docs/terraform-ansible-split.md` and the comments in `ansible/roles/proxmox_lxc_tun/` SHALL point to `01_BASE_CONFIGURATION/tailscale.yml` where they mention Tailscale.

#### Scenario: No stale reference remains
- **WHEN** `rg -n 'partygames01|03_SERVICES|02_SERVICES/tailscale|CT 230|tailscale01/vault|bootstrap.yml -l tailscale01|terraform -chdir' docs/tailscale-subnet-router.md README.md terraform/README.md docs/terraform-ansible-split.md ansible/roles/proxmox_lxc_tun` is run
- **THEN** it finds no Tailscale-related match
- **proof:** manual (doc review at Gate 2; the reviewer runs the rg line)

#### Scenario: Rollout and rebuild flows are described
- **WHEN** `docs/tailscale-subnet-router.md` is read
- **THEN** it walks through first rollout, rerun with an empty prompt and rebuild (stale node removed, fresh key, route auto-approved again) in the order of the flows above, and says the playbook runs from the workstation only
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: Other docs point to the operator playbook
- **WHEN** `README.md`, `terraform/README.md`, `docs/terraform-ansible-split.md` and the `proxmox_lxc_tun` comments are read
- **THEN** every Tailscale mention names `01_BASE_CONFIGURATION/tailscale.yml` as the run that applies TUN and Tailscale, and the key is described as prompted, not vaulted
- **proof:** manual (doc review at Gate 2; prose)

#### Scenario: The post-merge runbook lists every live step
- **WHEN** the "Post-merge runbook" section of `docs/tailscale-subnet-router.md` is read
- **THEN** it lists, in order and marked ⚠ where live: policy paste, merge with plan check and `infrastructure` approval, inventory fetch, tagged key, first operator run with on-box and console checks, second run with `changed=0`, client checks, and the `pct stop`/`pct start` laptop-at-home check, each naming the scenario it answers
- **proof:** manual (doc review at Gate 2; prose)

