common
======

Base configuration applied to **every** managed host as the `02_BASE_CONFIGURATION`
layer. Two concerns:

1. **Base packages** — host-level tooling every box needs, including the
   prerequisites for later roles (`acl` for unprivileged `become`, `git` for
   build-on-host service deploys).
2. **SSH hardening** — disable root login and password authentication
   (key-based auth only).

This role is the first thing applied to a freshly provisioned host, before any
runtime or service role.

Requirements
------------

- Debian (bookworm/trixie).
- SSH key access already in place for the connecting user — password auth is
  turned off, so locking yourself out is possible if no key is authorised.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `common_packages` | `[acl, git]` | Base packages installed on every host. `acl` lets Ansible set permissions on its temp files when becoming an unprivileged user on POSIX-ACL filesystems; `git` is the SCM client for build-on-host service deploys. Extend per environment as needed. |

Dependencies
------------

None.

Example Playbook
----------------

    - name: Base-configure a host
      hosts: all
      become: true
      roles:
        - common

License
-------

MIT
