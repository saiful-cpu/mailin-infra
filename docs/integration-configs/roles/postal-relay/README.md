# Datadog Integration Config — postal-relay

Postal MTA running in Docker, used as an outbound mail relay. Includes MySQL,
Redis, Postfix (Postal's SMTP engine), and Docker monitoring.

## What must be running before applying

| Service | Check command |
|---|---|
| Docker daemon | `systemctl is-active docker` |
| Postal containers | `docker ps --format '{{.Names}}' \| grep postal` |
| MySQL/MariaDB | `systemctl is-active mysql` or `mariadb` |
| Redis | `redis-cli ping` |
| Postfix | `systemctl is-active postfix` |

## OS prerequisites

```bash
# dd-agent in docker group
usermod -aG docker dd-agent
systemctl restart datadog-agent

# Postfix sudo rule
cat > /etc/sudoers.d/datadog-postfix << 'EOF'
dd-agent ALL=(root) NOPASSWD: /usr/sbin/postqueue -p
dd-agent ALL=(root) NOPASSWD: /usr/bin/find /var/spool/postfix -type f
EOF
chmod 440 /etc/sudoers.d/datadog-postfix
```

## MySQL: create monitoring user

```sql
CREATE USER 'datadog'@'localhost' IDENTIFIED BY '<STRONG_PASSWORD>';
GRANT REPLICATION CLIENT ON *.* TO 'datadog'@'localhost' WITH MAX_USER_CONNECTIONS 5;
GRANT PROCESS ON *.* TO 'datadog'@'localhost';
GRANT SELECT ON performance_schema.* TO 'datadog'@'localhost';
GRANT SELECT ON postal.* TO 'datadog'@'localhost';
FLUSH PRIVILEGES;
```

Then update `mysql.d/conf.yaml` with the password.

## Postal queue monitoring

> **There is no official Datadog `postal` integration.** Queue depth is
> monitored via two proxies:

### 1. Redis key lengths (Resque queues)

The `redisdb.d/conf.yaml` monitors `resque:queue:*` key lengths directly.
Alert on `redis.key.length{key:resque:queue:delivery} > 500`.

### 2. MySQL query (deferred messages)

Use a custom Datadog metric via the MySQL check or a cron-based script:

```sql
-- Queue depth by status
SELECT status, COUNT(*) AS cnt
FROM postal.messages
WHERE created_at > NOW() - INTERVAL 1 HOUR
GROUP BY status;
```

### 3. Postal status CLI

```bash
# Run from inside the Postal container
docker exec postal-web postal status
```

## Docker log collection (Postal containers)

Add to `docker-compose.override.yml`:

```yaml
services:
  postal-web:
    labels:
      com.datadoghq.ad.logs: '[{"source":"ruby","service":"postal-web"}]'
  postal-worker:
    labels:
      com.datadoghq.ad.logs: '[{"source":"ruby","service":"postal-worker"}]'
  postal-smtp:
    labels:
      com.datadoghq.ad.logs: '[{"source":"postfix","service":"postal-smtp"}]'
  postal-cron:
    labels:
      com.datadoghq.ad.logs: '[{"source":"ruby","service":"postal-cron"}]'
```

## Required datadog.yaml settings

```yaml
logs_enabled: true
process_config:
  process_collection:
    enabled: true
apm_config:
  enabled: true
network_config:
  enabled: true
```

## Validate each integration

```bash
datadog-agent check docker
datadog-agent check mysql
datadog-agent check redisdb
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
| MySQL check: `Access denied` | Missing grants | Run SQL setup above |
| Postfix check: `sudo access` error | Missing sudoers file | Add `/etc/sudoers.d/datadog-postfix` |
| Redis key length always 0 | Wrong key names | Check `redis-cli keys 'resque:*'` |
| `postal` check not found | No official check exists | Use process + redis + mysql monitoring instead |
