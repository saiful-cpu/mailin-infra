# Datadog Integration Config — proxmox-node

Proxmox VE bare-metal hypervisor nodes. Monitors the Proxmox API for node
health, VM/LXC resource metrics, and core system stats.

## What must be running before applying

| Service | Check command |
|---|---|
| Proxmox proxy (API) | `systemctl is-active pveproxy` |
| Proxmox daemon | `systemctl is-active pvedaemon` |
| API reachable | `curl -sk https://localhost:8006/api2/json/version` |

## Setup: Proxmox API token

Run on the Proxmox node as root:

```bash
# Create user
pveum user add datadog@pve

# Create token — SAVE THE SECRET, shown only once
pveum user token add datadog@pve datadog --expire 0

# Grant read-only access to entire cluster/node
pveum aclmod / --token 'datadog@pve!datadog' --role PVEAuditor

# Verify
pveum acl list | grep datadog
curl -sk -H 'Authorization: PVEAPIToken=datadog@pve!datadog=<secret>' \
  https://localhost:8006/api2/json/version
```

## Deploying

```bash
cp -r conf.d/* /etc/datadog-agent/conf.d/

# Edit proxmox.d/conf.yaml and set the Authorization header value
nano /etc/datadog-agent/conf.d/proxmox.d/conf.yaml

datadog-agent config-check
systemctl reload datadog-agent
```

## Required datadog.yaml settings

```yaml
logs_enabled: true

process_config:
  process_collection:
    enabled: true

network_config:
  enabled: true
```

## Validate each integration

```bash
datadog-agent check proxmox
datadog-agent check process
datadog-agent check disk
datadog-agent check network

# Check full proxmox output for guest metrics
datadog-agent check proxmox --check-rate 2>&1 | grep -E "proxmox\.|Metric"
```

## Auth configuration note

The Datadog Proxmox check v2.4.0 does **not** support `token_id`/`token_secret` fields — they are silently ignored by the check, resulting in unauthenticated requests and 401 errors.

Authentication uses Datadog's `auth_token` mechanism instead:

```yaml
auth_token:
  reader:
    type: file
    path: /etc/datadog-agent/proxmox_api_token
  writer:
    type: header
    name: Authorization
    value: "PVEAPIToken=mailininfra@pve!mailininfra=<TOKEN>"
```

The token secret file `/etc/datadog-agent/proxmox_api_token` is deployed by Ansible (owned by `dd-agent`, mode 0640). The `<TOKEN>` placeholder is replaced at runtime by fail2ban's file reader with the UUID from the file.

Token provisioning is handled by `run_proxmox_init.sh` which creates the `mailininfra@pve` user, grants `PVEAuditor` role, generates an API token, and encrypts the secret into `host_vars/<hostname>/vault.yml`.

## Auto-collected checks (no conf.yaml needed)

`cpu`, `io`, `load`, `memory`, `uptime`, `file_handle`, `ntp`

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `No ticket` 401 | `token_id`/`token_secret` fields are silently ignored by check v2.4.0 | Use `auth_token` with file reader (see above) |
| `no such user` 401 | User not created on this node | `pveum user add datadog@pve` |
| `invalid token value` 401 | Wrong secret in conf | Regenerate token: `pveum user token remove datadog@pve datadog && pveum user token add ...` |
| `NoneType.get` error | Token exists but missing PVEAuditor ACL | `pveum aclmod / --token 'datadog@pve!datadog' --role PVEAuditor` |
| `certificate verify failed` | Proxmox self-signed cert | Set `tls_verify: false` |
