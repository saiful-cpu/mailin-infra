#!/usr/bin/env bash
# Run the Datadog agent playbook with logging and color support.
#
# Defaults to playbook.yml (mail VMs).
# Use --site to target all host types via site.yml instead.
#
# Usage:
#   ./run_datadog.sh [--site] [ansible-playbook options]
#
# Examples:
#   ./run_datadog.sh
#   ./run_datadog.sh -l mailin_inbound
#   ./run_datadog.sh --site -l proxmox_nodes
#   ./run_datadog.sh --tags configure
#   ./run_datadog.sh --check

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

# Parse --site flag out before passing remaining args to ansible-playbook
PLAYBOOK="playbook.yml"
EXTRA_ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "--site" ]]; then
        PLAYBOOK="site.yml"
    else
        EXTRA_ARGS+=("$arg")
    fi
done

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PLAYBOOK_SLUG="${PLAYBOOK%.yml}"
LOG_FILE="${LOG_DIR}/${PLAYBOOK_SLUG}-${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

echo "Playbook : ${PLAYBOOK}"
echo "Log file : ${LOG_FILE}"
echo ""

ANSIBLE_FORCE_COLOR=1 ansible-playbook "${SCRIPT_DIR}/${PLAYBOOK}" \
    --ask-vault-pass \
    "${EXTRA_ARGS[@]}" 2>&1 | \
    tee >(sed 's/\x1b\[[0-9;]*[mK]//g' > "${LOG_FILE}")
exit "${PIPESTATUS[0]}"
