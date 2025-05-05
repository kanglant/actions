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


# Requires Bash. Other shells likely will not work.
# These utils are focused on making sure a suitable Python is available, and
# used, for the ML CI connection backend and frontend.

MIN_PYTHON_MAJOR_VERSION=3
MIN_PYTHON_MINOR_VERSION=10
MIN_PYTHON_VERSION="${MIN_PYTHON_MAJOR_VERSION}.${MIN_PYTHON_MINOR_VERSION}"

UV_VERSION="0.6.17"
UV_RELEASE_BASE_URL="https://github.com/astral-sh/uv/releases/download"
UV_PYTHON_TO_INSTALL="3.13"

# Checksums for uv 0.6.17
declare -A UV_CHECKSUMS=(
  ["aarch64-unknown-linux-gnu"]="6fb716c36e8ca9cf98b7cb347b0ced41679145837eb22890ee5fa9d8b68ce9f5"
  ["aarch64-unknown-linux-musl"]="98750f5c0cd9eb520799d10649efb18441b616150f07e6c1125f616a3fd137e8"
  ["x86_64-unknown-linux-gnu"]="720ec28f7a94aa8cd91d3d57dec1434d64b9ae13d1dd6a25f4c0cdb837ba9cf6"
  ["x86_64-unknown-linux-musl"]="28bd6b50be068cc09d8a46b76f8c4b72271d471c6673a5bdb47793622e62224d"
)

ensure_curl_is_installed() {
  echo "INFO: Checking if curl is installed..." >&2
  command -v curl &>/dev/null && { echo "INFO: curl found." >&2; return 0; }

  echo "INFO: curl not found, installing..." >&2
  local _cmd
  if command -v apt-get &>/dev/null; then
    _cmd='apt-get update 1>/dev/null && apt-get install -y curl'
  elif command -v dnf &>/dev/null; then _cmd='dnf install -y curl'
  elif command -v yum &>/dev/null; then _cmd='yum install -y curl'
  elif command -v apk &>/dev/null; then _cmd='apk add curl'
  elif command -v pacman &>/dev/null; then _cmd='pacman -S --noconfirm curl'
  elif command -v brew &>/dev/null; then _cmd='brew install curl'
  else echo "ERR: No package manager found." >&2; return 1; fi
  _cmd="$_cmd 1>/dev/null"

  echo "INFO: Running: $_cmd" >&2
  eval "$_cmd"
  echo "INFO: curl installed." >&2
}

# Determines the Linux target triple.
# Assumes one of the following. Other configurations working is incidental:
#   aarch64-unknown-linux-gnu
#   x86_64-unknown-linux-gnu
#   aarch64-unknown-linux-musl
#   x86_64-unknown-linux-musl
get_target_triple() {
  local arch libc
  arch=$(uname -m)
  echo "DEBUG: Detected architecture: ${arch}" >&2

  # Determine Libc
  libc="gnu" # Default to GNU/glibc

  # 1. Try ldd
  if command -v ldd >/dev/null && ldd --version 2>/dev/null | grep -qi 'musl'; then
      libc="musl"
  # 2. Fall back to `file` command if ldd didn't find musl
  elif command -v file >/dev/null && [ -e /bin/sh ]; then
      # Check the interpreter mentioned by file for /bin/sh
      # Example output containing musl: "... interpreter /lib/ld-musl-x86_64.so.1, ..."
      if file /bin/sh 2>/dev/null | grep -qi 'interpreter.*musl'; then
          libc="musl"
      fi
  fi
  echo "DEBUG: Detected libc: ${libc}" >&2

  local _target_triple="${arch}-unknown-linux-${libc}"
  echo "DEBUG: Target triple: $_target_triple" >&2
  echo "$_target_triple"
}

# Downloads and verifies the uv archive.
# Globals: UV_VERSION, UV_RELEASE_BASE_URL, UV_CHECKSUMS
# Arguments:
#   $1: Destination path.
#   $2: Target triple.
download_and_verify_uv() {
  local dest_file="$1" target_triple="$2"
  local expected_checksum filename url tmp_file calculated_checksum

  # 1. Get expected checksum (and check validity)
  expected_checksum="${UV_CHECKSUMS[${target_triple}]}"
  if [[ -z "$expected_checksum" || "$expected_checksum" == *"_HERE"* ]]; then
    echo "ERR: Invalid/missing checksum for ${target_triple}." >&2
    return 1
  fi
  echo "DEBUG: Expected checksum for ${target_triple}: ${expected_checksum}" >&2

  # 2. Download to temp file
  filename="uv-${target_triple}.tar.gz"
  url="${UV_RELEASE_BASE_URL}/${UV_VERSION}/${filename}"
  tmp_file=$(mktemp) || { echo "ERR: mktemp failed." >&2; return 1; }
  echo "INFO: Downloading uv from ${url} to ${tmp_file}" >&2

  local attempt=1 max_attempts=3
  while ! curl --proto '=https' --tlsv1.2 -sSfL "${url}" -o "${tmp_file}"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$max_attempts" ]; then
      echo "ERR: Download failed after $max_attempts attempts: ${url}" >&2
      return 1
    fi
    echo "WARN: Download attempt $((attempt-1)) failed. Retrying ${url} (attempt $attempt/$max_attempts)..." >&2
    sleep 1
  done
  echo "INFO: Download successful." >&2

  # 3. Verify checksum
  echo "INFO: Verifying checksum for ${tmp_file}" >&2
  calculated_checksum=$(sha256sum < "${tmp_file}" | awk '{print $1}')
  if [[ "$?" -ne 0 || "$calculated_checksum" != "$expected_checksum" ]]; then
      echo "ERR: Checksum mismatch for ${filename}." >&2
      echo "  Expected: $expected_checksum, Got: $calculated_checksum" >&2
      return 1
  fi
  echo "INFO: Checksum verified." >&2

  # 4. Move verified file to destination
  echo "INFO: Moving verified file to ${dest_file}" >&2
  mv "${tmp_file}" "${dest_file}"

  return 0
}

# Unpacks the uv archive and adds it to PATH
# Arguments:
#   $1: Path to the uv archive (.tar.gz).
#   $2: Target triple.
unpack_and_setup_uv() {
  local archive_path="$1" target_triple="$2"
  # Define install location
  local uv_bin_dir="$HOME/.uv/bin"
  local env_script_path="$HOME/.uv/env"
  echo "INFO: Unpacking uv from ${archive_path} and setting up PATH..." >&2

  # 1. Ensure directories exist
  mkdir -p "$uv_bin_dir"

  # 2. Unpack to temp dir and move binaries
  local unpack_dir
  unpack_dir=$(mktemp -d)
  local _unpacked_bin_dir="${unpack_dir}/uv-${target_triple}"
  echo "DEBUG: Unpacking ${archive_path} to ${unpack_dir}" >&2
  tar -xzf "$archive_path" -C "$unpack_dir"
  echo "DEBUG: Moving uv binaries to ${uv_bin_dir}" >&2
  mv "$_unpacked_bin_dir/uv" "$_unpacked_bin_dir/uvx" "$uv_bin_dir/"
  rm -rf "$unpack_dir"


  cat > "$env_script_path" << ENV_SCRIPT
#!/bin/sh
# Add uv bin directory to PATH idempotently
case ":\${PATH}:" in *:'$HOME/.uv/bin':*) ;; *) export PATH="\$HOME/.uv/bin:\${PATH}" ;; esac
ENV_SCRIPT
  chmod +x "$env_script_path"

  # 5. Modify profile files (Robust approach)
  local profile_files=("$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc")
  # Use single quotes for literal path in profile files
  local source_line=". '$HOME/.uv/env'"
  local file_updated=false

  for rc_file in "${profile_files[@]}"; do
      # Check if file exists and doesn't contain the line already
      if [[ -f "$rc_file" ]] && ! grep -qF -- "$source_line" "$rc_file" 2>/dev/null; then
          echo "INFO: Adding source line to ${rc_file}" >&2
          # Add a newline just in case the file doesn't end with one
          echo "" >> "$rc_file"
          echo "$source_line" >> "$rc_file"
          file_updated=true
      fi
  done

  # If no existing file was updated, and .profile doesn't exist, create .profile.
  local default_profile="$HOME/.profile"
  if [[ "$file_updated" = false ]] && [[ ! -f "$default_profile" ]]; then
      echo "INFO: Creating ${default_profile} and adding source line." >&2
      echo "$source_line" > "$default_profile"
      file_updated=true # Mark as updated for final message
  fi

  # 6. Update PATH for current session (simple prepend)
  echo "INFO: Adding ${uv_bin_dir} to PATH for current session." >&2
  export PATH="$uv_bin_dir:$PATH"

  echo "INFO: uv setup complete." >&2
  if [[ "$file_updated" = true ]]; then
      echo "INFO: Profile scripts (.bashrc, .profile, etc.) updated to include uv for interactive shells." >&2
  else
      echo "INFO: Profile scripts already configured or not found; sourcing '$HOME/.uv/env' is needed for new interactive shells if PATH is not inherited." >&2
  fi

  return 0
}

# Returns 0 if suitable, 1 otherwise.
suitable_python_exists() {
  local py_exe py_maj_min_output py_exit_status major minor setup_py_loc canon_py_path
  echo "INFO: Checking for a suitable Python >= ${MIN_PYTHON_VERSION}..." >&2
  # 1. Confirm an easily accessible Python exists
  py_exe=$(command -v python3 || command -v python)
  [[ -z "$py_exe" ]] && { echo "INFO: No python3 or python found in PATH." >&2; return 1; }
  echo "DEBUG: Found Python executable: ${py_exe}" >&2

  # 2. Get the python version
  set +e # Disable exit on error just for this command
  py_maj_min_output=$("$py_exe" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
  py_exit_status=$?
  set -e # Re-enable exit on error

  # 3. Check if the Python command executed successfully
  if [[ "$py_exit_status" -ne 0 ]]; then
      echo "WARN: Failed to execute '${py_exe} -c ...' to get version." >&2
      return 1 # Python command failed
  fi

  # 4. Check if the command produced any output
  if [[ -z "$py_maj_min_output" ]]; then
      echo "WARN: '${py_exe} -c ...' produced no version output." >&2
      return 1 # No version output received
  fi
  echo "DEBUG: Python version reported: ${py_maj_min_output}" >&2

  # 4. Make sure the version is acceptable.
  major="${py_maj_min_output%%.*}"
  minor="${py_maj_min_output#*.}"
  if [[ "$major" -lt "$MIN_PYTHON_MAJOR_VERSION" ]] || { [[ "$MIN_PYTHON_MAJOR_VERSION" -eq 3 ]] && [[ "$MIN_PYTHON_MINOR_VERSION" -lt 10 ]]; }; then
      echo "INFO: Python version ${major}.${minor} is < $MIN_PYTHON_VERSION (unsuitable)." >&2
      return 1 # Version too low
  fi

  # 5. Check if the Python is a setup-python one
  # (variable pythonLocation is set), and if so, dismiss it.

  # setup-python Python makes itself available via modifying various env
  # variables - something that's not reflected in a new session.
  # It also requires installing libssl-dev to ensure ability to make requests.
  # One of the variables it sets is `pythonLocation`, which appears to be unique
  # to the action. It's used to find out if  the Python is a setup-python one.
  # There is a potential of false positives here, but it's extremely low and
  # therefore acceptable.
  setup_py_loc="${pythonLocation:-}"
  if [[ -z "$setup_py_loc" ]]; then
    echo "INFO: Found suitable Python: ${py_exe}" >&2
    echo "$py_exe"
    return 0
  fi

  # Check if found python matches setup-python location
  echo "DEBUG: pythonLocation environment variable set to: ${setup_py_loc}" >&2
  canon_py_path=$(readlink -f "$py_exe" 2>/dev/null)
  echo "DEBUG: Canonical path of found Python: ${canon_py_path}" >&2
  if [[ "$canon_py_path" == "${setup_py_loc}"/* || "$canon_py_path" == "$setup_py_loc" ]]; then
      echo "INFO: Found Python (${py_exe}) matches pythonLocation (${setup_py_loc}). Treating as unsuitable." >&2
      return 1 # Is setup-python, unsuitable
  fi

  echo "INFO: Found suitable Python: ${py_exe}" >&2
  echo "$py_exe"
  return 0
}

ensure_suitable_python_is_available() {
  if suitable_python_path=$(suitable_python_exists); then
    echo "${suitable_python_path}"
    return 0
  fi

  echo "INFO: Suitable Python not found or unsuitable type detected. Using uv to install one." >&2

  # Make sure uv is available
  if ! command -v uv &>/dev/null; then
    echo "INFO: uv command not found. Proceeding with uv installation." >&2
    local tmp_archive
    tmp_archive=$(mktemp --suffix=.tar.gz uv-download-XXXXXX) || { echo "ERR: mktemp failed for uv archive."; return 1; }
    trap 'echo "INFO: Cleaning up ${tmp_archive}"; rm -f "${tmp_archive}"' EXIT

    local target_triple
    target_triple=$(get_target_triple)

    ensure_curl_is_installed
    download_and_verify_uv "$tmp_archive" "$target_triple"
    unpack_and_setup_uv "$tmp_archive" "$target_triple"
    trap - EXIT # Clear the trap after successful cleanup or if logic continues without needing it. Re-enable below if needed.
    echo "INFO: uv installation and setup complete." >&2
  else
    echo "INFO: uv command found in PATH." >&2
  fi

  # Use `uv` to install Python
  echo "INFO: Ensuring Python ${UV_PYTHON_TO_INSTALL} is installed via uv..." >&2
  uv python install "$UV_PYTHON_TO_INSTALL" # Idempotent
  echo "INFO: Finding path for Python ${UV_PYTHON_TO_INSTALL} via uv..." >&2
  uv python find "$UV_PYTHON_TO_INSTALL" # Print out the path
  echo "INFO: Python ${UV_PYTHON_TO_INSTALL} should now be available via uv." >&2
}
