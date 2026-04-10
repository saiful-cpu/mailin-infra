#!/usr/bin/env bash
# Provision Datadog API tokens on Proxmox nodes (first-time setup).
#
# For each proxmox_nodes host that lacks host_vars/<hostname>/vault.yml,
# this script:
#   - Creates mailininfra@pve user + PVEAuditor ACL on the node
#   - Generates an API token and stores the secret locally in
#     host_vars/<hostname>/vault.yml (ansible-vault encrypted)
#
# Hosts that already have vault.yml are skipped automatically.
#
# Usage:
#   ./run_proxmox_init.sh                      # all proxmox_nodes
#   ./run_proxmox_init.sh -l node-hi-60-0001   # single host

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

# Capture vault password once — used by ansible-playbook AND the in-playbook
# ansible-vault encrypt step.
VAULT_PASS_FILE="$(mktemp)"
trap 'rm -f "${VAULT_PASS_FILE}"' EXIT

read -r -s -p "Vault password: " _vault_password
echo
printf '%s' "${_vault_password}" > "${VAULT_PASS_FILE}"
unset _vault_password

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/proxmox_init-${TIMESTAMP}.log"
mkdir -p "${LOG_DIR}"

echo "Log file : ${LOG_FILE}"
echo ""

ANSIBLE_FORCE_COLOR=1 ansible-playbook "${SCRIPT_DIR}/playbook_proxmox_init.yml" \
    --vault-password-file "${VAULT_PASS_FILE}" \
    -e "vault_pass_file=${VAULT_PASS_FILE}" \
    "$@" 2>&1 | \
    tee >(sed 's/\x1b\[[0-9;]*[mK]//g' > "${LOG_FILE}")
exit "${PIPESTATUS[0]}"
