#!/usr/bin/env bash
# fix_pve9_vm_monitor.sh
#
# Removes the dropped 'VM.Monitor' privilege from all custom Proxmox roles
# after a PVE 8 → 9 upgrade. Safe to run multiple times (idempotent).
#
# Usage (run ON the Proxmox node as root):
#   bash fix_pve9_vm_monitor.sh
#
# Or run remotely via Ansible ad-hoc:
#   ansible proxmox_nodes -i inventory/hosts.ini --ask-vault-pass \
#     -m script -a fix_pve9_vm_monitor.sh --become
#
# Or run remotely via SSH on a single node:
#   ssh node-ca-01-0003 'bash -s' < fix_pve9_vm_monitor.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must run as root" >&2
  exit 1
fi

if ! command -v pveum &>/dev/null; then
  echo "ERROR: pveum not found — is this a Proxmox VE node?" >&2
  exit 1
fi

echo "Scanning /etc/pve/user.cfg for VM.Monitor..."

# Find all role lines that contain VM.Monitor
mapfile -t affected < <(grep '^role:' /etc/pve/user.cfg | grep 'VM\.Monitor' | awk -F: '{print $2}')

if [[ ${#affected[@]} -eq 0 ]]; then
  echo "OK: no roles contain VM.Monitor — nothing to do."
  exit 0
fi

echo "Found ${#affected[@]} affected role(s): ${affected[*]}"

for role in "${affected[@]}"; do
  # Get current privs from pveum (already strips VM.Monitor in display on PVE9,
  # but user.cfg still has it — we need to re-save via pveum to clean the file)
  current_privs=$(pveum role list --output-format json 2>/dev/null \
    | python3 -c "
import json, sys
roles = json.load(sys.stdin)
for r in roles:
    if r['roleid'] == '${role}':
        # Remove VM.Monitor from the privilege list
        privs = [p for p in r.get('privs','').split(',') if p and p != 'VM.Monitor']
        print(','.join(privs))
        break
")

  if [[ -z "$current_privs" ]]; then
    echo "WARN: could not determine privs for role '$role' — skipping"
    continue
  fi

  echo "Fixing role: $role"
  pveum role modify "$role" -privs "$current_privs"
  echo "  -> Done"
done

echo ""
echo "Verifying..."
if grep -q 'VM\.Monitor' /etc/pve/user.cfg; then
  echo "FAIL: VM.Monitor still present in user.cfg"
  grep 'VM.Monitor' /etc/pve/user.cfg
  exit 1
else
  echo "OK: user.cfg is clean — VM.Monitor fully removed"
fi
