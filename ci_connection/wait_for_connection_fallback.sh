#!/usr/bin/env bash

# Copyright 2025 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

SENTINEL_FILE="$RUNNER_TEMP/_debug_wait.flag"
echo "WAIT" >"$SENTINEL_FILE"

ENTRYPOINT="$GITHUB_ACTION_PATH/entrypoint.sh"

PARENT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
HALT_DIR="${CONNECTION_HALT_DIR:-${PARENT_DIR}}"

if [[ "$(uname -s)" == CYGWIN_NT* || "$(uname -s)" == MSYS_NT* ]]; then
  HALT_DIR=$(cygpath -m "$HALT_DIR")
fi

CONNECT_CMD="ml-actions-connect \
--runner=${CONNECTION_POD_NAME} \
--ns=${CONNECTION_NS} \
--loc=${CONNECTION_LOCATION} \
--cluster=${CONNECTION_CLUSTER} \
--halt_directory=\"${HALT_DIR}\" \
--entrypoint=\"bash ${ENTRYPOINT} ${SENTINEL_FILE} &\""
BOLD_GREEN_UNDERLINE='\033[1;4;32m'
RESET='\033[0m'

echo "Python-based connection didn't work. Switching to Bash-based one..."
echo "Googler connection only"
echo "See go/ml-github-actions:connect for details"
echo -e "${BOLD_GREEN_UNDERLINE}${CONNECT_CMD}${RESET}\n"

echo "Sentinel file on runner: ${SENTINEL_FILE}"
echo

initial_timeout=600    # 10 min to establish the first touch
inactive_limit=300     # 5 min keep‑alive gap after connection
start_time=$(date +%s)
initial_mtime=$(stat -c %Y "$SENTINEL_FILE")
connected=false
last_update=$start_time

echo "Waiting for connection..."
while true; do
  sleep 5
  [[ -f "$SENTINEL_FILE" ]] || { echo "Sentinel missing – abort."; exit 1; }

  current_mtime=$(stat -c %Y "$SENTINEL_FILE")
  state=$(cat "$SENTINEL_FILE" 2>/dev/null || true)

  # explicit shutdown from entry‑point
  if [[ "$state" == "SHUTDOWN" ]]; then
    echo "SHUTDOWN received – exiting."
    exit 0
  fi

  # detect first touch from client
  if ! $connected && (( current_mtime != initial_mtime )); then
    echo "Connection established."
    connected=true
    last_update=$current_mtime
  fi

  if $connected; then
    # post‑connect keep‑alive
    if (( $(date +%s) - last_update >= inactive_limit )); then
      echo "No keep‑alive for $inactive_limit s – aborting."
      exit 0
    fi
  else
    # still in pre‑connect window
    if (( $(date +%s) - start_time >= initial_timeout )); then
      echo "No connection established within 10 minutes – exiting..."
      exit 0
    fi
  fi

  # refresh last_update on every client write
  if (( current_mtime != last_update )); then
    last_update=$current_mtime
  fi
done
