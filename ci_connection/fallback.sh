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


echo "Python-based connection didn't work. Here's a basic pure Bash command to connect to the runner."
echo "Googler connection only"
echo "See go/ml-github-actions:connect for details"
echo "To connect, run the following command in your local terminal:"
echo -e "${BOLD_GREEN_UNDERLINE}----------------------------------------------------------------------${RESET}"
echo "${CONNECT_CMD}"
echo -e "${BOLD_GREEN_UNDERLINE}----------------------------------------------------------------------${RESET}"
echo -e "${BOLD_GREEN_UNDERLINE}This fallback will NOT wait for the connection - add a wait/sleep somewhere after the 'Wait for Connection' in your workflow manually.${RESET}"



  echo "INFO: uv setup complete. PATH updated for current session." >&2
  if [[ "$file_updated" = true ]]; then
      echo "INFO: Profile files updated. Restart your shell or run:" >&2
      echo "  . '$HOME/.uv/env'" >&2
  else
      echo "INFO: Profile files already configured or not found. To update PATH, run:" >&2
      echo "  . '$HOME/.uv/env'" >&2
  fi
