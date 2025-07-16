"""
Copyright 2025 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

import pytest
from seed_env.core import EnvironmentSeeder


def test_environment_seeder_init_valid():
  seeder = EnvironmentSeeder(
    host_name="myproj",
    host_source_type="local",
    host_github_org_repo="",
    host_requirements_file_path="requirements.txt",
    host_commit="",
    seed_config="jax_seed.yaml",
    seed_tag_or_commit="latest",
    python_version="3.12",
    hardware="cpu",
    build_pypi_package=False,
    output_dir="output",
  )
  assert seeder.host_name == "myproj"
  assert seeder.seed_config_input == "jax_seed.yaml"
  assert seeder.python_version == "3.12"


def test_environment_seeder_init_invalid_seed():
  with pytest.raises(FileNotFoundError):
    EnvironmentSeeder(
      host_name="myproj",
      host_source_type="local",
      host_github_org_repo="",
      host_requirements_file_path="requirements.txt",
      host_commit="",
      seed_config="not_a_seed.yaml",
      seed_tag_or_commit="latest",
      python_version="3.12",
      hardware="cpu",
      build_pypi_package=False,
      output_dir="output",
    )


def test_seed_environment_remote(mocker, tmp_path):
  # Mock all external dependencies
  mock_download = mocker.patch(
    "seed_env.core.download_remote_git_file", return_value=str(tmp_path / "host.txt")
  )
  mock_generate_pyproject = mocker.patch(
    "seed_env.core.generate_minimal_pyproject_toml"
  )
  mock_build_env = mocker.patch("seed_env.core.build_seed_env")
  mock_build_pypi = mocker.patch("seed_env.core.build_pypi_package")
  # Mock Seeder instance and its method
  mock_seeder_instance = mocker.Mock()
  mock_seeder_instance.pypi_project_name = "jax"
  mock_seeder_instance.github_org_repo = "org/repo"
  mock_seeder_instance.download_seed_lock_requirement.return_value = str(
    tmp_path / "seed.txt"
  )
  mocker.patch("seed_env.core.Seeder", return_value=mock_seeder_instance)

  seeder = EnvironmentSeeder(
    host_name="myproj",
    host_source_type="remote",
    host_github_org_repo="org/repo",
    host_requirements_file_path="requirements.txt",
    host_commit="main",
    seed_config="jax_seed.yaml",
    seed_tag_or_commit="latest",
    python_version="3.12",
    hardware="cpu",
    build_pypi_package=True,
    output_dir=str(tmp_path / "output"),
  )
  seeder.seed_environment()

  # Assert all mocks were called
  assert mock_download.called
  assert mock_generate_pyproject.called
  assert mock_build_env.called
  assert mock_build_pypi.called
  assert mock_seeder_instance.download_seed_lock_requirement.called


def test_seed_environment_local_file_not_found(mocker, tmp_path):
  seeder = EnvironmentSeeder(
    host_name="myproj",
    host_source_type="local",
    host_github_org_repo="",
    host_requirements_file_path="not_exist.txt",
    host_commit="",
    seed_config="jax_seed.yaml",
    seed_tag_or_commit="latest",
    python_version="3.12",
    hardware="cpu",
    build_pypi_package=False,
    output_dir=str(tmp_path / "output"),
  )
  with pytest.raises(FileNotFoundError):
    seeder.seed_environment()
