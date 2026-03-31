#!/usr/bin/env bash
# Run the mailcow_expunge playbook and save a timestamped log to logs/
#
# Usage:
#   ./run_mailcow_expunge.sh [ansible-playbook options]
#
# Examples:
#   ./run_mailcow_expunge.sh
#   ./run_mailcow_expunge.sh -l inbound-694-01a
#   ./run_mailcow_expunge.sh --limit @logs/retry/playbook_mailcow_expunge.retry

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/playbook_mailcow_expunge-${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

echo "Logging to ${LOG_FILE}"
ANSIBLE_FORCE_COLOR=1 ansible-playbook "${SCRIPT_DIR}/playbook_mailcow_expunge.yml" "$@" 2>&1 | \
  tee >(sed 's/\x1b\[[0-9;]*[mK]//g' > "${LOG_FILE}")
exit "${PIPESTATUS[0]}"
