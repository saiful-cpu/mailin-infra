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

The Proxmox check uses the `headers` field for authentication — **not**
`token_id`/`token_secret`. The correct format is:

```yaml
headers:
  Authorization: "PVEAPIToken=<user>@<realm>!<tokenid>=<secret>"
```

## Auto-collected checks (no conf.yaml needed)

`cpu`, `io`, `load`, `memory`, `uptime`, `file_handle`, `ntp`

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `No ticket` 401 | Auth header missing/wrong format | Verify `headers.Authorization` in conf.yaml |
| `no such user` 401 | User not created on this node | `pveum user add datadog@pve` |
| `invalid token value` 401 | Wrong secret in conf | Regenerate token: `pveum user token remove datadog@pve datadog && pveum user token add ...` |
| `NoneType.get` error | Token exists but missing PVEAuditor ACL | `pveum aclmod / --token 'datadog@pve!datadog' --role PVEAuditor` |
| `certificate verify failed` | Proxmox self-signed cert | Set `tls_verify: false` |
