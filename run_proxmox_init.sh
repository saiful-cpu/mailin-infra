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

# Capture vault password once — ansible-vault requires a trailing newline.
VAULT_PASS_FILE="$(mktemp)"
trap 'rm -f "${VAULT_PASS_FILE}"' EXIT

read -r -s -p "Vault password: " _vault_password
echo
printf '%s\n' "${_vault_password}" > "${VAULT_PASS_FILE}"
unset _vault_password

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/proxmox_init-${TIMESTAMP}.log"
mkdir -p "${LOG_DIR}"

echo "Log file : ${LOG_FILE}"
echo ""

ANSIBLE_FORCE_COLOR=1 ansible-playbook "${SCRIPT_DIR}/playbook_proxmox_init.yml" \
    --vault-password-file "${VAULT_PASS_FILE}" \
    "$@" 2>&1 | \
    tee >(sed 's/\x1b\[[0-9;]*[mK]//g' > "${LOG_FILE}")
PLAYBOOK_RC="${PIPESTATUS[0]}"

# Encrypt any plaintext vault.yml files written by the playbook.
# The playbook writes them unencrypted; we encrypt here so the same password
# is reused without a second prompt.
for vault_file in "${SCRIPT_DIR}"/host_vars/*/vault.yml; do
    [[ -f "${vault_file}" ]] || continue
    # Skip files already encrypted by a previous run
    if ! head -1 "${vault_file}" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
        echo "Encrypting ${vault_file}..."
        ansible-vault encrypt --vault-password-file "${VAULT_PASS_FILE}" "${vault_file}"
    fi
done

exit "${PLAYBOOK_RC}"
