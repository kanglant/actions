import os
import subprocess
import logging
import re
import requests
import re
import logging
from seed_env.config import DEPS_EXCLUDED_FROM_GPU_ENV, DEPS_EXCLUDED_FROM_TPU_ENV


logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')


def download_remote_git_file(url: str, output_dir: str) -> str:
    """
    Downloads a file from a given GitHub raw URL and saves it to the specified output directory.

    Args:
        url (str): The raw GitHub URL of the file to download.
        output_dir (str): The directory where the file should be saved.

    Returns:
        str: The path to the downloaded file.

    Raises:
        requests.RequestException: If the download fails.
        OSError: If the file cannot be written.
    """
    os.makedirs(output_dir, exist_ok=True)  # Ensure the output directory exists
    filename = os.path.basename(url)
    output_path = os.path.join(output_dir, filename)
    try:
        logging.info(f"Downloading file from {url} to {output_path}")
        response = requests.get(url)
        response.raise_for_status()
        with open(output_path, "wb") as f:
            f.write(response.content)
        logging.info(f"File downloaded successfully: {output_path}")
        return output_path
    except Exception as e:
        logging.error(f"Failed to download file from {url}: {e}")
        raise

def get_latest_project_version_from_pypi(project_name: str) -> str:
    """
    Retrieves the latest version of a given project from PyPI.

    Args:
        project_name (str): The name of the project on PyPI.

    Returns:
        str: The latest version of the project.

    Raises:
        requests.RequestException: If the request to PyPI fails.
        ValueError: If the project is not found or has no releases.
    """
    url = f"https://pypi.org/pypi/{project_name}/json"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        if 'releases' not in data or not data['releases']:
            raise ValueError(f"No releases found for project '{project_name}'")
        latest_version = max(data['releases'].keys(), key=lambda v: tuple(map(int, v.split('.'))))
        return latest_version
    except requests.RequestException as e:
        logging.error(f"Failed to fetch latest version for project '{project_name}': {e}")
        raise

def resolve_github_tag_to_commit(github_org_repo: str, tag: str) -> str:
    """
    Resolves a GitHub tag to its corresponding commit hash.

    Args:
        github_org_repo (str): The GitHub organization and repository in the format 'org/repo'.
        tag (str): The tag to resolve.

    Returns:
        str: The commit hash associated with the tag.

    Raises:
        requests.RequestException: If the request to GitHub fails.
        ValueError: If the tag is not found or does not resolve to a commit.
    """
    url = f"https://api.github.com/repos/{github_org_repo}/git/ref/tags/{tag}"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        if 'object' not in data or 'sha' not in data['object']:
            raise ValueError(f"Tag '{tag}' not found in repo '{github_org_repo}'.")
        return data['object']['sha']
    except requests.RequestException as e:
        logging.error(f"Failed to resolve tag '{tag}' in repo '{github_org_repo}': {e}")
        raise

def is_valid_commit_hash(github_org_repo: str, commit_hash: str) -> bool:
    """
    Checks if a given commit hash is valid in a GitHub repository.

    Args:
        github_org_repo (str): The GitHub organization and repository in the format 'org/repo'.
        commit_hash (str): The commit hash to validate.

    Returns:
        bool: True if the commit hash is valid, False otherwise.

    Raises:
        requests.RequestException: If the request to GitHub fails.
    """
    url = f"https://api.github.com/repos/{github_org_repo}/commits/{commit_hash}"
    try:
        response = requests.get(url)
        return response.status_code == 200
    except requests.RequestException as e:
        logging.error(f"Failed to check commit hash '{commit_hash}' in repo '{github_org_repo}': {e}")
        raise

def looks_like_commit_hash(commit_hash: str) -> bool:
    """
    Checks if a string looks like a valid commit hash, i.e.,
    a 40-character hexadecimal string.

    Args:
        commit_hash (str): The string to check.

    Returns:
        bool: True if the string looks like a commit hash, False otherwise.
    """
    return re.fullmatch(r"[0-9a-f]{40}", commit_hash) is not None

def generate_minimal_pyproject_toml(project_name: str, python_version: str, output_dir: str):
    """
    Generates a minimal pyproject.toml file for a given project and Python version.

    Args:
        project_name (str): The name of the project.
        python_version (str): The target Python version (e.g., '3.12').
        output_dir (str): The directory where the pyproject.toml file should be saved.

    Returns:
        str: The path to the generated pyproject.toml file.
    """
    if not project_name:
        raise ValueError("Project name cannot be empty in pyproject.toml.")
    if not valid_python_version_format(python_version):
        raise ValueError(f"Invalid Python version format: {python_version}. Expected format is 'X.Y'.")
        
    # TODO(kanglan): Pass the version as an argument
    # For now, we use a fixed version "0.1.0" as a placeholder.
    content = f"""\
[project]
name = "{project_name}-meta"
version = "0.1.0"
requires-python = "=={python_version}.*"
dependencies = [
]
"""
    try:
        pyproject_path = os.path.join(output_dir, "pyproject.toml")
        with open(pyproject_path, "w") as f:
            f.write(content)
        logging.info(f"Generated minimal pyproject.toml at {pyproject_path}")
        return pyproject_path
    except OSError as e:
        logging.error(f"Failed to write pyproject.toml to {pyproject_path}: {e}")
        raise

def build_seed_env(host_requirements_file: str, seed_lock_file: str, output_dir: str, hardware: str, host_lock_file_name: str):
    """
    Builds the seed environment by combining the host requirements and seed lock files.

    Args:
        host_requirements_file (str): Path to the host requirements file.
        seed_lock_file (str): Path to the seed lock file.
        output_dir (str): Directory where the output files will be saved.
        hardware (str): The target hardware for the environment (e.g., 'tpu', 'gpu').
        host_lock_file_name (str): The name of the host lock file to be generated.
    """
    if not os.path.isfile(host_requirements_file):
        raise FileNotFoundError(f"Host requirements file does not exist: {host_requirements_file}")
    if not os.path.isfile(seed_lock_file):
        raise FileNotFoundError(f"Seed lock file does not exist: {seed_lock_file}")

    # Ensure a minimal pyproject.toml file exists in the output directory
    pyproject_file = os.path.join(output_dir, "pyproject.toml")
    if not os.path.isfile(pyproject_file):
        raise FileNotFoundError(f"A minimal pyproject.toml file does not exist in output directory: {output_dir}")
    
    # Remove uv.lock if it exists, as we will generate a new one
    uv_lock_file = os.path.join(output_dir, "uv.lock")
    if os.path.isfile(uv_lock_file):
        try:
            os.remove(uv_lock_file)
            logging.info(f"Removed existing uv.lock file: {uv_lock_file}")
        except OSError as e:
            logging.error(f"Failed to remove existing uv.lock file: {e}. It may cause issues with the new lock generation.")
            raise

    command = [
        "uv", "add", "--managed-python", "--no-build", "--no-sync", "--resolution=highest",
        "--directory", output_dir,
        "-r", seed_lock_file,
    ]
    run_command(command)

    if hardware == "tpu":
        # Exclude gpu-only dependencies from the TPU environment
        command = [
            "uv", "remove", "--managed-python", "--resolution=highest", "--no-sync",
            "--directory", output_dir,
            *DEPS_EXCLUDED_FROM_TPU_ENV,
        ]
        run_command(command)
    elif hardware == "gpu":
        # Exclude tpu-only dependencies, including libtpu, from the GPU environment
        # This is crucial as JAX uses the existence of libtpu to determine if it is running on TPU or GPU.
        command = [
            "uv", "remove", "--managed-python", "--resolution=highest", "--no-sync",
            "--directory", output_dir,
            *DEPS_EXCLUDED_FROM_GPU_ENV,
        ]
        run_command(command)

    #################### Remove once the https://github.com/AI-Hypercomputer/maxtext/pull/1871 is merged
    command = [
        "sed", "-i", "s/protobuf==3.20.3/protobuf/g", host_requirements_file
    ]
    run_command(command)
    command = [
        "sed", "-i", "s/sentencepiece==0.2.0/sentencepiece>=0.1.97/g", host_requirements_file
    ]
    run_command(command)
    command = [
        "sed", "-i", 's|google-jetstream@git+https://github.com/AI-Hypercomputer/JetStream.git|google-jetstream @ https://github.com/AI-Hypercomputer/JetStream/archive/261f25007e4d12bb57cf8d5d61e291ba8f18430f.zip|g', host_requirements_file
    ]
    run_command(command)
    command = [
        "sed", "-i", 's|mlperf-logging@git+https://github.com/mlperf/logging.git|mlperf-logging @ https://github.com/mlcommons/logging/archive/44b4810e65e8c0a7d9e4e207c60e51d9458a3fb8.zip|g', host_requirements_file
    ]
    run_command(command)
    #################### Remove once the https://github.com/AI-Hypercomputer/maxtext/pull/1871 is merged

    command = [
         "uv", "add", "--managed-python", "--no-sync", "--resolution=highest",
         "--directory", output_dir, 
         "-r", host_requirements_file,
    ]
    run_command(command)

    command = [
        "uv", "export", "--managed-python", "--locked", "--no-hashes", "--no-annotate",
        "--resolution=highest",
        "--directory", output_dir,
        "--output-file", host_lock_file_name,
    ]
    run_command(command)

    lock_to_lower_bound_project(os.path.join(output_dir, host_lock_file_name), pyproject_file)

    os.remove(uv_lock_file)
    command = [
        "uv", "lock", "--managed-python", "--resolution=lowest",
        "--directory", output_dir,
    ]
    run_command(command)

    command = [
        "uv", "export", "--managed-python", "--locked", "--no-hashes", "--no-annotate",
        "--resolution=lowest",
        "--directory", output_dir,
        "--output-file", host_lock_file_name,
    ]
    run_command(command)

    logging.info("Environment build process completed successfully.")
    
def run_command(command, cwd=None, capture_output=False, check=True):
    """
    Executes a shell command.
    Args:
        command (list or str): The command to execute.
        cwd (str, optional): The current working directory for the command.
        capture_output (bool): If True, stdout and stderr will be captured and returned.
        check (bool): If True, raise CalledProcessError if the command returns a non-zero exit code.
    Returns:
        subprocess.CompletedProcess: The result of the command execution.
    Raises:
        subprocess.CalledProcessError: If check is True and the command fails.
    """
    cmd_str = ' '.join(command) if isinstance(command, list) else command
    logging.info(f"Executing command: {cmd_str}")
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            capture_output=capture_output,
            text=True, # Decode stdout/stderr as text
            check=check
        )
        if capture_output:
            # Only print debug output if logging level is DEBUG
            if logging.getLogger().level <= logging.DEBUG:
                logging.debug(f"Stdout:\n{result.stdout}")
                if result.stderr:
                    logging.debug(f"Stderr:\n{result.stderr}")
        return result
    except FileNotFoundError:
        logging.error(f"Command not found: '{command[0]}'. Make sure it's installed and in your PATH.")
        raise
    except subprocess.CalledProcessError as e:
        logging.error(f"Command failed with exit code {e.returncode}: {e.cmd}")
        logging.error(f"Stdout:\n{e.stdout}")
        logging.error(f"Stderr:\n{e.stderr}")
        raise
    except Exception as e:
        logging.error(f"An unexpected error occurred while running command: {e}")
        raise

def valid_python_version_format(python_version: str) -> bool:
    """
    Validates that the Python version string is in the format X.Y where X and Y are integers.
    Returns True if valid, False otherwise.
    """
    if not isinstance(python_version, str):
        return False
    return re.fullmatch(r"\d+\.\d+", python_version) is not None

def replace_dependencies_in_project_toml(new_deps: str, filepath: str):
    """
    Replaces the dependencies section in a pyproject.toml file with a new set of dependencies.

    Args:
        new_deps (str): The new dependencies block as a string.
        filepath (str): Path to the pyproject.toml file to update.

    This function reads the specified pyproject.toml file, finds the existing [project] dependencies array,
    and replaces it with the provided new_deps string. The updated content is then written back to the file.
    """
    dependencies_regex = re.compile(
        r"^dependencies\s*=\s*\[(\n+\s*.*,\s*)*[\n\r]*\]",
        re.MULTILINE
    )

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    new_content = dependencies_regex.sub(new_deps, content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)

def read_requirements_lock_file(filepath):
    """
    Reads a requirements lock file and extracts all pinned dependencies.

    Args:
        filepath (str): Path to the requirements lock file.

    Returns:
        list[str]: A list of dependency strings (e.g., 'package==version').
                   Lines that are comments or do not contain '==' or '@' are ignored.

    This function skips comment lines and only includes lines that specify pinned dependencies
    (using '==' or '@' for VCS links).
    """
    lines = []
    with open(filepath, 'r', encoding='utf-8') as file:
        for line in file:
            if "#" not in line and ("==" in line or "@" in line):
                lines.append(line.strip())
    return lines

def convert_deps_to_lower_bound(pinned_deps):
    """
    Converts a list of pinned dependencies (e.g., 'package==version') to lower-bound dependencies (e.g., 'package>=version').

    Args:
        pinned_deps (list[str]): A list of dependency strings pinned to specific versions.

    Returns:
        list[str]: A list of dependency strings with lower-bound version specifiers.

    This function replaces '==' with '>=' for each dependency, preserving other dependency formats (such as VCS links).
    """
    lower_bound_deps = []
    for pinned_dep in pinned_deps:
        lower_bound_dep = pinned_dep
        if "==" in pinned_dep:
            lower_bound_dep = pinned_dep.replace("==", ">=")
        lower_bound_deps.append(lower_bound_dep)

    return lower_bound_deps

def lower_boud_deps_to_string(lower_bound_deps):
    """
    Converts a list of lower-bound dependency strings into a TOML-formatted dependencies array.

    Args:
        lower_bound_deps (list[str]): A list of dependency strings (e.g., 'package>=version').

    Returns:
        str: A string representing the dependencies array in TOML format, suitable for insertion into pyproject.toml.
    """
    return 'dependencies = [\n    "' + '",\n    "'.join(lower_bound_deps) + '"\n]'

def lock_to_lower_bound_project(host_lock_file: str, pyproject_toml: str):
    """
    Updates the dependencies in a pyproject.toml file to use lower-bound versions based on a lock file.

    Args:
        host_lock_file (str): Path to the requirements lock file containing pinned dependencies.
        pyproject_toml (str): Path to the pyproject.toml file to update.

    This function reads all pinned dependencies from the lock file, converts them to lower-bound specifiers (e.g., 'package>=version'),
    formats them as a TOML dependencies array, and replaces the dependencies section in the given pyproject.toml file.
    """
    pinned_deps = read_requirements_lock_file(host_lock_file)
    lower_bound_deps = convert_deps_to_lower_bound(pinned_deps)
    new_deps = lower_boud_deps_to_string(lower_bound_deps)
    replace_dependencies_in_project_toml(new_deps, pyproject_toml)

def build_pypi_package(output_dir: str):
    """
    Builds a PyPI wheel package from a pyproject.toml file in the specified output directory.

    Args:
        output_dir (str): The directory containing the pyproject.toml file.

    Raises:
        FileNotFoundError: If the pyproject.toml file does not exist in the output directory.
        subprocess.CalledProcessError: If the build command fails.

    This function uses 'uv build --wheel' to generate a wheel package in the given directory.
    """
    # Use uv build --wheel to build a pypi package at output_dir
    # Assume there is a pyproject.toml
    pyproject_file = os.path.join(output_dir, "pyproject.toml")
    if not os.path.isfile(pyproject_file):
        raise FileNotFoundError(f"A pyproject.toml file does not exist in output directory: {output_dir}")
    
    command = [
        "uv", "build", "--wheel",
        "--directory", output_dir,
    ]
    run_command(command)
