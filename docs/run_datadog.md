# run_datadog.sh

Wrapper script for deploying the Datadog agent across the fleet. Handles vault password prompting, terminal colors, and timestamped log files automatically.

---

## Playbooks

| Flag | Playbook | Targets |
|---|---|---|
| _(default)_ | `playbook.yml` | `mail_servers`, `mailin_inbound`, `mailin_outbound`, `node_hi_10_0001_vms_in` |
| `--site` | `site.yml` | `mail_servers`, `proxmox_nodes`, `jumpserver` |

---

## Usage

```bash
./run_datadog.sh [--site] [ansible-playbook options]
```

`--ask-vault-pass` is always included automatically. Any standard `ansible-playbook` flag can be appended.

---

## Examples

### Deploy to all mail VMs (default)

```bash
./run_datadog.sh
```

### Deploy to all host types (mail + Proxmox + jumpserver)

```bash
./run_datadog.sh --site
```

### Limit to a single host

```bash
./run_datadog.sh -l inbound-850-01r
```

### Limit to a group

```bash
./run_datadog.sh -l mailin_inbound
./run_datadog.sh -l inbound_850
./run_datadog.sh --site -l proxmox_nodes
```

### Dry run — no changes applied

```bash
./run_datadog.sh --check
./run_datadog.sh --site --check
```

### Run only specific phases via tags

```bash
# Detection only
./run_datadog.sh --tags detect

# Install/upgrade agent only
./run_datadog.sh --tags install

# Apply all integration configs (skip install)
./run_datadog.sh --tags configure

# Single integration
./run_datadog.sh --tags redis
./run_datadog.sh --tags mailcow
./run_datadog.sh --tags postfix

# Validate agent is running and healthy
./run_datadog.sh --tags validate

# Multiple tags
./run_datadog.sh --tags "configure,redis"
```

### Force agent reinstall

```bash
./run_datadog.sh -e "dd_force_update=true" --tags install,configure
```

### Wipe config and reprovision a single host

```bash
./run_datadog.sh -l <hostname> --tags reset,configure
```

### Combine limit and tags

```bash
./run_datadog.sh -l inbound_850 --tags configure
./run_datadog.sh --site -l proxmox_nodes --tags configure,proxmox
```

---

## Logs

Each run saves a timestamped log to `logs/`:

```
logs/playbook-YYYYMMDD-HHMMSS.log       # from playbook.yml
logs/site-YYYYMMDD-HHMMSS.log           # from site.yml (--site)
```

ANSI color codes are stripped from log files. Terminal output retains full color.

### View the last run log

```bash
# playbook.yml
less logs/$(ls -t logs/playbook-*.log | head -1)

# site.yml
less logs/$(ls -t logs/site-*.log | head -1)
```

### Search logs for failures

```bash
grep -i "fatal\|failed\|error" logs/$(ls -t logs/playbook-*.log | head -1)
```

### List all past runs

```bash
ls -lht logs/playbook-*.log
ls -lht logs/site-*.log
```

---

## Available Tags

| Tag | What it runs |
|---|---|
| `detect` | Service detection only (sets `has_docker`, `has_mailcow`, etc.) |
| `install` | Install or upgrade the Datadog agent |
| `backup` | Backup `/etc/datadog-agent/` before changes |
| `reset` | Wipe user-managed configs (always pair with `configure`) |
| `configure` | Deploy all integration configs |
| `core` | `datadog.yaml` and `system-probe.yaml` only |
| `docker` | Docker integration |
| `mailcow` | Mailcow HTTP/TCP checks |
| `postal` | Postal HTTP/TCP checks |
| `postfix` | Postfix queue monitoring |
| `redis` | Redis integration |
| `memcached` | Memcached integration |
| `proxmox` | Proxmox API check + journald logs |
| `disk` | Disk monitoring config |
| `validate` | Start agent and verify it is running |
| `cleanup` | Remove stale integration configs |

---

## Troubleshooting

### Check agent status on a host

```bash
ssh <hostname> "datadog-agent status"
```

### Check agent version on a host

```bash
ssh <hostname> "datadog-agent version"
```

### Tail agent logs on a host

```bash
ssh <hostname> "tail -f /var/log/datadog/agent.log"
```

### Re-run after fixing a failed host

```bash
./run_datadog.sh -l <hostname>
```

### Check what would change without applying (dry run)

```bash
./run_datadog.sh -l <hostname> --check
```
