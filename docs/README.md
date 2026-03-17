# datadog_mail — Ansible Role

Installs and configures the Datadog Agent on Mailcow and standalone Postfix mail VMs.
Auto-detects services and writes only the integrations that are relevant.

## Requirements

- Ansible ≥ 2.12
- Target: Debian 11/12, Ubuntu 20.04/22.04/24.04, AlmaLinux/RHEL 8/9
- `become: true` (root access)
- Outbound HTTPS to `install.datadoghq.com` and your `DD_SITE`

## Quick start

```bash
# 0. Encrypt the vault
ansible-vault encrypt vars/vault.yml
# remember the Vault password.

# 1. Set your API key in vault
ansible-vault edit vars/vault.yml
#    set: vault_dd_api_key: "your_key"

# 2. Run
ansible-playbook playbook.yml --ask-vault-pass

# 3. Limit to one host for testing
ansible-playbook playbook.yml -l inbound-419-01b --ask-vault-pass
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `dd_api_key` | **required** | Datadog API key — always pass via vault |
| `dd_site` | `datadoghq.com` | Datadog intake site |
| `dd_env` | `prod` | Environment tag |
| `mailcow_search_paths` | see defaults | Paths to search for Mailcow install |
| `disk_excluded_filesystems` | `tmpfs,devtmpfs,...` | FSes excluded from disk check |

## Tags

```bash
ansible-playbook playbook.yml --tags detect        # detection only
ansible-playbook playbook.yml --tags install       # install agent only
ansible-playbook playbook.yml --tags configure     # all integration configs
ansible-playbook playbook.yml --tags mailcow       # Mailcow configs only
ansible-playbook playbook.yml --tags postfix       # Postfix configs only
ansible-playbook playbook.yml --tags validate      # restart + verify only
```

## Directory layout

```
datadog_mail/
├── ansible.cfg
├── playbook.yml
├── inventory/
│   └── hosts.ini
├── vars/
│   └── vault.yml            ← ansible-vault encrypted, holds dd_api_key
└── roles/
    └── datadog_mail/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── meta/main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── validate.yml
        │   ├── detect.yml
        │   ├── install.yml
        │   ├── configure_core.yml
        │   ├── configure_docker.yml
        │   ├── configure_mailcow.yml
        │   ├── configure_postfix.yml
        │   ├── configure_disk.yml
        │   └── validate_agent.yml
        └── templates/
            ├── docker_conf.yaml.j2
            ├── mailcow_http_check.yaml.j2
            ├── mailcow_tcp_check.yaml.j2
            ├── mailcow_logs.yaml.j2
            ├── postfix_conf.yaml.j2
            ├── postfix_tcp_check.yaml.j2
            └── disk_conf.yaml.j2
```

## What gets configured per detected service

| Service detected | Integrations deployed |
|---|---|
| Docker | `docker.d/conf.yaml` |
| Mailcow | `http_check.d/`, `tcp_check.d/`, `mailcow_logs.d/` |
| Postfix (standalone) | `postfix.d/`, `tcp_check.d/` (if not Mailcow) |
| Always | `disk.d/`, core `datadog.yaml` tuning |

## Fixes vs original shell script

- API key never hardcoded — required via vault or env
- `mailcow_logs` config placed in `conf.d/mailcow_logs.d/conf.yaml` (not directly in `conf.d/`)
- Docker log filters use compose service labels, not image names
- Rspamd TCP check on port 11334 removed (not host-exposed in Mailcow)
- Postfix detection uses `systemctl is-active`, not `pgrep master`
- `all_partitions: false` on disk check (prevents Docker overlay metric flood)
- `DD_ENV` written to `datadog.yaml` as `env:`, not only in host tags
- `sleep 8` replaced with proper poll loop (retries: 15, delay: 2)
- `DD_SITE` validated against known Datadog endpoints before use
