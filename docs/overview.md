# Repository Overview

A unified Ansible infrastructure repo that installs/configures the Datadog Agent v7 across mail servers, Proxmox nodes, and a jumpserver. Core principle: **service auto-detection** — one role works across all host types.

---

## Roles

### `datadog_server` (Primary)

The main role used by `site.yml` and `playbook.yml`. 17 task files:

| Task File | Purpose |
|---|---|
| `main.yml` | Orchestrates: validate → detect → install → configure → validate |
| `detect.yml` | Probes for Docker, Proxmox, Mailcow, Postal, Postfix, Redis, Memcached; sets `has_*` facts + `server_role` + `mail_type` |
| `install.yml` | Checks current agent version, upgrades if below `dd_agent_min_version` (7.76.3) via Datadog install script |
| `backup_config.yml` | Archives `/etc/datadog-agent/` to `/var/backups/datadog/` before every configure (keeps last 5) |
| `reset_config.yml` | Wipes all user-managed `.yaml` from `conf.d/`, removes `datadog.yaml` + `system-probe.yaml`, stops agent |
| `configure_core.yml` | Deploys `datadog.yaml` + `system-probe.yaml` templates |
| `configure_system_checks.yml` | Ensures `.default` files exist for cpu, memory, load, network, io, uptime, file_handle, ntp |
| `configure_docker.yml` | Docker integration (when `has_docker`) |
| `configure_mailcow.yml` | HTTP + TCP checks for Mailcow (when `has_mailcow`) |
| `configure_postal.yml` | HTTP + TCP checks + log collection for Postal (when `has_postal`) |
| `configure_postfix.yml` | Postfix queue monitoring + sudoers grant for postqueue (when `has_postfix`) |
| `configure_redis.yml` | Redis integration, removes `auto_conf.yaml` to prevent Autodiscovery conflict (when `has_redis`) |
| `configure_memcached.yml` | Memcached integration (when `has_memcached`) |
| `configure_proxmox.yml` | Proxmox API check + journald log collection (when `has_proxmox`) |
| `configure_process.yml` | Named-process checks for Mailcow or Postal |
| `configure_disk.yml` | Disk monitoring with filesystem exclusions |
| `validate_agent.yml` | Waits for agent active status, shows status summary |

**Key defaults:**
- `dd_agent_min_version: "7.76.3"`, `dd_force_update: false`
- APM/NPM/process disabled (`false`), logs enabled (`true`)
- `dd_min_collection_interval: 30` (all checks poll every 30s)

**Templates (18):** `datadog.yaml.j2`, `system-probe.yaml.j2`, per-service configs for disk, docker, mailcow (HTTP+TCP), postal (HTTP+TCP+logs), postfix (conf+TCP), redis, memcached, proxmox, journald, process (mailcow+postal).

---

### `disk_cleanup`

Prevents disk exhaustion alongside the Datadog role in `playbook.yml`.

| Task File | Purpose |
|---|---|
| `docker_logs.yml` | Deploys `daemon.json` with log rotation (50MB max, 3 files); truncates existing large logs |
| `journal.yml` | Sets journald limits (500MB max, 1 month retention); vacuums immediately |
| `purge_script.yml` | Deploys `/usr/local/bin/disk-purge` bash script + hourly cron; cleans Docker logs, journal, apt cache, old /tmp files |

---

### `mailcow_recreate`

Force recreates all Mailcow Docker containers (`docker compose up -d --force-recreate`), 2 retries, 10s delay. Runs 4 hosts at a time via `serial: 4`.

### `mailcow_expunge`

Runs `doveadm expunge -A mailbox % before 2w` inside the dovecot container — removes messages older than 2 weeks. 4 hosts at a time.

---

## Playbooks

| Playbook | Targets | Roles |
|---|---|---|
| `site.yml` | mail + proxmox + jumpserver | `datadog_server` |
| `playbook.yml` | mail VMs | `datadog_server` + `disk_cleanup` |
| `playbook_mailcow_recreate.yml` | mailin_inbound + mail_servers | `mailcow_recreate` |
| `playbook_mailcow_expunge.yml` | mailin_inbound | `mailcow_expunge` |

---

## Inventory

Groups in `inventory/hosts.ini`:
- `mailin_inbound` — Many inbound VMs (OVH Virginia), `ubuntu` user, `~/.ssh/mailin.pem`
- `mail_servers` — General mail hosts, `root` user, `~/.ssh/id_ed25519`
- `proxmox_nodes` — 7 Proxmox nodes (node-ca-*, node-hi-*), `root` user
- `jumpservers` — `127.0.0.1`, local
- `node_hi_10_0001_vms_in` — 22 VMs, `~/.ssh/mo.pem`
- `infrastructure`, `utilities`, `warmup` — misc servers

`host_vars/` — Per-node Proxmox API credentials (`vars.yml` + `vault.yml`) for all 10 Proxmox nodes. Provisioned via `run_proxmox_init.sh`.

---

## Docs

| File | Contents |
|---|---|
| `docs/run_datadog.md` | Full CLI usage, all available tags, troubleshooting commands |
| `docs/mailcow_recreate.md` | Recreate usage + retry logic |
| `docs/mailcow_expunge.md` | Expunge usage + serial execution explanation |

---

## Key Design Patterns

1. **Auto-detection** — `detect.yml` sets `has_*` boolean facts; all configure tasks are gated on them
2. **Full template ownership** — `datadog.yaml` + `system-probe.yaml` are fully overwritten each run (no stale keys)
3. **Backup before every configure** — timestamped `.tar.gz` to `/var/backups/datadog/`, last 5 kept
4. **`check_mode: false` on read-only commands** — ensures dry-run doesn't break version checks
5. **Tag-based workflow** — granular control: `detect`, `install`, `configure`, `core`, `docker`, `mailcow`, `postal`, `postfix`, `redis`, `memcached`, `proxmox`, `disk`, `validate`, `cleanup`
