import logging
import os
from seed_env.seeders import SEEDER_REGISTRY
from seed_env.utils import (
    download_remote_git_file,
    generate_minimal_pyproject_toml,
    build_seed_env,
    build_pypi_package
)

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

class EnvironmentSeeder:
    """
    Handles the seeding and setup of a reproducible Python environment for host projects.

    This class supports:
      - Downloading a seed project's requirements lock file at a specific commit or version.
      - Downloading or using a local requirements file for the target (host) project.
      - Building dependency lock files for the host project based on both the seed project and
        the host requirements, ensuring consistent environment setup.
      - Optionally building a PyPI package for the host project.

    The EnvironmentSeeder is designed to streamline the process of creating reliable and
    reproducible environments by leveraging a known-good seed configuration and integrating
    it with the host project's requirements.
    """
    def __init__(
            self,
            host_name: str,
            host_source_type: str,
            host_github_org_repo: str,
            host_requirements_file_path: str,
            host_commit: str,
            seed_project: str,
            seed_tag_or_commit: str,
            python_version: str,
            hardware: str,
            build_pypi_package: bool,
            output_dir: str,
    ):
        self.host_name = host_name
        self.host_source_type = host_source_type
        self.host_github_org_repo = host_github_org_repo
        self.host_requirements_file_path = host_requirements_file_path
        self.host_commit = host_commit
        self.seed_project = seed_project
        self.seed_tag_or_commit = seed_tag_or_commit
        self.python_version = python_version
        self.hardware = hardware
        self.build_pypi_package = build_pypi_package
        self.output_dir = output_dir

        if seed_project not in SEEDER_REGISTRY:
            raise ValueError(f"Unsupported seed project: {seed_project}. Supported: {list(SEEDER_REGISTRY.keys())}")

    def seed_environment(self):
        """
        Orchestrates the full environment seeding process for the host project.

        This method performs the following steps:
          1. Retrieves the host project's requirements file, either by downloading it from a remote repository
                at a specific commit or using a local file.
          2. Determines the appropriate seed project and resolves the exact commit or tag to use.
                If 'latest' is specified, finds the latest release version;
                if the input reference looks like a commit, i.e., a 40-character hexadecimal string, validate it;
                if a tag is specified, resolves it to a commit hash.
          3. Downloads the seed project's lock file (e.g., build/requirements_lock_3_12.txt) for the specified
                Python version, e.g., 3.12, and commit.
          4. Generates a minimal pyproject.toml file for the specified Python environment.
          5. Combines the seed lock file and the host requirements to generate a new pyproject.toml, uv.lock,
                and host_requirements.txt in the output directory, using uv commands. Handles hardware-specific
                dependency exclusions (e.g., excludes libtpu for GPU, or CUDA dependencies for TPU).
          6. Optionally builds a PyPI package for the host project if requested.

        Raises:
            FileNotFoundError: If the local host requirements file does not exist for local host mode.
        """
        # Ensure the output directory exists
        os.makedirs( self.output_dir, exist_ok=True)
        self.output_dir = os.path.abspath(self.output_dir)

        # Create a directory for storing the downloaded requirements file
        self.download_dir = "downloaded_base_and_seed_requirements"
        os.makedirs(self.download_dir, exist_ok=True)

        # 1. Determine the host requirements file based on the source type
        HOST_REQUIREMENTS_FILE = None
        if self.host_source_type == "remote":
            # Download the host requirements file from the remote repository at the specified commit
            logging.info(f"Downloading host requirements file {self.host_requirements_file_path} from {self.host_github_org_repo} at commit/branch {self.host_commit}")
            remote_host_url = f"https://raw.githubusercontent.com/{self.host_github_org_repo}/{self.host_commit}/{self.host_requirements_file_path}"
            HOST_REQUIREMENTS_FILE = os.path.abspath(download_remote_git_file(remote_host_url, self.download_dir + "/host"))
        elif self.host_source_type == "local":
            if not os.path.isfile(self.host_requirements_file_path):
                raise FileNotFoundError(f"Local requirements file does not exist: {self.host_requirements_file_path}")
            HOST_REQUIREMENTS_FILE = self.host_requirements_file_path
        else:
            raise ValueError(f"Unsupported host source type: {self.host_source_type}. Supported: 'remote', 'local'.")
            
        # 2. Initialize the seeder instance, passing the path where the seed requirements lock files will be downloaded
        SeederClass = SEEDER_REGISTRY[self.seed_project]
        self.seeder = SeederClass(
            seed_tag_or_commit=self.seed_tag_or_commit,
            download_dir=self.download_dir + "/seed",
        )
        logging.info(f"Using {self.seeder.framework_name} at tag/commit {self.seed_tag_or_commit} on {self.seeder.github_org_repo} as seed")
        
        # 3. Download the seed lock file for the specified Python version
        SEED_LOCK_FILE = os.path.abspath(self.seeder.download_seed_lock_requirement(self.python_version))

        # 4. Generate a minimal pyproject.toml file for the specified Python version to the output directory
        generate_minimal_pyproject_toml(self.host_name, self.python_version, self.output_dir)

        # Construct the host lock file name
        HOST_LOCK_FILE_NAME = f"{self.host_name.replace('-', '_')}_requirements_lock_{self.python_version.replace('.', '_')}.txt"
        # 5. Generate the pyproject.toml, uv.lock, and host_requirements.txt in the output directory
        build_seed_env(HOST_REQUIREMENTS_FILE, SEED_LOCK_FILE, self.output_dir, self.hardware, HOST_LOCK_FILE_NAME)

        # 6. Build pypi package
        if self.build_pypi_package:
            build_pypi_package(self.output_dir)
            logging.info("Successfully build a python package")
