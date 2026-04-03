#!/usr/bin/env bash
# Run the disk_cleanup role only via playbook.yml.
#
# Usage:
#   ./run_disk_cleanup.sh
#   ./run_disk_cleanup.sh -l inbound-850-01r
#   ./run_disk_cleanup.sh -l mailin_inbound
#   ./run_disk_cleanup.sh -e "disk_cleanup_restart_docker=true"
#   ./run_disk_cleanup.sh --check

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
PLAYBOOK="playbook.yml"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/disk_cleanup-${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

echo "Playbook : ${PLAYBOOK} (tags: disk_cleanup)"
echo "Log file : ${LOG_FILE}"
echo ""

ANSIBLE_FORCE_COLOR=1 ansible-playbook "${SCRIPT_DIR}/${PLAYBOOK}" \
    --ask-vault-pass \
    --tags disk_cleanup \
    "$@" 2>&1 | \
    tee >(sed 's/\x1b\[[0-9;]*[mK]//g' > "${LOG_FILE}")
exit "${PIPESTATUS[0]}"
