import logging
import os
from seed_env.seeders.base_seeder import BaseSeeder
from seed_env.utils import (
    download_remote_git_file,
    valid_python_version_format,
    get_latest_project_version_from_pypi,
    resolve_github_tag_to_commit,
    is_valid_commit_hash,
    looks_like_commit_hash,
)

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

class JaxSeeder(BaseSeeder):
    @property
    def framework_name(self) -> str:
        return "jax"
    
    @property
    def github_org_repo(self) -> str:
        return "jax-ml/jax"
    
    def download_seed_lock_requirement(self, python_version: str) -> str:
        """
        Returns the path of a seed lock file that is downloaded from the seeder repo
        for the specified Python version.
        """
        # Construct the jax requirement lock file name based on the Python version
        file_name = self._jax_lock_file_path(python_version)

        # Validate the seed tag or commit
        SEED_COMMIT = ""

        if not self.seed_tag_or_commit:
            raise ValueError("No specific JAX tag or commit provided. "
                             "Please provide a valid JAX tag/commit or use 'latest' to determine the latest release version.")
        
        if self.seed_tag_or_commit.lower() == "latest":
            logging.info("Using 'latest' to determine the most recent stable JAX version.")
            # Here we implement logic to fetch the latest JAX version from PyPI
            # Note that JAX sometimes has jax only release, so the jaxlib version may not be the same as jax version.
            # For this reason, it may be better to use "jaxlib" instead of "jax" to determine the latest version.
            # TODO(kanglan): Sync this with the team.
            latest_version = get_latest_project_version_from_pypi(self.framework_name)
            # Construct the tag from the latest version, e.g., "jax-v<latest_version>"
            # This is also customized for JAX seeders, which use a specific release tag naming convention.
            latest_tag = f"jax-v{latest_version}"
            logging.info(f"Latest JAX version determined: {latest_version}. Using tag: {latest_tag}")
            # Get the valid commit hash from the latest_tag
            SEED_COMMIT = resolve_github_tag_to_commit(self.github_org_repo, latest_tag)
        elif looks_like_commit_hash(self.seed_tag_or_commit):
            if not is_valid_commit_hash(self.github_org_repo, self.seed_tag_or_commit):
                raise ValueError(f"Provided commit hash '{self.seed_tag_or_commit}' is not valid. ")
            SEED_COMMIT = self.seed_tag_or_commit
        else:
            logging.info(f"Assume the provided seed commit '{self.seed_tag_or_commit}' is a JAX tag.")
            # Get the valid commit hash from the tag
            SEED_COMMIT = resolve_github_tag_to_commit(self.github_org_repo, self.seed_tag_or_commit)

        # Construct the final seed file path based on the commit and Python version.
        final_seed_file_path = f"https://raw.githubusercontent.com/{self.github_org_repo}/{SEED_COMMIT}/{file_name}"
        # Download the seed lock file from the remote repository.
        SEED_REQUIREMENTS_FILE = os.path.abspath(download_remote_git_file(final_seed_file_path, self.download_dir))        
        if not SEED_REQUIREMENTS_FILE:
            raise ValueError(f"Failed to download the seed lock file from {final_seed_file_path}. "
                             "Please ensure the file exists in the JAX repository at the specified commit.")
        
        return SEED_REQUIREMENTS_FILE
    
    def _jax_lock_file_path(self, python_version: str) -> str:
        """
        Returns the path of a jax lock file that exists in jax-ml/jax repo.
        This is customized for JAX seeders, which use a specific naming convention for their lock files.
        E.g., 'build/requirements_lock_' + python_version.replace('.', '_') + '.txt'.
        """
        if not valid_python_version_format(python_version):
            raise ValueError(f"Invalid Python version: {python_version}. It should be in format X.Y")
        return f"build/requirements_lock_{python_version.replace('.', '_')}.txt"
    