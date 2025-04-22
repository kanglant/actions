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
# Keep‑alive pinger; sends SHUTDOWN when it exits.

SENTINEL="$1"
[ -n "$SENTINEL" ] || { echo "Usage: $0 <sentinel-file>"; exit 1; }

keep()   { echo "WAIT"     >"$SENTINEL"; }
finish() { echo "SHUTDOWN" >"$SENTINEL"; }
trap finish EXIT

keep
while true; do sleep 60; keep; done
