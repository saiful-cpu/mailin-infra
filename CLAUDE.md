# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an Ansible repository that installs and configures the Datadog Agent (v7) across a fleet of mail servers, Proxmox VE nodes, and a jumpserver. The central design principle is **service auto-detection**: the `detect.yml` task probes each host at runtime and sets boolean facts (`has_docker`, `has_mailcow`, `has_postal`, `has_postfix`, `has_redis`, `has_memcached`, `has_proxmox`). Subsequent configure tasks are gated on those facts, so a single role works across heterogeneous hosts without per-host task lists.

## Running Playbooks

All-hosts deployment (mail servers + Proxmox nodes + jumpserver):
```bash
ansible-playbook site.yml --ask-vault-pass
```

Mail servers only (legacy playbook, also runs `disk_cleanup` role):
```bash
ansible-playbook playbook.yml --ask-vault-pass
```

Proxmox nodes only (uses `datadog_proxmox` role, legacy):
```bash
ansible-playbook playbook_proxmox.yml --ask-vault-pass
```

Limit to a single host or group:
```bash
ansible-playbook site.yml -l pve01 --ask-vault-pass
ansible-playbook site.yml -l mail_servers --ask-vault-pass
```

Dry run:
```bash
ansible-playbook site.yml --ask-vault-pass --check
```

Force agent reinstall regardless of current version:
```bash
ansible-playbook site.yml --ask-vault-pass -e "dd_force_update=true"
```

Run only specific phases via tags:
```bash
ansible-playbook site.yml --ask-vault-pass --tags detect
ansible-playbook site.yml --ask-vault-pass --tags "configure,redis"
ansible-playbook site.yml --ask-vault-pass --tags validate
```

Available tags: `detect`, `install`, `configure`, `core`, `docker`, `mailcow`, `postal`, `postfix`, `redis`, `memcached`, `proxmox`, `disk`, `validate`, `cleanup`

## Architecture

### Roles

- **`datadog_server`** — primary role used by `site.yml` for all host types. Runs detection, installs the agent, then conditionally applies integration configs based on detected services.
- **`datadog_proxmox`** — older dedicated role for Proxmox nodes, used by `playbook_proxmox.yml`. Superseded by `datadog_server` in `site.yml`.
- **`datadog_mail`** — older dedicated role for mail VMs. Superseded by `datadog_server`.
- **`disk_cleanup`** — configures Docker log rotation, systemd journal limits, and a cron-based purge script. Applied alongside `datadog_server` in `playbook.yml`.

### Detection Flow (`roles/datadog_server/tasks/detect.yml`)

Detection resets state variables first (prevents stale facts on multi-play runs), then probes: Docker → Proxmox → Mailcow → Postal → Postfix → Redis → Memcached. It also derives two Datadog host tags:
- `server_role`: `proxmox | mailcow | postal | postfix | generic`
- `mail_type`: `inbound | outbound | none | unknown` (derived from hostname patterns or detected services)

Postfix is only flagged as standalone if it is not shadowed by Mailcow or Postal.

### Secrets / Vault

- `vars/vault.yml` — contains `vault_dd_api_key` (Ansible Vault encrypted, AES256)
- `vars/vault_proxmox.yml` — contains `vault_proxmox_api_user`, `vault_proxmox_api_token_name`, `vault_proxmox_api_token_secret`
- `host_vars/<hostname>/vault.yml` — per-node overrides for Proxmox API credentials
- `host_vars/<hostname>/vars.yml` — per-node non-secret vars (e.g. `proxmox_api_user`, `proxmox_api_token_name`)

The DD API key falls back to the `DD_API_KEY` environment variable if vault is unavailable (see `roles/datadog_server/defaults/main.yml`).

### Inventory Groups (`inventory/hosts.ini`)

| Group | Description |
|---|---|
| `mail_servers` | Mailcow/general mail hosts |
| `mailin_inbound` | Inbound mail VMs (OVH Virginia) — SSH via `~/.ssh/mailin.pem`, user `ubuntu` |
| `proxmox_nodes` | Proxmox VE nodes — SSH via `~/.ssh/id_ed25519`, user `root` |
| `jumpservers` | Local jumpserver (`127.0.0.1`) |

The `outbound.ini` file (`inventory/outbound.ini`) exists but is not yet referenced by `ansible.cfg`.

### Key Defaults (`roles/datadog_server/defaults/main.yml`)

- `dd_agent_min_version: "7.76.3"` — agent is upgraded if the installed version is below this
- `dd_force_update: false` — set to `true` to force reinstall
- `dd_apm_enabled: true`, `dd_npm_enabled: true`, `dd_logs_enabled: true`, `dd_process_enabled: false`
- Mailcow is searched in `/opt/mailcow-dockerized`, `/opt/mailcow`, `/srv/mailcow-dockerized`, `/root/mailcow-dockerized`
- Postal is searched in `/opt/postal`, `/etc/postal`
