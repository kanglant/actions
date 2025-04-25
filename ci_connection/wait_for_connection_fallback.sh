#!/usr/bin/env bash

set -euo pipefail

# --- Configuration ---
SENTINEL_FILE="${RUNNER_TEMP}/_debug_wait.flag"
GITHUB_ACTION_PATH="${GITHUB_ACTION_PATH:-.}"

: "${CONNECTION_POD_NAME?Error: CONNECTION_POD_NAME is not set}"
: "${CONNECTION_NS?Error: CONNECTION_NS is not set}"
: "${CONNECTION_LOCATION?Error: CONNECTION_LOCATION is not set}"
: "${CONNECTION_CLUSTER?Error: CONNECTION_CLUSTER is not set}"

# --- Path Setup ---
echo "WAIT" >"$SENTINEL_FILE" # Create/overwrite sentinel file

ENTRYPOINT_SCRIPT_NAME="entrypoint.sh" # Assume entrypoint.sh is directly in GITHUB_ACTION_PATH
ENTRYPOINT="$GITHUB_ACTION_PATH/$ENTRYPOINT_SCRIPT_NAME"

# Check if this is running in a Cygwin/MSYS environment on Windows
if [[ "$(uname -s)" == CYGWIN_NT* || "$(uname -s)" == MSYS_NT* ]]; then
  ENTRYPOINT=$(cygpath -m "$ENTRYPOINT")
  SENTINEL_FILE=$(cygpath -m "$SENTINEL_FILE")
fi

# --- Build Connect Command ---
CONNECT_CMD="ml-actions-connect \\
--runner=${CONNECTION_POD_NAME} \\
--ns=${CONNECTION_NS} \\
--loc=${CONNECTION_LOCATION} \\
--cluster=${CONNECTION_CLUSTER} \\
--entrypoint=\"bash ${ENTRYPOINT} ${SENTINEL_FILE}\""

BOLD_GREEN_UNDERLINE='\033[1;4;32m'
RESET='\033[0m'

# --- User Instructions ---
echo "Python-based connection didn't work. Switching to Bash-based one..."
echo "Googler connection only_debug_wait"
echo "See go/ml-github-actions:connect for details"
echo "To connect, run the following command in your local terminal:"
echo -e "${BOLD_GREEN_UNDERLINE}----------------------------------------------------------------------${RESET}"
echo "${CONNECT_CMD}"
echo -e "${BOLD_GREEN_UNDERLINE}----------------------------------------------------------------------${RESET}"
echo

# --- Monitoring Logic ---
initial_timeout=600    # 10 minutes to establish the first touch
keep_alive_interval=300     # 5 minutes keep‑alive gap after connection

echo "Sentinel file on runner: ${SENTINEL_FILE}"
echo "Will wait $((initial_timeout / 60)) minutes (${initial_timeout} seconds) for the initial connection."
echo

start_time=$(date +%s)
# Ensure file exists before stat, handle potential race condition
if [[ ! -f "$SENTINEL_FILE" ]]; then
    echo "Error: Sentinel file '$SENTINEL_FILE' disappeared before starting wait." >&2
    exit 1
fi
initial_mtime=$(stat -c %Y "$SENTINEL_FILE") # Assumes GNU stat
connected=false
last_update=$start_time # Initialize last_update relative to script start initially

echo "Waiting for connection..."
while true; do
  sleep 5
  [[ -f "$SENTINEL_FILE" ]] || { echo "Sentinel file missing – aborting."; exit 1; }

  current_mtime=$(stat -c %Y "$SENTINEL_FILE" 2>/dev/null || echo "$initial_mtime") # Handle stat errors gracefully
  # If stat failed, current_mtime retains previous value, loop continues checking state/timeouts

  state=$(cat "$SENTINEL_FILE" 2>/dev/null || echo "UNKNOWN")

  if [[ "$state" == "SHUTDOWN" ]]; then
    echo "SHUTDOWN received – exiting."
    exit 0
  fi

  # Detect first touch from client
  if ! $connected && (( current_mtime > initial_mtime )); then
    echo "Connection established at $(date '+%Y-%m-%d %H:%M:%S')."
    connected=true
    last_update=$current_mtime
  fi

  # Check timeouts based on connection state
  if $connected; then
    # Post‑connect keep‑alive timeout
    if (( $(date +%s) - last_update >= keep_alive_interval )); then
      echo "No keep-alive received for $keep_alive_interval seconds – aborting."
      exit 0
    fi
  else
    # Still in pre‑connect window timeout
    if (( $(date +%s) - start_time >= initial_timeout )); then
      echo "No connection established within $((initial_timeout / 60)) minutes – exiting..."
      exit 0
    fi
  fi

  # Refresh last_update on every client write after initial connection
  # and print keep-alive message
  if $connected && (( current_mtime > last_update )); then
    echo "Keep-alive received at $(date '+%Y-%m-%d %H:%M:%S'). Resetting the ${keep_alive_interval}s keep-alive timer."
    last_update=$current_mtime
  fi
done
