# Role: mailcow_recreate

Force recreates all Mailcow Docker containers on target hosts using `docker compose up -d --force-recreate`. Useful when containers are in a bad state, after config changes, or as part of routine maintenance.

---

## What it does

1. Checks that `/opt/mailcow-dockerized` exists on the host
2. Runs `docker compose up -d --force-recreate` from that directory
3. Automatically retries up to 2 times (10s apart) if Docker returns a transient error

Hosts where `/opt/mailcow-dockerized` is not found are silently skipped.

---

## Playbook

`playbook_mailcow_recreate.yml` targets `mailin_inbound` and `mail_servers` groups.

| Setting | Value |
|---|---|
| `serial` | `1` — one host at a time |
| `max_fail_percentage` | `100` — a failed host does not stop the rest of the fleet |
| `become` | `true` |

---

## Usage

Always use the wrapper script — it saves a timestamped log to `logs/` and preserves colors in the terminal.

### Run against the full fleet

```bash
./run_mailcow_recreate.sh
```

### Run against a single host

```bash
./run_mailcow_recreate.sh -l inbound-850-01r
```

### Run against a specific group

```bash
./run_mailcow_recreate.sh -l inbound_850
```

### Re-run only failed hosts after a failed run

```bash
./run_mailcow_recreate.sh --limit @logs/retry/playbook_mailcow_recreate.retry
```

### Dry run (no changes made)

```bash
./run_mailcow_recreate.sh --check
```

---

## Logs

Each run creates a timestamped log file:

```
logs/playbook_mailcow_recreate-YYYYMMDD-HHMMSS.log
```

ANSI color codes are stripped from log files. To review the last run:

```bash
cat logs/$(ls -t logs/playbook_mailcow_recreate-*.log | head -1)
```

If a host fails, a retry file is written to:

```
logs/retry/playbook_mailcow_recreate.retry
```

---

## Troubleshooting

### A host failed with "No such container"

This is a transient Docker state issue. The task retries automatically up to 2 times. If it still fails, re-run against just that host:

```bash
./run_mailcow_recreate.sh -l <hostname>
```

### Check container status on a host

```bash
ssh <hostname> "cd /opt/mailcow-dockerized && docker compose ps"
```

### Check Docker logs for a specific container

```bash
ssh <hostname> "docker logs mailcowdockerized-dovecot-mailcow-1 --tail 50"
```

### Manually recreate containers on a host

```bash
ssh <hostname> "cd /opt/mailcow-dockerized && docker compose up -d --force-recreate"
```

### Check which hosts failed in the last run

```bash
cat logs/retry/playbook_mailcow_recreate.retry
```

### Review full output of the last run

```bash
less logs/$(ls -t logs/playbook_mailcow_recreate-*.log | head -1)
```
