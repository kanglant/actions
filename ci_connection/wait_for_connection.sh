#!/usr/bin/env bash
#
# Wrapper that attempts to ensure a suitable Python is available before invoking
# wait_for_connection.py. When debugging is enabled,
# Bash x-trace is logged to a file for easier inspection.

source "$(dirname "$0")/utils.sh"

# X-trace setup — write set -x output only to $TRACE_FILE
TRACE_FILE="$(_normalize_path "${HOME}/connection_trace_$(date +%s).log")"
exec 5> "${TRACE_FILE}"           # FD 5 opened for the trace
export BASH_XTRACEFD=19            # Bash will write x-trace to FD 19

set -exuo pipefail

# Cleanup trap — always runs, even on SIGINT
cleanup() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    # Show the trace in the GitHub Actions log, foldable as a group
    echo "::group::connection-debug-trace"
    cat "${TRACE_FILE}"
    echo "::endgroup::"
  fi
  rm -f "${TRACE_FILE}"
  exec 5>&-                       # close FD 5
  exit "$status"
}
trap cleanup EXIT

# Run the code
source "$(dirname "$0")/utils.sh"

python_bin=""
ensure_suitable_python_is_available python_bin
"$python_bin" -V
"$python_bin" "$GITHUB_ACTION_PATH/wait_for_connection.py"
