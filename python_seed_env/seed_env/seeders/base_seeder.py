from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

class BaseSeeder(ABC):
    """
    Abstract Base Class for framework-specific environment seeders.
    Defines the interface for how a seeder should provide its version
    and modify requirements for uv compilation.
    """
    def __init__(self, seed_tag_or_commit: str, download_dir: Optional[Path] = None):
        self.seed_tag_or_commit = seed_tag_or_commit
        if download_dir is None:
            download_dir = Path.cwd() / "seed_locks"
        self.download_dir = download_dir # Path to the download directory where seed lock files will be stored.

    @property
    @abstractmethod
    def framework_name(self) -> str:
        """Returns the name of the framework this seeder handles (e.g., 'jax', 'pytorch')."""
        pass

    @property
    @abstractmethod
    def github_org_repo(self) -> str:
        """Returns the github organization and repository of the seeder (e.g., 'jax-ml/jax')."""
        pass

    @abstractmethod
    def download_seed_lock_requirement(self, python_version: str) -> str:
        """
        Returns the path of a seed lock file that is downloaded from the seeder repo
        for the specified Python version.
        """
        pass

