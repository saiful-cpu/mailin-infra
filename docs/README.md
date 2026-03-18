# Datadog Agent — Ansible Deployment

Unified Ansible role that installs and configures the Datadog Agent across all server types.
Auto-detects running services on each host and deploys only the relevant integrations.

## Supported host types

| Host type | Detected via | Integrations deployed |
|---|---|---|
| **Proxmox VE** | `/etc/pve` + `pveversion` | Proxmox API check (VM metrics), journald logs, disk |
| **Mailcow** | `mailcow.conf` + `docker-compose.yml` | HTTP check, TCP ports, Docker container logs, disk |
| **Postal** | `/opt/postal` or `postal` service | HTTP check, TCP ports, log collection, disk |
| **Postfix** | `systemctl is-active postfix` | Queue metrics, log collection, TCP ports, disk |
| **Docker** | `docker info` | Container metrics, image stats, events |
| **Redis** | `redis-server` + active service | Metrics, slow-log, log collection |
| **Memcached** | `memcached` + active service | Metrics |
| **All hosts** | — | Disk, APM, process monitoring, Network Performance Monitoring |

## Requirements

- Ansible ≥ 2.12
- Target: Debian 11/12, Ubuntu 20.04/22.04/24.04, AlmaLinux/RHEL 8/9
- `become: true` (root access via SSH key)
- Outbound HTTPS to `install.datadoghq.com` and your Datadog site

## Quick start

```bash
# 1. Fill in vault credentials
ansible-vault edit vars/vault.yml           # set vault_dd_api_key
ansible-vault edit vars/vault_proxmox.yml   # set Redis password (Proxmox token goes in host_vars)

# 2. Add hosts to inventory
vi inventory/hosts.ini

# 3. Fill in per-node Proxmox token secrets
ansible-vault edit host_vars/pve01/vault.yml
ansible-vault edit host_vars/pve02/vault.yml

# 4. Encrypt all vault files
ansible-vault encrypt vars/vault.yml vars/vault_proxmox.yml
ansible-vault encrypt host_vars/pve01/vault.yml host_vars/pve02/vault.yml

# 5. Run on all servers
ansible-playbook site.yml --ask-vault-pass

# 6. Limit to one host for testing
ansible-playbook site.yml -l test-mailcow --ask-vault-pass
```

## Inventory

Edit `inventory/hosts.ini`:

```ini
[mail_servers]
test-mailcow  ansible_host=1.2.3.4
postal-01     ansible_host=1.2.3.5

[proxmox_nodes]
pve01  ansible_host=10.0.0.10
pve02  ansible_host=10.0.0.11

[mail_servers:vars]
ansible_user=root
ansible_ssh_private_key_file=~/.ssh/id_ed25519

[proxmox_nodes:vars]
ansible_user=root
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

## Vault secrets

### `vars/vault.yml` — Datadog API key
```yaml
vault_dd_api_key: "your_datadog_api_key"
```

### `vars/vault_proxmox.yml` — shared secrets
```yaml
# For clustered Proxmox only (single shared token).
# Leave empty if nodes are standalone — use host_vars instead.
vault_proxmox_api_user: ""
vault_proxmox_api_token_name: ""
vault_proxmox_api_token_secret: ""

# Redis password — empty string if no auth configured
vault_redis_password: ""
```

### `host_vars/<node>/vault.yml` — per-node Proxmox token (standalone nodes)

Each unclustered Proxmox node has its own API token secret:

```yaml
# host_vars/pve01/vault.yml
vault_proxmox_api_token_secret: "token-secret-for-pve01"
```

```yaml
# host_vars/pve02/vault.yml
vault_proxmox_api_token_secret: "token-secret-for-pve02"
```

### `host_vars/<node>/vars.yml` — per-node Proxmox config (non-sensitive)

```yaml
# host_vars/pve01/vars.yml
proxmox_api_user: "datadog@pam"
proxmox_api_token_name: "datadog"
```

Encrypt all vault files with the same password:
```bash
ansible-vault encrypt vars/vault.yml vars/vault_proxmox.yml
ansible-vault encrypt host_vars/pve01/vault.yml host_vars/pve02/vault.yml
```

## Proxmox API token setup

Run on **each standalone node** (tokens are not shared between unclustered nodes):

```bash
# Create user and token (secret shown ONCE — copy it immediately)
pveum user add datadog@pam
pveum user token add datadog@pam datadog --privsep 0

# Grant read-only access
pveum aclmod / -token 'datadog@pam!datadog' -role PVEAuditor -propagate 1
```

Or via the web UI:
1. Datacenter → Permissions → Users → Add: `datadog@pam`
2. Datacenter → Permissions → API Tokens → Add: user `datadog@pam`, token ID `datadog`, uncheck "Privilege Separation"
3. Datacenter → Permissions → Add → API Token Permission: path `/`, role `PVEAuditor`, propagate yes

For **clustered nodes**: run the commands once on the primary node — tokens replicate automatically. Use `vars/vault_proxmox.yml` for the shared secret instead of `host_vars`.

## Proxmox token — clustered vs standalone

| Setup | Where to store secret | Variable precedence |
|---|---|---|
| **Clustered** (pvecm) | `vars/vault_proxmox.yml` | Group vault → all nodes |
| **Standalone** | `host_vars/<node>/vault.yml` | Host vault → overrides group |

Variable resolution order (highest wins):

```
host_vars/<hostname>/vault.yml    ← per-node token secret
host_vars/<hostname>/vars.yml     ← per-node token user/name
vars/vault_proxmox.yml            ← group fallback (clustered)
roles/datadog_server/defaults/    ← role defaults
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `dd_api_key` | **required** | Datadog API key |
| `dd_site` | `datadoghq.com` | Datadog intake site |
| `dd_env` | `prod` | Environment tag |
| `dd_apm_enabled` | `true` | Enable APM tracing |
| `dd_process_enabled` | `true` | Enable process monitoring |
| `dd_npm_enabled` | `true` | Enable Network Performance Monitoring |
| `dd_logs_enabled` | `true` | Enable log collection |
| `dd_agent_min_version` | `7.76.3` | Minimum agent version — auto-upgrades if installed version is below this. Set `""` to disable |
| `dd_force_update` | `false` | Force reinstall regardless of current version |
| `proxmox_host` | `localhost` | Proxmox API hostname |
| `proxmox_port` | `8006` | Proxmox API port |
| `proxmox_ssl_verify` | `false` | Verify Proxmox TLS cert |
| `proxmox_api_user` | `datadog@pam` | Proxmox API token user |
| `proxmox_api_token_name` | `datadog` | Proxmox API token ID |
| `proxmox_api_token_secret` | `vault_proxmox_api_token_secret` | Proxmox token secret |
| `redis_host` | `localhost` | Redis host |
| `redis_port` | `6379` | Redis port |
| `memcached_host` | `localhost` | Memcached host |
| `memcached_port` | `11211` | Memcached port |

## Playbook tags

```bash
# Detection only — shows what was found, no changes made
ansible-playbook site.yml --ask-vault-pass --tags detect

# Install / upgrade agent only (auto-upgrades if below dd_agent_min_version)
ansible-playbook site.yml --ask-vault-pass --tags install

# Pin a specific minimum version
ansible-playbook site.yml --ask-vault-pass --tags install -e "dd_agent_min_version=7.76.3"

# Force reinstall regardless of current version
ansible-playbook site.yml --ask-vault-pass --tags install -e "dd_force_update=true"

# Re-deploy all integration configs
ansible-playbook site.yml --ask-vault-pass --tags configure

# Specific integration only
ansible-playbook site.yml --ask-vault-pass --tags redis
ansible-playbook site.yml --ask-vault-pass --tags proxmox
ansible-playbook site.yml --ask-vault-pass --tags mailcow
ansible-playbook site.yml --ask-vault-pass --tags postal

# Restart agent and show status
ansible-playbook site.yml --ask-vault-pass --tags validate
```

## What each enabled feature adds to `datadog.yaml`

| Feature | Setting |
|---|---|
| **Logs** | `logs_enabled: true` |
| **APM** | `apm_config: { enabled: true }` |
| **Process** | `process_config: { process_collection: { enabled: true } }` |
| **NPM** | `network_config: { enabled: true }` + `system-probe.yaml` |

## Directory layout

```
ansible/datadog/
├── site.yml                         ← main entry point (all server types)
├── playbook.yml                     ← mail servers only (legacy)
├── playbook_proxmox.yml             ← Proxmox only (legacy)
├── ansible.cfg
├── inventory/
│   └── hosts.ini
├── vars/
│   ├── vault.yml                    ← vault_dd_api_key (encrypted)
│   └── vault_proxmox.yml            ← Redis password + clustered Proxmox token (encrypted)
├── host_vars/
│   ├── pve01/
│   │   ├── vars.yml                 ← proxmox_api_user, proxmox_api_token_name
│   │   └── vault.yml                ← vault_proxmox_api_token_secret (encrypted)
│   └── pve02/
│       ├── vars.yml
│       └── vault.yml                ← vault_proxmox_api_token_secret (encrypted)
├── docs/
│   └── README.md
└── roles/
    ├── datadog_server/              ← unified role (use this)
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── meta/main.yml
    │   ├── tasks/
    │   │   ├── main.yml
    │   │   ├── detect.yml
    │   │   ├── install.yml
    │   │   ├── configure_core.yml
    │   │   ├── configure_docker.yml
    │   │   ├── configure_mailcow.yml
    │   │   ├── configure_postal.yml
    │   │   ├── configure_postfix.yml
    │   │   ├── configure_redis.yml
    │   │   ├── configure_memcached.yml
    │   │   ├── configure_proxmox.yml
    │   │   ├── configure_disk.yml
    │   │   └── validate_agent.yml
    │   └── templates/
    │       ├── disk_conf.yaml.j2
    │       ├── docker_conf.yaml.j2
    │       ├── journald_conf.yaml.j2
    │       ├── mailcow_http_check.yaml.j2
    │       ├── mailcow_tcp_check.yaml.j2
    │       ├── mailcow_logs.yaml.j2
    │       ├── memcached_conf.yaml.j2
    │       ├── postal_http_check.yaml.j2
    │       ├── postal_tcp_check.yaml.j2
    │       ├── postal_logs.yaml.j2
    │       ├── postfix_conf.yaml.j2
    │       ├── postfix_tcp_check.yaml.j2
    │       ├── proxmox_conf.yaml.j2
    │       └── redis_conf.yaml.j2
    ├── datadog_mail/                ← mail-only role (legacy)
    └── datadog_proxmox/             ← Proxmox-only role (legacy)
```

## Tag scheme

All metrics and logs use a consistent tag set:

| Tag | Example | Description |
|---|---|---|
| `env` | `env:prod` | Environment |
| `role` | `role:mailcow` | Primary server role (auto-detected) |
| `host` | `host:test-mailcow` | Hostname |
| `service` | `service:redis` | Specific service |
| `pve_node` | `pve_node:pve01` | Proxmox node name |
| `pve_cluster` | `pve_cluster:homelab` | Proxmox cluster name (`standalone` if not clustered) |

## Detected role values

| Value | Condition |
|---|---|
| `proxmox` | `/etc/pve` exists and `pveversion` succeeds |
| `mailcow` | `mailcow.conf` + `docker-compose.yml` found |
| `postal` | `/opt/postal` exists or `postal` service active |
| `postfix` | `postfix` active, not shadowed by Mailcow or Postal |
| `generic` | None of the above |
