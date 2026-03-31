# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an Ansible repository that installs and configures the Datadog Agent (v7) across a fleet of mail servers, Proxmox VE nodes, and a jumpserver. The central design principle is **service auto-detection**: the `detect.yml` task probes each host at runtime and sets boolean facts (`has_docker`, `has_mailcow`, `has_postal`, `has_postfix`, `has_redis`, `has_memcached`, `has_proxmox`). Subsequent configure tasks are gated on those facts, so a single role works across heterogeneous hosts without per-host task lists.

## Running Playbooks

Use the wrapper scripts instead of calling `ansible-playbook` directly — they handle vault prompting, terminal colors, and timestamped logs automatically. See `docs/run_datadog.md` for full details.

### Datadog agent (`run_datadog.sh`)

Mail VMs (default):
```bash
./run_datadog.sh
./run_datadog.sh -l inbound-745-01a
./run_datadog.sh -l mailin_inbound --tags configure
./run_datadog.sh --check
```

All host types (mail + Proxmox + jumpserver):
```bash
./run_datadog.sh --site
./run_datadog.sh --site -l proxmox_nodes
```

Force agent reinstall:
```bash
./run_datadog.sh -e "dd_force_update=true" --tags install,configure
```

Wipe config and reprovision a host:
```bash
./run_datadog.sh -l <host> --tags reset,configure
```

Available tags: `detect`, `install`, `backup`, `reset`, `configure`, `core`, `docker`, `mailcow`, `postal`, `postfix`, `redis`, `memcached`, `proxmox`, `process`, `disk`, `validate`, `cleanup`

### Mailcow container recreate (`run_mailcow_recreate.sh`)

Targets `mailin_inbound` and `mail_servers`. Runs `docker compose up -d --force-recreate` one host at a time. See `docs/mailcow_recreate.md`.

```bash
./run_mailcow_recreate.sh
./run_mailcow_recreate.sh -l inbound-850-01r
./run_mailcow_recreate.sh --limit @logs/retry/playbook_mailcow_recreate.retry
```

### Mailcow Dovecot expunge (`run_mailcow_expunge.sh`)

Targets `mailin_inbound`. Expunges messages older than 2 weeks from all mailboxes. Runs 5 hosts at a time. See `docs/mailcow_expunge.md`.

```bash
./run_mailcow_expunge.sh
./run_mailcow_expunge.sh -l inbound-694-01a
./run_mailcow_expunge.sh --limit @logs/retry/playbook_mailcow_expunge.retry
```

## Architecture

### Roles

- **`datadog_server`** — primary role used by `site.yml` for all host types. Runs detection, installs the agent, then conditionally applies integration configs based on detected services.
- **`datadog_proxmox`** — older dedicated role for Proxmox nodes, used by `playbook_proxmox.yml`. Superseded by `datadog_server` in `site.yml`.
- **`datadog_mail`** — older dedicated role for mail VMs. Superseded by `datadog_server`.
- **`disk_cleanup`** — configures Docker log rotation, systemd journal limits, and a cron-based purge script. Applied alongside `datadog_server` in `playbook.yml`.
- **`mailcow_recreate`** — force recreates all Mailcow Docker containers via `docker compose up -d --force-recreate`. Retries up to 2 times on transient Docker errors. Used by `playbook_mailcow_recreate.yml`. See `docs/mailcow_recreate.md`.
- **`mailcow_expunge`** — expunges Dovecot messages older than 2 weeks from all mailboxes via `doveadm expunge -A mailbox % before 2w`. Used by `playbook_mailcow_expunge.yml`. See `docs/mailcow_expunge.md`.

### Detection Flow (`roles/datadog_server/tasks/detect.yml`)

Detection resets state variables first (prevents stale facts on multi-play runs), then probes: Docker → Proxmox → Mailcow → Postal → Postfix → Redis → Memcached. It also derives two Datadog host tags:
- `server_role`: `proxmox | mailcow | postal | postfix | generic`
- `mail_type`: `inbound | outbound | none | unknown` (derived from hostname patterns or detected services)

Postfix is only flagged as standalone if it is not shadowed by Mailcow or Postal. Mailcow Redis credentials (REDISPASS, REDIS_PORT) are extracted directly from `mailcow.conf` during detection.

### Config Ownership (Template-Based)

`datadog.yaml` and `system-probe.yaml` are **fully owned by Ansible templates** — every run overwrites the entire file, so there are no stale keys from manual edits or old installs. Integration configs in `conf.d/` are also fully managed: each is deployed when detected, removed when not.

- `roles/datadog_server/templates/datadog.yaml.j2` — renders the complete `datadog.yaml`
- `roles/datadog_server/templates/system-probe.yaml.j2` — renders the complete `system-probe.yaml` (empty when NPM disabled)
- `roles/datadog_server/tasks/configure_system_checks.yml` — ensures built-in check `.default` files exist for `cpu`, `memory`, `load`, `network`, `io`, `uptime`, `file_handle`, `ntp` (agent v7.77+ may not create these on install)

### Backup and Reset

- **Backup** (`backup_config.yml`): runs automatically before every `configure`. Saves `/etc/datadog-agent/` as a timestamped `.tar.gz` to `/var/backups/datadog/` (keeps last 5).
- **Reset** (`reset_config.yml`): wipes all user-managed `.yaml` files from `conf.d/` (preserves `.default` files), removes `datadog.yaml` and `system-probe.yaml`, stops the agent. Always run with `--tags reset,configure` so configure immediately rebuilds.

### Secrets / Vault

- `vars/vault.yml` — contains `vault_dd_api_key` (Ansible Vault encrypted, AES256)
- `vars/vault_proxmox.yml` — contains `vault_proxmox_api_user`, `vault_proxmox_api_token_name`, `vault_proxmox_api_token_secret`
- `host_vars/<hostname>/vault.yml` — per-node overrides for Proxmox API credentials
- `host_vars/<hostname>/vars.yml` — per-node non-secret vars (e.g. `proxmox_api_user`, `proxmox_api_token_name`)

The DD API key falls back to the `DD_API_KEY` environment variable if vault is unavailable.

### Inventory Groups (`inventory/hosts.ini`)

| Group | Description |
|---|---|
| `mail_servers` | Mailcow/general mail hosts |
| `mailin_inbound` | Inbound mail VMs (OVH Virginia) — SSH via `~/.ssh/mailin.pem`, user `ubuntu` |
| `proxmox_nodes` | Proxmox VE nodes — SSH via `~/.ssh/id_ed25519`, user `root` |
| `jumpservers` | Local jumpserver (`127.0.0.1`) |

`inventory/outbound.ini` exists but is not yet referenced by `ansible.cfg`.

### Key Defaults (`roles/datadog_server/defaults/main.yml`)

- `dd_agent_min_version: "7.76.3"` — agent is upgraded if installed version is below this
- `dd_force_update: false` — set to `true` to force reinstall
- `dd_apm_enabled: false`, `dd_npm_enabled: false` — disabled to reduce CPU usage
- `dd_process_enabled: false` — full process list collection disabled (expensive); container-level collection stays enabled via `container_collection.enabled: true`
- `dd_logs_enabled: true`, `dd_log_level: warn`
- `dd_min_collection_interval: 30` — all metric checks poll every 30s (default is 15s)

### Host Tags (set in `datadog.yaml` template)

Every host gets: `env`, `host`, `hostname`, `role` (mailserver/proxmox/generic), `mail_platform` (mailcow/postal/postfix/proxmox/generic), `mail_type` (inbound/outbound), `ip:<public_ip>`. Mailcow hosts additionally get `mailcow_domain:<MAILCOW_HOSTNAME>`. Private IPs (10.x, 172.x, 192.168.x) are excluded from IP tags.

### Integration Configs (`conf.d/`)

| Directory | Deployed when | Notes |
|---|---|---|
| `cpu.d`, `memory.d`, `load.d`, `network.d`, `io.d`, `uptime.d`, `file_handle.d`, `ntp.d` | always | `.default` files — created by `configure_system_checks.yml` if missing |
| `disk.d` | always | `file_system_exclude` list filters overlay/tmpfs/etc. |
| `docker.d` | `has_docker` | includes `container_labels_as_tags` for compose service/project |
| `redisdb.d` | `has_redis` | auto_conf.yaml removed to prevent Autodiscovery conflict |
| `http_check.d/conf.yaml` | `has_mailcow` | HTTP endpoint checks for Mailcow |
| `http_check.d/postal.yaml` | `has_postal` | HTTP endpoint checks for Postal |
| `tcp_check.d/conf.yaml` | `has_mailcow` or `has_postal` or `has_postfix` | TCP port checks |
| `process.d` | `has_mailcow` or `has_postal` | lightweight named-process checks (not full process list) |
| `postfix.d` | `has_postfix` | standalone Postfix only (not shadowed by Mailcow/Postal) |
| `proxmox.d` + `journald.d` | `has_proxmox` | Proxmox API check + journal log collection |
| `mcache.d` | `has_memcached` | Memcached integration |

### Wrapper Scripts and Logging

All playbooks have a corresponding wrapper script (`run_datadog.sh`, `run_mailcow_recreate.sh`, `run_mailcow_expunge.sh`) that:
- Forces terminal colors via `ANSIBLE_FORCE_COLOR=1`
- Saves a timestamped log to `logs/` with ANSI codes stripped (e.g. `logs/playbook_mailcow_recreate-20260331-054501.log`)
- Preserves the ansible-playbook exit code via `PIPESTATUS[0]`

Retry files are saved to `logs/retry/` (enabled in `ansible.cfg`). To re-run only failed hosts:
```bash
./run_mailcow_recreate.sh --limit @logs/retry/playbook_mailcow_recreate.retry
```

The `logs/` directory is gitignored. The `docs/` directory contains role-specific documentation (`run_datadog.md`, `mailcow_recreate.md`, `mailcow_expunge.md`).

### Mailcow Playbook Behaviour

`playbook_mailcow_recreate.yml` and `playbook_mailcow_expunge.yml` both use:
- `serial: 1` for recreate (one host at a time — container restart causes brief downtime)
- `serial: 5` for expunge (5 hosts at a time — safe to parallelise)
- `max_fail_percentage: 100` — a failed host does not stop the remaining fleet from being processed

### Check Mode (`--check`)

Read-only `command` tasks (version checks, `systemctl is-active`, `datadog-agent status`) use `check_mode: false` so they actually execute during dry runs. Without this, Ansible skips them and returns empty stdout, causing retry loops and index-out-of-bounds failures. Any new read-only `command` task added to `install.yml` or `validate_agent.yml` must include `check_mode: false`.

### Datadog Monitor Tag Reference

Host tags emitted by the agent (use these when scoping monitors):

| Tag | Example values |
|---|---|
| `env` | `production` |
| `role` | `mailserver`, `proxmox`, `generic` |
| `mail_platform` | `mailcow`, `postal`, `postfix`, `generic` |
| `mail_type` | `inbound`, `outbound` |
| `host` / `hostname` | hostname of the server |
| `ip` | public IPv4 only |
| `mailcow_domain` | Mailcow hosts only |

Use `mail_type:inbound` (not `type:inbound`) to scope monitors to inbound VMs.

### Known Limitations

- `container.net.*` and `container.*.partial_stall` metrics require the system probe (NPM) to be running. These are not available with `dd_npm_enabled: false`.
- The "Tokens are required to process patterns" log errors are a known agent issue with `container_collect_all` in this agent version — they are cosmetic and do not affect functionality.
- NTP check will error on OVH inbound VMs because they use the AWS NTP endpoint `169.254.169.123` which is not reachable from OVH.
- `regex_search(..., '\1')` returns `None` (not Undefined) when there is no match. Use `| default([], true)` (with the `true` boolean flag) before `| first` — plain `| default([])` does not replace `None`.
