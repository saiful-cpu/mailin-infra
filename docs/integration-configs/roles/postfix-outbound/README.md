# Datadog Integration Config — postfix-outbound

Bare-metal outbound Postfix servers. No Docker. System-level monitoring plus
Postfix queue depth and process health.

## What must be running before applying

| Service | Check command |
|---|---|
| Postfix | `systemctl is-active postfix` |
| postqueue accessible | `/usr/sbin/postqueue -p` (run as root) |

## OS prerequisites

```bash
# Create sudoers rule so dd-agent can run postqueue
cat > /etc/sudoers.d/datadog-postfix << 'EOF'
dd-agent ALL=(root) NOPASSWD: /usr/sbin/postqueue -p
dd-agent ALL=(root) NOPASSWD: /usr/bin/find /var/spool/postfix -type f
EOF
chmod 440 /etc/sudoers.d/datadog-postfix

# Verify
sudo -u dd-agent sudo /usr/sbin/postqueue -p
```

## Deploying

```bash
cp -r conf.d/* /etc/datadog-agent/conf.d/
datadog-agent config-check
systemctl reload datadog-agent  # or restart if first install
```

## Required datadog.yaml settings

```yaml
logs_enabled: true

process_config:
  process_collection:
    enabled: true
```

## Validate each integration

```bash
datadog-agent check postfix
datadog-agent check process
datadog-agent check disk
datadog-agent check network
```

## Auto-collected checks (no conf.yaml needed)

`cpu`, `io`, `load`, `memory`, `uptime`, `file_handle`, `ntp`

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `dd-agent user does not have sudo access` | Missing sudoers rule | Add `/etc/sudoers.d/datadog-postfix` as above |
| `postqueue: fatal: open /etc/postfix/main.cf: No such file or directory` | Wrong `directory` path | Check `postconf queue_directory` |
| Queue always 0 | Permission issue or no mail | Check `mailq` manually |
