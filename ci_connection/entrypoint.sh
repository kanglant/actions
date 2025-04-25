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

# Used in conjunction with the fallback waiting loop, when Python doesn't work or isn't available.
# Basic shell setup. Keep‑alive pinger; sends SHUTDOWN when it exits.

set -uo pipefail

SENTINEL="$1"
[ -n "$SENTINEL" ] || { echo "Usage: $0 <sentinel-file>"; exit 1; }

keep_alive_loop() {
  trap 'echo "SHUTDOWN" >"$SENTINEL"' EXIT

  echo "WAIT" >"$SENTINEL"

  while true; do
    sleep 60
    echo "WAIT" >"$SENTINEL"
  done
}

keep_alive_loop & # Run the keep-alive loop in the background
_keepalive_pid=$! # Capture the Process ID (PID) of the background loop

# Run on exit, so, whenever the user ends their `bash -il` session,
# or any other termination of the script
_main_cleanup() {
  echo "[Entrypoint] Interactive session ended or signal received. Cleaning up keep-alive ($_keepalive_pid)..." >&2
  kill "$_keepalive_pid" 2>/dev/null || true
  # Wait for the keep-alive process to be terminated fully, so it can run its own TRAP
  wait "$_keepalive_pid" 2>/dev/null || true
  echo "[Entrypoint] Cleanup complete." >&2
}
trap _main_cleanup EXIT

# Launch an interactive shell in the foreground
echo "[Entrypoint] Starting interactive shell for user. Keep-alive running in background (PID: $_keepalive_pid)." >&2
echo "[Entrypoint] Type 'exit' or Ctrl+D when done." >&2
bash -il

exit 0
