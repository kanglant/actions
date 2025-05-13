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

UV_VERSION="0.6.17"
UV_RELEASE_BASE_URL="https://github.com/astral-sh/uv/releases/download"
UV_PYTHON_TO_INSTALL="3.13"

# Checksums for uv 0.6.17
declare -A UV_CHECKSUMS=(
  ["aarch64-pc-windows-msvc"]="3a9468e90df970f75759da6caed7dfde2816e0f3842031235c3835fc0c4e7d09"
  ["aarch64-unknown-linux-gnu"]="6fb716c36e8ca9cf98b7cb347b0ced41679145837eb22890ee5fa9d8b68ce9f5"
  ["aarch64-unknown-linux-musl"]="98750f5c0cd9eb520799d10649efb18441b616150f07e6c1125f616a3fd137e8"
  ["x86_64-pc-windows-msvc"]="32882cf98f646cafca003e7a7c471b7ff4ba977b681c9fa3b12cf908ba64af82"
  ["x86_64-unknown-linux-gnu"]="720ec28f7a94aa8cd91d3d57dec1434d64b9ae13d1dd6a25f4c0cdb837ba9cf6"
  ["x86_64-unknown-linux-musl"]="28bd6b50be068cc09d8a46b76f8c4b72271d471c6673a5bdb47793622e62224d"
)

# Detect Windows shells
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) _IS_WINDOWS=1 ;;
  *)                    _IS_WINDOWS=0 ;;
esac

_normalize_path() {
  local input_path="$1"
  if (( _IS_WINDOWS )); then local output_type="${2:-windows}"
  else local output_type="${2:-posix}"
  fi
  local normalized_path

  # This handles cases like HOME=/ leading to //somepath or HOME=/some/dir/ leading to /some/dir//.another
  normalized_path=$(printf '%s' "$input_path" | sed 's#/\+#/#g')

  if (( _IS_WINDOWS )) && [[ "$output_type" == "windows" ]]; then
      cygpath -m "$normalized_path"
  else
    # On non-Windows, the path is already POSIX-like
    echo "$normalized_path"
  fi
}

detect_pm() {
  if command -v apt-get &>/dev/null; then echo 'apt-get update 1>/dev/null && apt-get install -y';
  elif command -v dnf &>/dev/null; then echo 'dnf install -y';
  elif command -v yum &>/dev/null; then echo 'yum install -y';
  elif command -v apk &>/dev/null; then echo 'apk add';
  elif command -v pacman &>/dev/null; then echo 'pacman -S --noconfirm';
  elif command -v brew &>/dev/null; then echo 'brew install';
  else echo ""; fi
}

ensure_packages_installed() {
  local missing=() pm cmd
  for pkg in "$@"; do
    command -v "$pkg" &>/dev/null || missing+=("$pkg")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  pm=$(detect_pm) || true
  if [[ -z "$pm" ]]; then
    echo "ERR: No package manager found to install: ${missing[*]}" >&2
    return 1
  fi
  cmd="$pm ${missing[*]}"
  echo "INFO: Installing missing packages: ${missing[*]}" >&2
  eval "$cmd 1>/dev/null"
}

# Determines the Linux or Windows target triple for uv.
# Only specific triples in the UV_CHECKSUMS array above are supported, others
# working is unlikely, or incidental.
get_target_triple() {
  local arch os_type target_triple
  arch=$(uname -m)
  os_type=$(uname -s)

  if [[ "$os_type" == Linux* ]]; then
    local libc="gnu"
    if command -v ldd >/dev/null && ldd --version 2>/dev/null | grep -qi 'musl'; then
      libc="musl"
    elif command -v file >/dev/null && [ -e /bin/sh ] && file /bin/sh 2>/dev/null | grep -qi 'interpreter.*musl'; then
      libc="musl"
    fi
    target_triple="${arch}-unknown-linux-${libc}"
  elif (( _IS_WINDOWS )); then
    case "$arch" in
      x86_64) target_triple="x86_64-pc-windows-msvc" ;;
      aarch64) target_triple="aarch64-pc-windows-msvc" ;;
      *) echo "ERR: Unsupported architecture for Windows: ${arch}" >&2; return 1 ;;
    esac
  else
    echo "ERR: Unsupported OS type: ${os_type}" >&2; return 1
  fi
  echo "$target_triple"
}

# Downloads and verifies the uv archive.
download_and_verify_uv() {
  local dest_file="$1" target_triple="$2" expected_checksum filename url tmp_file calculated_checksum
  local archive_extension=".tar.gz"
  [[ "$target_triple" == *windows* ]] && archive_extension=".zip"

  expected_checksum="${UV_CHECKSUMS[${target_triple}]}"
  [[ -z "$expected_checksum" ]] && { echo "ERR: Missing checksum for ${target_triple}." >&2; return 1; }

  filename="uv-${target_triple}${archive_extension}"
  url="${UV_RELEASE_BASE_URL}/${UV_VERSION}/${filename}"

  if (( _IS_WINDOWS )); then
    tmp_file=$(mktemp "uv-XXXXXX.zip") || { echo "ERR: mktemp failed." >&2; return 1; }
  else
    tmp_file=$(mktemp "uv-XXXXXX.tar.gz") || { echo "ERR: mktemp failed." >&2; return 1; }
  fi
  echo "INFO: Downloading uv from ${url}" >&2

  local attempt=1 max_attempts=3
  while ! curl --proto '=https' --tlsv1.2 -sSfL "${url}" -o "${tmp_file}"; do
    (( attempt++ ))
    (( attempt > max_attempts )) && { echo "ERR: Download failed after ${max_attempts} attempts for ${url}" >&2; rm -f "${tmp_file}"; return 1; }
    echo "WARN: Retry ${attempt}/${max_attempts} for ${url}" >&2
    sleep 1
  done

  calculated_checksum=$(sha256sum < "${tmp_file}" | awk '{print $1}')
  if [[ "$calculated_checksum" != "$expected_checksum" ]]; then
    echo "ERR: Checksum mismatch for downloaded uv." >&2
    rm -f "${tmp_file}"
    return 1
  fi

  mv "${tmp_file}" "${dest_file}"
}

# Unpacks the uv archive and adds it to PATH
unpack_and_setup_uv() {
  local archive_path="$1" target_triple="$2" uv_bin_dir env_script_path
  uv_bin_dir="$(_normalize_path "$HOME/.uv/bin" posix)"
  env_script_path="$(_normalize_path "$HOME/.uv/env")"
  mkdir -p "$uv_bin_dir"
  local unpack_dir
  unpack_dir="$(_normalize_path "$(mktemp -d)")"
  trap 'rm -rf "${unpack_dir}"' EXIT RETURN

  local extracted_uv_content_dir="${unpack_dir}"
  if (( _IS_WINDOWS )); then
    ensure_packages_installed unzip
    unzip -q "$archive_path" -d "$unpack_dir"
  else
    tar -xzf "$archive_path" -C "$unpack_dir"
    extracted_uv_content_dir="${unpack_dir}/uv-${target_triple}"
  fi

  local exe_suffix=""
  (( _IS_WINDOWS )) && exe_suffix=".exe"
  local uv_exe_name="uv${exe_suffix}" uvx_exe_name="uvx${exe_suffix}"

  mv "${extracted_uv_content_dir}/${uv_exe_name}" "${uv_bin_dir}/"
  mv "${extracted_uv_content_dir}/${uvx_exe_name}" "${uv_bin_dir}/"

  rm -rf "${unpack_dir}"
  trap - EXIT RETURN # Clear the trap for unpack_dir

  cat > "$env_script_path" << ENV_SCRIPT
#!/bin/sh
case ":\${PATH}:" in *:'${uv_bin_dir}':*) ;; *) export PATH="${uv_bin_dir}:\${PATH}" ;; esac
ENV_SCRIPT
  chmod +x "$env_script_path"

  local profile_files=("$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc")
  local source_line
  source_line=". '$(_normalize_path "$env_script_path" posix)'"
  local file_updated=false

  for rc_file in "${profile_files[@]}"; do
    if [[ -f "$rc_file" ]] && ! grep -qF -- "$source_line" "$rc_file" 2>/dev/null; then
      echo "" >> "$rc_file"
      echo "$source_line" >> "$rc_file"
      file_updated=true
    fi
  done

  local default_profile="$HOME/.profile"
  if [[ "$file_updated" = false && ! -f "$default_profile" ]]; then
    echo "INFO: Adding uv to PATH by creating/updating ${default_profile}" >&2
    echo "$source_line" >> "$default_profile" # Append rather than overwrite, in case it exists but was empty
  fi

  export PATH="${uv_bin_dir}:$PATH"
}

suitable_python_exists() {
  local py_exe py_maj_min_output major minor setup_py_loc canon_py_path
  py_exe=$(command -v python3 || command -v python)
  [[ -z "$py_exe" ]] && return 1
  py_maj_min_output=$("$py_exe" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
  major="${py_maj_min_output%%.*}"
  minor="${py_maj_min_output#*.}"
  if [[ "$major" -lt "$MIN_PYTHON_MAJOR_VERSION" ]] || \
     { [[ "$major" -eq "$MIN_PYTHON_MAJOR_VERSION" && "$minor" -lt "$MIN_PYTHON_MINOR_VERSION" ]]; }; then
    return 1
  fi

  # Check if the Python is a setup-python one
  # (variable pythonLocation is set), and if so, do not use it.

  # setup-python Python makes itself available via modifying various env
  # variables - something that's not reflected in a connecting session.
  # It also requires installing libssl-dev to ensure ability to make requests.

  # One of the variables it sets is `pythonLocation`, which appears to be unique
  # to the action. Here, it's used to check if the Python is a setup-python one.

  # There is a potential of false positives here, but it's very low and
  # thus acceptable.
  setup_py_loc="${pythonLocation:-}"
  if [[ -n "$setup_py_loc" ]]; then
    canon_py_path=$(readlink -f "$py_exe" 2>/dev/null || echo "$py_exe") # Fallback for readlink failure
    # Check if python executable path starts with setup_py_loc
    [[ "$canon_py_path" == "${setup_py_loc}"/* || "$canon_py_path" == "$setup_py_loc" ]] && return 1
  fi

  _normalize_path "$py_exe"
}

ensure_suitable_python_is_available() {
  local -n python_bin_path="$1" # nameref for output variable
  local suitable_python_path
  if suitable_python_path=$(suitable_python_exists); then
    python_bin_path="${suitable_python_path}"
    return 0
  fi

  echo "INFO: Suitable Python not found, installing via uv." >&2
  ensure_packages_installed curl || return  1
  if ! command -v uv &>/dev/null; then
    local archive_extension=".tar.gz"
    (( _IS_WINDOWS )) && archive_extension=".zip"
    local tmp_archive
    tmp_archive="$(mktemp "uv-dl-XXXXXX${archive_extension}")"
    trap 'rm -f "${tmp_archive}"' EXIT

    local target_triple
    target_triple=$(get_target_triple) || return 1

    download_and_verify_uv "$tmp_archive" "$target_triple" || return 1
    unpack_and_setup_uv "$tmp_archive" "$target_triple" || return 1

    rm -f "${tmp_archive}"
    trap - EXIT
  fi

  echo "INFO: Installing Python ${UV_PYTHON_TO_INSTALL} using uv." >&2
  if ! uv python install "$UV_PYTHON_TO_INSTALL"; then
    echo "ERR: uv failed to install Python ${UV_PYTHON_TO_INSTALL}." >&2
    return 1
  fi

  local found_python_path
  found_python_path="$(uv python find "$UV_PYTHON_TO_INSTALL")"
  if [[ -z "$found_python_path" ]]; then
    echo "ERR: uv installed Python ${UV_PYTHON_TO_INSTALL} but could not find it afterwards." >&2
    return 1
  fi
  python_bin_path="$found_python_path"
}
