nodejs
======

Install the Node.js runtime from the
[NodeSource](https://github.com/nodesource/distributions) apt repository, pinned
to a chosen major version. Provides `node` and `npm` system-wide for services
that run a Node process (e.g. the `partygames` role).

Requirements
------------

- Debian (bookworm/trixie) host.
- Network access to `deb.nodesource.com`.
- Ansible ≥ 2.15 (uses `deb822_repository`). The role installs `python3-debian`
  on the host, which that module requires.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `nodejs_version` | `"22"` | NodeSource major version line (e.g. `22` → `node_22.x`). Use an LTS ≥ 22 for built-in `node:sqlite`. |
| `nodejs_packages` | `[nodejs]` | Packages to install from the repo (`nodejs` bundles `npm`). |

Notes:

- Packages install with `state: present`. Changing `nodejs_version` on a host
  that already has Node updates the apt source but does **not** force a
  major-version upgrade — handle that deliberately if needed.
- Native addons (e.g. `better-sqlite3` built from source) need a C toolchain
  (`build-essential`, `python3`). This role installs only the runtime; a
  consuming role should add build deps if required. Using `node:sqlite` avoids
  the need entirely.

Dependencies
------------

None.

Example Playbook
----------------

    - name: Install the Node.js runtime
      hosts: <service_group>
      become: true
      roles:
        - nodejs

License
-------

MIT
