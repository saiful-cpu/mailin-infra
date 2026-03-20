# Datadog Integration Config — mailcow-inbound

Mailcow stack running in Docker. Applies to inbound MX servers on AWS EC2 or
Proxmox VMs.

## What must be running before applying

| Service | Check command |
|---|---|
| Docker daemon | `systemctl is-active docker` |
| Mailcow containers | `docker ps --format '{{.Names}}' \| grep mailcow` |
| Redis (in Docker) | `docker exec redis-mailcow redis-cli ping` |
| Memcached (in Docker) | `echo stats \| nc 127.0.0.1 11211` |
| Nginx (webui reachable) | `curl -sk https://localhost/ -o /dev/null -w '%{http_code}'` |

## OS prerequisites

```bash
# dd-agent must be in the docker group
usermod -aG docker dd-agent
systemctl restart datadog-agent

# Confirm group membership
id dd-agent   # should include 'docker'
```

## Deploying

```bash
# Copy all conf.d files
cp -r conf.d/* /etc/datadog-agent/conf.d/

# Restart for Docker group change (first install only)
systemctl restart datadog-agent

# Subsequent config changes use live reload
datadog-agent config-check   # validate syntax
```

## Docker log collection (label approach)

Add to `/opt/mailcow-dockerized/docker-compose.override.yml`:

```yaml
services:
  postfix-mailcow:
    labels:
      com.datadoghq.ad.logs: '[{"source":"postfix","service":"mailcow-postfix"}]'
  dovecot-mailcow:
    labels:
      com.datadoghq.ad.logs: '[{"source":"dovecot","service":"mailcow-dovecot"}]'
  rspamd-mailcow:
    labels:
      com.datadoghq.ad.logs: '[{"source":"rspamd","service":"mailcow-rspamd"}]'
  nginx-mailcow:
    labels:
      com.datadoghq.ad.logs: '[{"source":"nginx","service":"mailcow-nginx"}]'
  sogo-mailcow:
    labels:
      com.datadoghq.ad.logs: '[{"source":"sogo","service":"mailcow-sogo"}]'
  php-fpm-mailcow:
    labels:
      com.datadoghq.ad.logs: '[{"source":"php-fpm","service":"mailcow-phpfpm"}]'
  clamd-mailcow:
    labels:
      com.datadoghq.ad.logs: '[{"source":"clamav","service":"mailcow-clamd"}]'
```

```bash
cd /opt/mailcow-dockerized
docker compose up -d   # applies labels without full restart
```

## Required datadog.yaml settings

```yaml
logs_enabled: true
logs_config:
  container_collect_all: false   # collect only labelled containers

process_config:
  process_collection:
    enabled: true

apm_config:
  enabled: true

network_config:
  enabled: true   # NPM — requires system-probe
```

## Validate each integration

```bash
datadog-agent check docker
datadog-agent check redisdb
datadog-agent check mcache
datadog-agent check http_check
datadog-agent check tcp_check
datadog-agent check disk
datadog-agent check network
datadog-agent check process
datadog-agent status | grep -A10 "Logs Agent"
```

## Auto-collected checks (no conf.yaml needed)

The following are enabled automatically by the Agent core and require no
configuration file: `cpu`, `io`, `load`, `memory`, `uptime`, `file_handle`,
`ntp`.

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| Docker check: permission denied | dd-agent not in docker group | `usermod -aG docker dd-agent` + restart |
| Redis check: connection refused | Mailcow Redis container not running | `docker start redis-mailcow` |
| http_check: SSL error | Self-signed cert | Set `tls_verify: false` |
| tcp_check: port closed | Postfix/Dovecot not started | Check mailcow container health |
