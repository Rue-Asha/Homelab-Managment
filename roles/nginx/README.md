nginx
=====

Install and configure nginx, optionally as a **reverse proxy** in front of a
local application backend.

With defaults, the role just installs nginx and leaves its stock default site —
a bare rollout shows the **"Welcome to nginx!"** page, not a `502`. The reverse
proxy is **opt-in**: a consuming service sets `nginx_reverse_proxy_enabled: true`
and supplies the backend details, at which point nginx becomes the front door on
port 80 and forwards all traffic to a single upstream process on
`nginx_backend_host:nginx_backend_port` — a plain HTTP proxy.

The role is **service-agnostic**: its defaults are generic fallbacks. A concrete
service (e.g. a web app on a host) consumes the role and overrides the backend
port, vhost filename, and `nginx_service_description` in its own
host_vars/group_vars.

Requirements
------------

- Debian (bookworm/trixie) host.
- Run with `gather_facts: true` — the default `nginx_server_name` derives from
  `ansible_facts`.
- A backend listening on `nginx_backend_host:nginx_backend_port` to serve
  content. Until it exists, the proxy returns `502 Bad Gateway` — expected, and
  confirms nginx itself is healthy.

Role Variables
--------------

| Variable | Default | Description |
|---|---|---|
| `nginx_packages` | `[nginx]` | Packages to install. |
| `nginx_service_name` | `nginx` | systemd service name. |
| `nginx_reverse_proxy_enabled` | `false` | Opt-in: deploy + enable the reverse-proxy vhost. Off = stock default site only. |
| `nginx_server_name` | default IPv4 fact | `server_name` for the vhost. |
| `nginx_listen_port` | `80` | Port nginx listens on. |
| `nginx_backend_host` | `127.0.0.1` | Backend host to proxy to. |
| `nginx_backend_port` | `8080` | Backend port (override per service). |
| `nginx_proxy_read_timeout` | `60s` | Upstream read timeout. |
| `nginx_vhost_filename` | `reverse_proxy.conf` | Vhost filename under sites-available/enabled. |
| `nginx_service_description` | `the application backend` | Free-text label for the proxied service; used in generated comments + SETUP_INFO. |
| `nginx_worker_processes` | `auto` | nginx worker count. |
| `nginx_client_max_body_size` | `10m` | Max request body size. |
| `nginx_gzip_enabled` | `true` | Toggle gzip. |
| `nginx_remove_default_site` | `false` | Remove the stock default site (services with a proxy vhost set this true). |
| `nginx_tls_enabled` | `false` | TLS scaffolded off (plain HTTP); services enable as needed. |
| `nginx_install_dir` | `/opt/nginx` | Where SETUP_INFO.txt is written. |

> **Firewall:** this role does **not** manage the host firewall. Opening the
> port nginx listens on (e.g. `80/tcp`) is left to a base/host-level layer.

Dependencies
------------

None.

Example Playbook
----------------

    - name: Install and configure nginx reverse proxy
      hosts: <service_group>      # the host(s) running the service to front
      become: true
      gather_facts: true
      roles:
        - common
        - nginx

License
-------

MIT
