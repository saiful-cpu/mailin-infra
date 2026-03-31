#!/usr/bin/env bash
# Run the mailcow_recreate playbook and save a timestamped log to logs/
#
# Usage:
#   ./run_mailcow_recreate.sh [ansible-playbook options]
#
# Examples:
#   ./run_mailcow_recreate.sh
#   ./run_mailcow_recreate.sh -l inbound-850-01r
#   ./run_mailcow_recreate.sh --limit @logs/retry/playbook_mailcow_recreate.retry

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/playbook_mailcow_recreate-${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

echo "Logging to ${LOG_FILE}"
ANSIBLE_FORCE_COLOR=1 ansible-playbook "${SCRIPT_DIR}/playbook_mailcow_recreate.yml" "$@" 2>&1 | \
  tee >(sed 's/\x1b\[[0-9;]*[mK]//g' > "${LOG_FILE}")
exit "${PIPESTATUS[0]}"
