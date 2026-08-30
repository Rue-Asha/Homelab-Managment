---
trigger: always_on
---
# Homelab Ansible

Proxmox-based homelab automation. Standard Ansible best practices (Red Hat CoP) apply — this file lists only project-specific conventions and deviations worth flagging.

---

## Repo layout

Two peer layers, one repo. `terraform/` provisions the guests, `ansible/` configures them — see the boundary section below.

```
ansible/                    # configuration layer
  ansible.cfg
  inventory/
  playbooks/
  roles/
  collections/
terraform/                  # provisioning layer
  environments/homelab/     # the single root module — one node, one state
  modules/
docs/  openspec/  .envrc
```

`.envrc` exports `ANSIBLE_CONFIG=$PWD/ansible/ansible.cfg`, so **every command runs from the repo root**. Relative paths inside `ansible.cfg` resolve against the config file's own directory, so they needed no rewriting when the tree moved. Do not `cd ansible/` — the Terraform-backed inventory plugin resolves `project_path` relative to the working directory.

Playbooks are grouped by purpose, with a numeric prefix encoding the order the categories are applied to a fresh host (00 → 03).

```
ansible/playbooks/
  00_OPERATIONAL/         # ad-hoc / day-2 ops: backups, snapshots, maintenance, troubleshooting
  01_PROVISIONING/        # SUPERSEDED by terraform/ — removed once the rebuild lands
  02_BASE_CONFIGURATION/  # post-provision host setup: users, SSH, packages, OS hardening
  03_SERVICES/            # application install & config: pihole, retropie, etc.
```

- `ansible/inventory/` — structured directory inventory (no vars in `hosts` file). Introduce a `<datacenter>/<environment>/` layer only when a second site or environment is added.
  - `ansible/inventory/group_vars/`, `ansible/inventory/host_vars/` — co-located with the inventory; split into logical YAML files per group/host
- `ansible/roles/` — standard Galaxy structure; variables prefixed with role name (`foo_packages`, not `packages`)

**Naming:**
- **Top-level playbook category directories** use `NN_UPPER_SNAKE_CASE` (e.g. `01_PROVISIONING/`). The `NN_` prefix encodes apply order so the categories sort visually in the right sequence.
- **Filenames inside each category** stay descriptive snake_case with no further numbering — e.g. `ansible/playbooks/01_PROVISIONING/lxc_proxmox.yml`, `ansible/playbooks/03_SERVICES/pihole.yml`. The directory provides the ordering; the filename describes the action.

---

## Terraform / Ansible boundary

> **Migration in progress.** The `terraform/` tree exists and is additive;
> `ansible/playbooks/01_PROVISIONING/` is still the active path until the import gate
> passes. The rules below describe the target and already apply to new work.

**Terraform** declares anything the Proxmox API owns: guest existence, vmid,
hostname, CPU/memory/swap/disk, network interface and IP, boot behaviour,
template/ISO reference, and the SSH key seeded at creation.

**Ansible** declares anything inside the guest: users, sudo, SSH hardening,
packages, runtimes, services, application releases.

- **Never add guest lifecycle to Ansible.** No role or playbook may call a
  Proxmox API module to create, resize, or delete a guest.
- **Terraform `provisioner` / `remote-exec` / `local-exec` are banned** —
  one-shot, not idempotent, invisible to `plan`. Post-boot configuration is
  always an Ansible run.
- **`for_each` over a hostname-keyed map, never `count`** — `count` renumbers on
  deletion and proposes recreating unrelated containers.
- **vmid and IP are independent declarations** — deriving one from the other
  welds the address plan to container IDs.
- **No guest root passwords.** `pct enter <ctid>` is the console fallback.
- Terraform follows HashiCorp style (`terraform fmt`, snake_case,
  `main.tf`/`variables.tf`/`outputs.tf`/`versions.tf` per module) — the Ansible
  rules below do not apply to it.

Known gap: `ansible/roles/proxmox_lxc_tun` stays in Ansible because the provider has no
escape hatch for raw `lxc.*` config keys. Full detail, including the run order
and the secret model, in `docs/terraform-ansible-split.md`.

---

## Service delivery model

Application services are deployed **app-per-LXC**, not via container images. Each service runs in its own Proxmox LXC; Ansible converges the box into the service (no Docker/OCI images, no registry, no CI required). `systemd` supervises the process (restart, boot-start, journald) — it is the runtime supervisor in place of a container runtime.

- **Two repos:** this repo configures the host; the application lives in its **own repo**, referenced from the service's host/group vars by URL + a **pinned version** (git tag/commit, the equivalent of an image tag). A deploy is a playbook run (Ansible checks out + builds), not host-side polling.
- **Build on host:** the service role checks out the pinned ref and builds on the LXC (e.g. `npm ci && npm run build`); no prebuilt artifact. Graduate to a shipped tarball only if a host must stay toolchain-free or builds need CI — only the checkout/build steps change.
- **Release layout:** build into `/opt/<svc>/releases/<ts>`, flip a `current` symlink, restart — atomic deploy + instant rollback. Persistent data (e.g. a SQLite file) lives outside releases (e.g. `/var/lib/<svc>/`) and is never touched by a redeploy.
- **Role split:** reusable machine-config concerns are their own roles (runtime e.g. `nodejs`, `nginx`, base/hardening in `common`); a service gets its **own role** only when it has config/deps beyond a declarative `03_SERVICES` playbook. **Host-level concerns (firewall, runtime install) must not live in a service/app role.**
- **nginx** is a host-level reverse proxy in front of the service (`:80` → `127.0.0.1:<port>`), enabled via the service host's vars.

Worked example: `docs/party-games-webservice-architecture.md`.

---

## Git conventions

**Commits** — Conventional Commits:
- Format: `type(scope): description`
- Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`
- Example: `feat(webserver): add SSL config support`

**Branches** — cut from `main` after pulling latest:
- `feat/<name>` for features
- `bugfix/<name>` for fixes

**Vault** — append new passwords as the *last entry*; never commit unencrypted secrets.

---

## Project-specific Ansible rules

These are choices the team has made that differ from defaults or are worth keeping explicit:

- **Split role tasks into per-function files** — `tasks/main.yml` is an import-only hub (`ansible.builtin.import_tasks`) that pulls in one file per logical step (e.g. `install.yml`, `configure.yml`, `service.yml`, `repository.yml`). Do not pile tasks directly into `main.yml`.
- **Prefer distro-specific package modules** (`ansible.builtin.apt`, `ansible.builtin.dnf`) over the generic `package` module — gives finer control over distro options
- **Pass package lists as a single list** to the module, not via `loop` with `{{ item }}`
- **No `meta: end_play`** — aborts the whole play. Use `meta: end_host` only if absolutely required
- **Avoid `lineinfile`** — prefer templates or dedicated modules
- **`set_fact` may not override role defaults/vars** — use a different variable name instead
- **No Jinja2 `eq`/`equalto`/`==` tests** — use `match`/`search`/`regex` for EL7 compatibility

---

## Style quick-reference

| Rule | Example |
|---|---|
| Snake case for vars, tasks, files | `foo_service_name` (playbook category dirs are the exception — see Repo layout) |
| Role vars prefixed with role name | `nginx_port`, not `port` |
| Booleans lowercase | `true` / `false` |
| Bracket notation for var access | `{{ item['key'] }}` |
| `\| bool` filter with bare vars in `when` | `when: foo \| bool` |
| Fold long lines with `>-` (never `>`) | avoids trailing newline |
| Imperative task names | "Ensure service is running" |
| FQCN for all modules | `ansible.builtin.service` |
| `.yml` extension, not `.yaml` | — |
| Handlers over `when: result is changed` | — |

---

## Before committing

Ansible:

- `ansible-playbook --syntax-check <playbook>.yml`
- `ansible-lint`
- Address all lint warnings

Terraform (anything under `terraform/`):

- `terraform fmt -check -recursive`
- `terraform validate`
- `tflint`
- `checkov -d .` (or `trivy config .`) — address findings or record a reason inline

---

## References

- [Red Hat CoP — Automation Good Practices](https://redhat-cop.github.io/automation-good-practices/) — full style guide
- [Ansible Lint Rules](https://ansible-lint.readthedocs.io/)
