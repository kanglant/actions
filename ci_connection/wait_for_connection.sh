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


# A wrapper script that does its best to make sure a suitable Python is
# available so that `wait_for_connection.py` and `notify_connection.py` can be
# run without issues.

set -euo pipefail

source "$(dirname "$0")/utils.sh"

echo "INFO: Determining Python executable..." >&2

# See if there's an existing suitable Python
if ! python_bin=$(suitable_python_exists); then
    echo "INFO: No suitable system Python found. Ensuring Python via uv..." >&2
    python_bin=$(ensure_suitable_python_is_available) || {
      echo "ERR: Failed to find/install Python using uv." >&2
      exit 1
    }
    # Sanity check: ensure the successful command actually produced output.
    if [[ -z "$python_bin" ]]; then
         echo "ERR: uv process succeeded but Python path was not output." >&2
         exit 1
    fi
    echo "INFO: Using Python installed/found by uv: $python_bin" >&2
else
    echo "INFO: Found suitable system Python: $python_bin" >&2
fi

echo "INFO: Using Python: $python_bin"
"$python_bin" --version

"$python_bin" "$GITHUB_ACTION_PATH/wait_for_connection.py"
