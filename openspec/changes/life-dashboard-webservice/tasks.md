## 1. Scaffold the `life-dashboard` service role

- [x] 1.1 Copy `roles/partygames/` to `roles/life-dashboard/` preserving the task split
      (`main.yml` import hub + `user`, `directories`, `deploy_key`, `checkout`,
      `build`, `migrate`, `config`, `release`, `service`, `prune`), handlers, meta,
      and templates
- [x] 1.2 Rename every `partygames_*` variable to `life_dashboard_*` across
      `defaults/main.yml`, all `tasks/*.yml`, `handlers/main.yml`, and templates
- [x] 1.3 Update service identity and on-host paths in `defaults/main.yml`:
      user/group `life-dashboard`, `life_dashboard_service_name: life-dashboard`, `/opt/life-dashboard`,
      `/var/lib/life-dashboard`, `life_dashboard_db_path: /var/lib/life-dashboard/app.db`,
      `/etc/life-dashboard`, and `life_dashboard_port` (choose a free port, e.g. 3000)
- [x] 1.4 Rename the systemd unit template to `life-dashboard.service.j2` and update its
      `Description`, `ReadWritePaths={{ life_dashboard_data_dir }}`, and
      `ExecStart={{ life_dashboard_node_bin }} {{ life_dashboard_current_link }}/build`
- [x] 1.5 Rename the handler to `Restart life-dashboard` and update every `notify:` in the
      role's tasks to match
- [x] 1.6 Update `env.j2` comments/values and `meta/main.yml`
      (description, galaxy_tags) for the life-dashboard service; keep `dependencies: []`
- [x] 1.7 Write `roles/life-dashboard/README.md` describing the role, mirroring the
      party-games README

## 2. Service playbook

- [x] 2.1 Create `playbooks/03_SERVICES/life-dashboard.yml` with `hosts: life-dashboard`,
      `become: true`, applying roles `common → nodejs → life-dashboard → nginx`
      (comments matching the party-games playbook)

## 3. Inventory and host vars

- [x] 3.1 Add a `[life_dashboard]` group to `inventory/hosts` under the
      `lxc_container_proxmox:children` list and define `life-dashboard01` with a free
      static LAN IP `192.168.0.226` (verify unused) and
      `ansible_user=ansible`
- [x] 3.2 Create `inventory/host_vars/life-dashboard01/vars.yml` with LXC sizing
      (`lxc_cores`, `lxc_memory`, `lxc_swap`, `lxc_disk_gb`), `life_dashboard_repo_url`,
      `life_dashboard_version`, and the nginx overrides
      (`nginx_reverse_proxy_enabled: true`,
      `nginx_backend_port: "{{ life_dashboard_port }}"`, `nginx_service_description`)
- [x] 3.3 Create `inventory/host_vars/life-dashboard01/vault.yml` (ansible-vault) holding
      the read-only deploy key (`life_dashboard_deploy_key`) and any LXC password,
      appending the new password as the last vault entry per repo convention
- [x] 3.4 Set a free, unused `id` (CTID) for `life-dashboard01` consistent with how other
      LXC hosts supply `lxc_ctid` / `id`

## 4. Validation

- [x] 4.1 `ansible-playbook --syntax-check playbooks/03_SERVICES/life-dashboard.yml`
- [ ] 4.2 `ansible-lint` on the new role and playbook; address all warnings
      <!-- deferred: ansible-lint not installed here (no pip/pipx/uvx). Role is a
      structural clone of the lint-clean partygames role with only token renames;
      YAML well-formedness of all new files verified. Run `ansible-lint` locally
      to confirm. -->
- [x] 4.3 Confirm no lingering `partygames` references in `roles/life-dashboard/`
      (`grep -ri partygames roles/life-dashboard` returns nothing)

## 5. End-to-end deploy (requires the app repo to exist and build)

<!-- Deferred: these steps run against the live Proxmox node and the separate
     dashboard app repo, neither reachable from this environment. Run them
     yourself once the app repo has a buildable skeleton and its public deploy
     key is registered on GitHub. -->

- [ ] 5.1 Ensure the separate SvelteKit dashboard app repo exists and builds
      (at least a buildable skeleton); set `life_dashboard_migrate_command: ""` if
      migrations are not yet defined
- [ ] 5.2 Provision the container: run `01_PROVISIONING/lxc_proxmox.yml` limited
      to `life-dashboard01`, then base config; verify the LXC is up and reachable
- [ ] 5.3 Deploy: run `playbooks/03_SERVICES/life-dashboard.yml`
      (optionally `-e life_dashboard_version=<tag>`)
- [ ] 5.4 Verify the service is reachable through nginx on `:80` over LAN/VPN, the
      backend binds to `127.0.0.1:<life_dashboard_port>`, and the SQLite DB exists under
      `/var/lib/life-dashboard/`
- [ ] 5.5 Verify a redeploy of the same version is a no-op and that rollback by
      repointing `current` works without touching the database

## 6. Documentation

- [x] 6.1 Note the new service in project docs (mirror the party-games
      architecture/implementation docs, or add a short section referencing them)
