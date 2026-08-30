## Context

The homelab is one Proxmox node (`ray` @ `192.168.0.22`) running four LXCs
(`pihole01 .225`, `partygames01 .224`, `life-dashboard01 .223`,
`tailscale01 .230`) on a flat `192.168.0.0/24`. Everything is driven from one
Ansible repo, control-host-initiated, with `.vault_pass` on disk and an SSH key
at `~/.ssh/Proxmox`.

Provisioning currently calls `community.proxmox` modules with
`delegate_to: localhost` against a `root@pam!ansible` API token. Because Ansible
has no state, each role hand-rolls the reconciliation:
`roles/proxmox_lxc/tasks/preflight.yml` queries the API, derives
`lxc_exists`, asserts free space, and `create.yml` then runs only
`when: not lxc_exists`. That makes creation idempotent but makes **update** and
**destroy** unrepresentable.

Host identity is encoded in `inventory/hosts` (IP + user) and derived in
`inventory/group_vars/proxmox_guest/vars.yml`:

```yaml
id: "{{ ansible_host.split('.')[-1] | int }}"   # vmid = 4th octet of the IP
```

so vmid and IP are welded together — pihole01 is CT 225 *because* it is `.225`.

Constraints:
- Single operator, single node, no CI runner, no shared state today.
- `.claude/CLAUDE.md` conventions: playbook categories `NN_UPPER_SNAKE_CASE`,
  role vars prefixed, no vars in `inventory/hosts`, host-level concerns must not
  live in service/app roles, `ansible-lint` clean before commit.
- The app-per-LXC / two-repo / build-on-host service model must survive
  unchanged — it is the repo's defining architecture.
- Terraform is **not currently installed** on the control host.

## Goals / Non-Goals

**Goals:**
- Give guest infrastructure a real desired-state lifecycle: create, **update**,
  and **destroy**, with `terraform plan` as a reviewable diff before any change.
- Adopt the four running LXCs into Terraform **without rebuilding them** — no
  downtime, no data loss on `life-dashboard01`'s SQLite file or `pihole01`'s
  config.
- Draw one unambiguous, documented boundary between Terraform and Ansible so
  neither layer reimplements the other.
- Keep exactly one definition of each host — Terraform — with Ansible reading
  from it, not duplicating it.
- Exercise the practices that transfer to cloud security work: state handling,
  least-privilege credentials, plan review, IaC scanning.

**Non-Goals:**
- Replacing Ansible. Guest-internal configuration stays Ansible (see D6).
- Multi-node, multi-environment, or multi-workspace layouts. One node, one
  environment, one state — structured so a second can be added later without a
  rewrite.
- Remote state, PVE RBAC/firewall/SDN as code, Tailscale ACLs as code, Packer
  images. All are logged as follow-ups in D11, none are in this change.
- Immutable infrastructure. Guests stay long-lived and mutable; that is what the
  build-on-host deploy model assumes.
- Automating the manual Tailscale admin-console steps (route approval, key
  expiry) — unchanged from `add-tailscale-subnet-router`.

## Decisions

### D1: Same repo, new top-level `terraform/` — not a second repo

Terraform and Ansible go in **this** repo, side by side.

The two layers are coupled by the same facts: vmid, IP, hostname, sizing, SSH
key. Splitting them across repos means a host rename becomes two PRs in two
repos with an ordering dependency and no atomic revert, and the Ansible side
must then either duplicate the host list or reach across a repo boundary for
state. The usual reasons orgs split IaC repos — separate teams, separate
approval chains, separate blast radius, different credential scopes per repo —
do not exist for a single-operator homelab. Adopting the split anyway buys the
ceremony without the benefit.

Co-locating also makes the handoff in D7 trivial: the Ansible inventory plugin
points at a relative path, not a cross-repo artifact fetch.

- *Alternative: separate `Homelab-Infra` repo.* Rejected for the above. It is
  the right call once there are multiple nodes/environments with different
  people or credentials owning them — revisit then, and the module layout in D3
  is chosen so the `terraform/` tree can be lifted out whole.
- *Alternative: `terraform/` nested under `playbooks/01_PROVISIONING/`.*
  Rejected — it implies Terraform is a step inside an Ansible run. It is a
  peer layer that runs first, on its own.

Resulting layout:

```
terraform/
  environments/
    homelab/                 # the single root module — one state, one node
      versions.tf            # required_version + provider constraints
      providers.tf           # bpg/proxmox + ansible provider config
      variables.tf
      hosts.auto.tfvars      # ← the host catalogue (replaces inventory/hosts)
      containers.tf          # module "lxc" for_each over var.lxc_hosts
      vms.tf                 # module "vm"  for_each over var.vm_hosts
      ansible.tf             # ansible_host / ansible_group resources (D7)
      imports.tf             # import blocks for the four live LXCs (D9)
      outputs.tf
  modules/
    proxmox_lxc/             # main.tf variables.tf outputs.tf versions.tf
    proxmox_vm/
  README.md                  # bootstrap + day-2 commands
playbooks/
  00_OPERATIONAL/
  02_BASE_CONFIGURATION/     # ← gains bootstrap.yml (was empty)
  03_SERVICES/               # unchanged
inventory/
  terraform.yml              # ← inventory plugin config (replaces `hosts`)
  group_vars/                # unchanged
  host_vars/                 # unchanged
roles/                       # minus proxmox_lxc, proxmox_vm_iso, proxmox_vm_template
```

`playbooks/01_PROVISIONING/` is removed entirely. The `NN_` ordering still
reads correctly: Terraform is the new step "00" that precedes `02_`.

### D2: `bpg/proxmox` provider, not `Telmate/proxmox`

`bpg/proxmox` is the actively maintained Proxmox provider, covers both
`proxmox_virtual_environment_container` and `_vm`, supports API-token auth, and
exposes the resources needed for the D11 roadmap (users, roles, ACLs, firewall,
file downloads). `Telmate/proxmox` is the older community provider with thinner
LXC support and a slower release cadence.

Provider version is pinned with `~>` in `versions.tf`, and `.terraform.lock.hcl`
**is committed** — it is the Terraform equivalent of the pinned refs the service
roles already use for application code.

- *Alternative: keep `community.proxmox` Ansible modules and add no provider.*
  Rejected — that is the status quo this change exists to fix.
- OpenTofu is a drop-in substitute if licensing ever matters; the configuration
  is written to work with either, but the toolchain standardises on Terraform
  because that is the name on job descriptions.

### D3: One root module per environment, thin reusable child modules

`environments/homelab/` is the only root module and holds the only state file.
`modules/proxmox_lxc` and `modules/proxmox_vm` are thin wrappers that encode the
homelab's opinions (unprivileged by default, `start_on_boot`, Debian template,
`vmbr0`, `/24`, gateway `.1`, the SSH public key) so a new host is a few lines
of tfvars rather than a full resource block.

Child modules take a flat variable set and expose `vmid`, `ipv4_address`, and
`hostname` as outputs. No `count`/`for_each` **inside** the modules — the
fan-out happens at the root, which keeps state addresses readable
(`module.lxc["pihole01"]`) and lets a single host be targeted or destroyed.

- *Alternative: no modules, raw resources in the root.* Rejected — four hosts
  today, and the LXC resource block is ~40 lines of which 35 are identical
  across hosts.
- *Alternative: Terraform workspaces per host/service.* Rejected — workspaces
  are for identical copies of an environment, not for slicing one environment.

### D4: Hosts declared as a map in `hosts.auto.tfvars`

The host catalogue is one map keyed by hostname, iterated with `for_each`:

```hcl
lxc_hosts = {
  pihole01 = {
    vmid = 225, ipv4 = "192.168.0.225/24"
    cores = 1, memory = 1024, swap = 512, disk_gb = 8
    groups = ["pihole"]
  }
  life-dashboard01 = {
    vmid = 223, ipv4 = "192.168.0.223/24"
    cores = 2, memory = 2048, swap = 512, disk_gb = 12
    groups = ["life_dashboard"]
  }
  # ...
}
```

`for_each` (not `count`) is mandatory: with `count`, deleting a host in the
middle of the list renumbers every index after it and Terraform proposes
destroying and recreating unrelated containers.

This is where the "vmid = last octet of the IP" derivation dies. It is a neat
trick that silently constrains the address plan — a host cannot be re-IP'd
without changing its container ID, and two hosts cannot share an octet across
future VLANs. vmid and IP become two explicit, independent fields. Existing
values are carried over unchanged so the import in D9 matches reality.

`inventory/group_vars/lxc_container_proxmox.yml` and `vm_proxmox.yml` are
absorbed here; the shared values (bridge, gateway, CIDR, template, SSH key)
become root-module variables with defaults, not per-host repetition.

### D5: Local state now, git-ignored, with an explicit backup duty

State starts as a local file in `environments/homelab/`. A remote backend needs
somewhere to live, and the obvious homelab candidate (a MinIO LXC) would itself
be provisioned by this Terraform — a bootstrap cycle not worth paying for four
containers and one operator.

Non-negotiables that come with local state:
- `.gitignore` gains `*.tfstate`, `*.tfstate.*`, `.terraform/`,
  `*.auto.tfvars.secret`, `crash*.log`. **State is never committed.** With the
  root passwords deleted per D8 it holds no credential, but it still records the
  complete address and container-ID plan, and Terraform makes no guarantee that
  a future resource attribute will not be sensitive.
- State is included in whatever backs up the control host. Losing it means
  re-importing all four containers by hand, which is recoverable but tedious;
  the import blocks in D9 stay in the repo precisely so that recovery is scripted.
- `.terraform.lock.hcl` **is** committed (it is not state).

Migrating to an S3-compatible backend with locking is D11 item 4, and is a
`terraform init -migrate-state` away — no configuration rewrite.

- *Alternative: HCP Terraform free tier.* Viable and gives locking + remote
  plan for free, but puts the homelab's address plan in a SaaS and adds a
  network dependency to every `plan`. Rejected for now, reconsidered when the
  cloud-practice module in D11 item 7 lands.

### D6: The boundary — Terraform owns the PVE API, Ansible owns the guest

The rule, to be written into `.claude/CLAUDE.md`:

> **Terraform** declares anything the Proxmox API owns: guest existence, vmid,
> hostname, CPU/memory/swap/disk, network interface and IP, boot behaviour,
> template/ISO reference, and the initial root credential + SSH key.
> **Ansible** declares anything inside the guest: users, sudo, SSH hardening,
> packages, runtimes, services, application releases.
> Terraform `provisioner` / `remote-exec` / `local-exec` blocks are **banned** —
> they are one-shot, not idempotent, and invisible to `plan`. Configuration
> after boot is always an Ansible run.

Consequences for existing code:

| Today | After |
|---|---|
| `roles/proxmox_lxc` (create/start/preflight) | deleted → `modules/proxmox_lxc` |
| `roles/proxmox_vm_template`, `roles/proxmox_vm_iso` | deleted → `modules/proxmox_vm` |
| `proxmox_lxc_bootstrap/tasks/ssh.yml` (key via `pct exec`) | Terraform `initialization.user_account.keys` |
| `proxmox_lxc_bootstrap/tasks/account.yml` (root password) | Terraform `initialization.user_account.password` |
| `proxmox_lxc_bootstrap` — create `ansible` user + sudo | **stays Ansible**, moves to `02_BASE_CONFIGURATION/bootstrap.yml`, connects as `root` |
| `roles/proxmox_lxc_tun` (`/dev/net/tun` passthrough) | **stays Ansible** — see below |
| `roles/common` and all `03_SERVICES` | untouched |

The `ansible` user survives in Ansible because the provider seeds only the
container's root account; creating an unprivileged user with a sudo rule is
guest-side state, and it is exactly the kind of thing `02_BASE_CONFIGURATION`
was created for and never used for.

`proxmox_lxc_tun` stays in Ansible because it writes raw lines into
`/etc/pve/lxc/<ctid>.conf`:

```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

The provider models container config as typed attributes and offers no raw
passthrough for arbitrary `lxc.*` keys, so this is a genuine gap, not a
preference. It remains a host-level Ansible role delegated to `proxmox1`, run
after `terraform apply` — which is a real trade-off, because Terraform will not
see that config drift. Documented in Risks.

**Can Ansible be dropped entirely?** No, and it should not be attempted.
Terraform has no model for converging a running OS; doing it with provisioners
gives up idempotency and plan visibility. The only coherent way to shrink
Ansible further is to bake guest state into images with Packer and rebuild
instead of converge — which is a valid third architecture but incompatible with
the checkout-and-build-on-host deploy model this repo is built around. Logged as
D11 item 8, not proposed.

### D7: Ansible reads hosts from Terraform via `cloud.terraform.terraform_provider`

`inventory/hosts` is deleted. Terraform declares Ansible-facing metadata using
the `ansible/ansible` Terraform provider, and Ansible reads it back from state:

```hcl
# terraform/environments/homelab/ansible.tf
resource "ansible_host" "lxc" {
  for_each = var.lxc_hosts
  name     = each.key
  groups   = concat(each.value.groups, ["lxc_container_proxmox", "proxmox_guest"])
  variables = {
    ansible_host = module.lxc[each.key].ipv4_address
    ansible_user = "ansible"
  }
}
```

```yaml
# inventory/terraform.yml
plugin: cloud.terraform.terraform_provider
project_path: ../terraform/environments/homelab
```

`ansible.cfg` already sets `inventory = inventory/`, and a directory inventory
happily mixes a plugin config file with `group_vars/` and `host_vars/`. Because
groups and host names are preserved exactly, **every existing `group_vars/` and
`host_vars/` file keeps working untouched** — `pihole01` is still `pihole01` in
group `pihole` under `lxc_container_proxmox` under `proxmox_guest`. This also
satisfies the standing "no vars in the `hosts` file" rule by construction.

- *Alternative: Terraform renders `inventory/hosts` via `local_file` +
  `templatefile`.* Simpler, no extra providers, greppable output — but it
  commits a generated file, and a stale checkout silently disagrees with
  reality. Kept as the documented fallback if the plugin proves awkward.
- *Alternative: `cloud.terraform.terraform_state` plugin.* It maps *known cloud*
  resource types (AWS/GCP/Azure) to hosts and has no notion of a Proxmox
  container, so it does not fit.
- *Alternative: keep `inventory/hosts` static and hand-sync it.* Rejected — two
  sources of truth for the same four IPs is the problem, not the solution.

### D8: A dedicated least-privilege PVE token, held outside any secret store

Terraform gets its own identity: a PVE user `terraform@pve` with an API token,
granted a **custom role** carrying only the privileges it needs (`VM.Allocate`,
`VM.Config.*`, `VM.PowerMgmt`, `VM.Audit`, `Datastore.AllocateSpace`,
`Datastore.Audit`, `SDN.Use` if VLANs land later) on the relevant path — not
`root@pam` and not `PVEAdmin`. The exact privilege set is derived empirically
during implementation: start from the provider's documented minimum, run
`plan`/`apply`, and add only what fails.

Credentials are supplied as environment variables
(`PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`) sourced from a file **outside
the repo** (e.g. `~/.config/homelab/terraform.env`, mode `0600`). This is a new
secret-handling path: ansible-vault cannot serve it, because Terraform cannot
read vault. The existing `root@pam!ansible` token stays for now and is retired
once nothing in Ansible calls the Proxmox API — which, after this change, is
only `proxmox_lxc_tun` (SSH, not API) and the `pct exec` bootstrap (removed), so
the Ansible token becomes unnecessary and its removal is a task.

Two per-guest secrets could have had the same problem: `lxc_password`
(`partygames01`, `life-dashboard01`) and `vm_ci_password` (`retropie01`),
currently in vaulted `host_vars`. **They are deleted rather than migrated.**

A container root password solves no problem that exists here: `pct enter <ctid>`
from the node gives passwordless root in any container, unconditionally, and
every guest is SSH-key-authenticated. Keeping them would mean managing and
rotating three secrets that are never used, and — because Terraform would have
to pass them to the provider — permanently marking the state file as holding
credentials. Deleting them removes an entire secret class and leaves the state
file holding only vmids and the address plan.

This makes Terraform's total secret requirement exactly **one** value: the PVE
API token. Terraform therefore needs no secret store at all, which is what makes
D12 sequenceable.

### D12: Secrets — HashiCorp Vault in phase B, with one bootstrap credential outside it

Target state (operator decision): a self-hosted HashiCorp Vault LXC becomes the
secret store for the homelab, replacing ansible-vault entirely; `.vault_pass` is
retired. Ansible reads secrets through `community.hashi_vault`.

This **cannot** happen inside this change, and the constraint is structural, not
a matter of scope preference: Vault runs in an LXC, that LXC is provisioned by
Terraform, and Terraform authenticates with the PVE API token. If that token
lived in Vault, the system could not be bootstrapped. Hence:

- **Phase A (this change):** Terraform migration. The PVE API token lives in
  `~/.config/homelab/terraform.env` (mode `0600`, outside the repo), loaded by
  `direnv` — already installed on the control host. Root passwords deleted per
  D8. Ansible keeps ansible-vault untouched.
- **Phase B (follow-up change):** Terraform provisions `vault01`; Vault is
  initialised and unsealed; every remaining Ansible secret — `pihole_password`,
  `life_dashboard_proton_ics_url`, the Tailscale pre-auth key, and both git
  deploy keys — migrates from ansible-vault to Vault; `.vault_pass` and the
  `vault_password_file` line in `ansible.cfg` are removed.

**The PVE API token permanently stays outside Vault.** It is the root of the
trust chain; every secret manager has exactly one credential outside itself.
This is the standard structure, not a concession.

Known ongoing cost, accepted knowingly: after any node reboot Vault is sealed
and every Ansible run that needs a secret fails until it is manually unsealed.
Auto-unseal is the fix, and the option worth taking in phase B is **AWS KMS
auto-unseal** — it removes the manual step and teaches KMS key policies and IAM
scoping, which is squarely the target skill set. Transit auto-unseal needs a
second Vault and is not an option here.

- *Alternative considered: SOPS + age.* Encrypted files committed to git, read
  natively by both Terraform (`sops exec-env`) and Ansible (`community.sops`),
  no runtime service, no unseal ritual, and re-encryptable to cloud KMS later.
  Lower operational burden than Vault for this size of estate. Not chosen —
  Vault's dynamic secrets, leases, and audit log were judged the more valuable
  thing to run for real. Recorded here because it remains the fallback if the
  unseal burden proves impractical.

### D9: Migrate by `import`, never by rebuild

The four LXCs are running services with persistent data. They are adopted using
Terraform 1.5+ `import` blocks committed to `imports.tf`, so the adoption is
reviewable code rather than shell history and is replayable if state is lost:

```hcl
import {
  to = module.lxc["pihole01"].proxmox_virtual_environment_container.this
  id = "ray/225"   # <node>/<vmid> — confirm format against provider docs
}
```

The gate for success is a **completely empty `terraform plan`** after import. If
the plan proposes changes, the *configuration* is wrong (defaults that do not
match reality) and gets corrected until it matches — the container is never
"fixed" to match the config. Any proposed `-/+ destroy and then create` on a
running container is a hard stop.

Order: import and reach empty-plan **before** deleting the Ansible provisioning
roles, so rollback is "revert the commit, the playbooks are still there".

### D10: VM-from-ISO becomes a Terraform VM with an attached CD-ROM

`vm_from_iso.yml` exists to create a VM shell with an ISO attached, to be
installed interactively at the console; `vm_from_template_proxmox.yml` clones a
template with cloud-init. Both collapse into `modules/proxmox_vm`, which takes
either a `clone` source or a `cdrom` file id. The interactive install remains
interactive — Terraform declares the shell, a human installs the OS, Ansible
takes over afterwards.

`retropie01` is currently unprovisioned and commented out of the inventory. It
is **not** imported; it is declared in tfvars only when the box comes back. This
is one of the concrete wins: its absence becomes explicit state rather than a
comment.

### D11: Where Terraform pays off next (roadmap, not this change)

Ordered by value for the Cloud Security Engineer goal:

0. **HashiCorp Vault LXC + migration of all Ansible secrets** — phase B of D12.
   Comes first in time because it is already decided; the items below are
   ordered by value, not by schedule.
1. **PVE users, roles, ACLs, API tokens as code**
   (`proxmox_virtual_environment_user` / `_role` / `_acl` / `_user_token`).
   RBAC as code, reviewable least-privilege, and it makes D8's token
   self-managing. Highest security payoff in the lab.
2. **Proxmox firewall as code** (datacenter/host/guest rules, security groups,
   aliases, IP sets). The lab is a flat `/24` with no segmentation today; this
   turns "which host may talk to which" into a diffable policy — the closest
   local analogue to cloud security groups.
3. **Template and ISO management** (`proxmox_virtual_environment_download_file`).
   Removes the unversioned manual prerequisite currently baked into
   `lxc_template_file: debian-12-standard_12.12-1_amd64.tar.zst`.
4. **Remote state with locking** (MinIO/S3-compatible LXC, or HCP) — see D5.
5. **Policy-as-code gate**: `checkov` / `trivy config` in the pre-commit
   contract, then OPA/Conftest rules expressing homelab-specific policy
   ("no privileged containers", "no guest without a firewall rule").
6. **Tailscale provider** — tailnet ACLs and auth keys as code. This directly
   closes the two manual admin-console steps `add-tailscale-subnet-router` had
   to leave open, and ACL-as-code is squarely on the target career path.
7. **A real cloud module** (AWS or Azure free tier) in the same repo: VPC/IAM
   with least-privilege policies, scanned by the same gate as item 5, deployed
   via OIDC rather than static keys. This is the piece that turns homelab
   Terraform into cloud-security practice, and it is the reason to build the
   habits in items 4–5 first.
8. **Packer images** — only if the deploy model ever moves from
   converge-in-place to rebuild. Not currently compatible with build-on-host.

Backup jobs, storage, pools, HA groups, and SDN/VLANs are all expressible too,
but have little to teach beyond items 1–3.

## Risks / Trade-offs

- **An import mismatch proposes destroying a running container.** → Empty-plan
  gate in D9 is mandatory; `terraform plan` output is read in full before any
  `apply`; take a PVE snapshot/backup of all four LXCs before the first apply.
  Any `destroy` line for an existing container aborts the migration.
- **Losing local state orphans four running containers.** → State is
  git-ignored but backed up with the control host; `imports.tf` stays committed
  so re-adoption is one `terraform apply` away, not archaeology.
- **One credential moves from vault-encrypted git to a plaintext file on disk**:
  the PVE API token (D8/D12). Net secret count still drops, because three LXC
  root passwords are deleted outright. → `0600`, outside the repo, loaded by
  `direnv`; scoped by a custom PVE role so its blast radius is bounded; it is
  the designated bootstrap credential and stays outside Vault by design.
- **Phase B leaves the homelab dependent on a service that seals itself.** After
  a node reboot, Vault is sealed and secret-consuming Ansible runs fail until it
  is manually unsealed. → Accepted deliberately; runbook documented in phase B,
  with AWS KMS auto-unseal as the planned fix. Terraform is unaffected — its
  only credential never lives in Vault.
- **`proxmox_lxc_tun` is invisible to Terraform** (D6). Raw `lxc.mount.entry`
  lines are not provider-modelled, so `terraform plan` will never notice they
  are missing, and a container recreated by Terraform loses TUN until the
  Ansible role runs again. → Documented as a post-apply step in the Terraform
  README and in `docs/terraform-ansible-split.md`; `tailscale01`'s runbook
  states the ordering explicitly.
- **The dynamic inventory adds a hard dependency on readable state.**
  `ansible-inventory` fails if `terraform/` is missing or state is absent —
  including on a fresh clone before `terraform init`. → The rendered-file
  fallback in D7 is documented; the Terraform README states the bootstrap order.
- **Two tools, two mental models, for four containers.** The honest cost is more
  moving parts than a homelab strictly needs. → Accepted deliberately: the
  learning goal is explicit, and the update/destroy gaps in the current setup
  are real, not hypothetical.
- **Terraform is not installed and the operator is new to it.** → The migration
  plan runs `plan` against the live node repeatedly before the first `apply`;
  `plan` is read-only and safe to run as often as needed.
- **`.claude/CLAUDE.md` conventions are Ansible-shaped.** Rules like "FQCN for
  all modules" or "split role tasks per function" have no Terraform meaning. →
  A new Terraform section is added rather than stretching the Ansible rules;
  Terraform follows standard HashiCorp style (`terraform fmt`, snake_case,
  one `main.tf`/`variables.tf`/`outputs.tf` per module).

## Migration Plan

1. **Prepare (no changes to the node).** Install Terraform + `tflint` +
   `checkov`. Create the `terraform@pve` user, custom role, and API token in the
   PVE UI; export credentials from a `0600` file outside the repo. Snapshot or
   back up all four LXCs.
2. **Write the modules and the host catalogue** to describe the *existing*
   world exactly — matching vmids, IPs, sizing, template, bridge.
3. **Import.** `terraform plan` → iterate on the configuration until the plan is
   empty. No `apply` until it is. Ansible provisioning playbooks and roles are
   still present and untouched at this point; rollback is `git revert`.
4. **First real apply.** A trivial, reversible change (e.g. adjust a swap value)
   to prove the update path that Ansible never had.
5. **Cut the handoff.** Add `ansible_host`/`ansible_group` resources and
   `inventory/terraform.yml`; verify `ansible-inventory --graph` matches the old
   static inventory exactly, then delete `inventory/hosts`. Run one `03_SERVICES`
   playbook in `--check` mode to prove the inventory works end to end.
6. **Move the bootstrap.** Create `02_BASE_CONFIGURATION/bootstrap.yml` for the
   `ansible` user + sudo; verify against a throwaway container created by
   Terraform, destroyed afterwards — this also proves the destroy path.
7. **Delete.** Remove `playbooks/01_PROVISIONING/`, `roles/proxmox_lxc`,
   `roles/proxmox_vm_template`, `roles/proxmox_vm_iso`, and the obsolete
   `group_vars`. Retire the `root@pam!ansible` API token.
8. **Document.** README layout section, `.claude/CLAUDE.md` boundary rules and
   pre-commit gates, `docs/terraform-ansible-split.md`, `terraform/README.md`.

**Rollback:** before step 7, rollback is `git revert` plus `rm` of the state
file — the Ansible path is fully intact and the containers are untouched. After
step 7, rollback means restoring the deleted roles from git history; the
containers themselves are never destroyed at any step, so no service is ever at
risk of data loss.

## Open Questions

- **Exact minimum PVE privilege set for the `terraform@pve` role.** Derived
  empirically in step 1; the provider's documented list is the starting point,
  not the answer.
- **Container import ID format** (`<node>/<vmid>` assumed) — confirm against the
  pinned provider version's documentation before writing `imports.tf`.
- ~~Where the LXC root passwords ultimately live.~~ **Decided:** deleted, not
  migrated (D8). `pct enter` makes them redundant.
- **Whether `retropie01` returns.** If it stays gone, `modules/proxmox_vm` has
  no consumer and could be deferred to the change that actually needs a VM.
