import pytest
from seed_env.core import EnvironmentSeeder

def test_environment_seeder_init_valid():
    seeder = EnvironmentSeeder(
        host_name="myproj",
        host_source_type="local",
        host_github_org_repo="",
        host_requirements_file_path="requirements.txt",
        host_commit="",
        seed_project="jax",
        seed_tag_or_commit="latest",
        python_version="3.12",
        hardware="cpu",
        build_pypi_package=False,
        output_dir="output"
    )
    assert seeder.host_name == "myproj"
    assert seeder.seed_project == "jax"
    assert seeder.python_version == "3.12"

def test_environment_seeder_init_invalid_seed():
    with pytest.raises(ValueError):
        EnvironmentSeeder(
            host_name="myproj",
            host_source_type="local",
            host_github_org_repo="",
            host_requirements_file_path="requirements.txt",
            host_commit="",
            seed_project="not_a_seed",
            seed_tag_or_commit="latest",
            python_version="3.12",
            hardware="cpu",
            build_pypi_package=False,
            output_dir="output"
        )

def test_seed_environment_remote(mocker, tmp_path):
    # Mock all external dependencies
    mock_download = mocker.patch("seed_env.core.download_remote_git_file", return_value=str(tmp_path / "host.txt"))
    mock_generate_pyproject = mocker.patch("seed_env.core.generate_minimal_pyproject_toml")
    mock_build_env = mocker.patch("seed_env.core.build_seed_env")
    mock_build_pypi = mocker.patch("seed_env.core.build_pypi_package")
    # Mock SeederClass and its method
    mock_seeder_class = mocker.Mock()
    mock_seeder_instance = mocker.Mock()
    mock_seeder_instance.framework_name = "jax"
    mock_seeder_instance.github_org_repo = "org/repo"
    mock_seeder_instance.download_seed_lock_requirement.return_value = str(tmp_path / "seed.txt")
    mock_seeder_class.return_value = mock_seeder_instance
    mocker.patch.dict("seed_env.core.SEEDER_REGISTRY", {"jax": mock_seeder_class})

    seeder = EnvironmentSeeder(
        host_name="myproj",
        host_source_type="remote",
        host_github_org_repo="org/repo",
        host_requirements_file_path="requirements.txt",
        host_commit="main",
        seed_project="jax",
        seed_tag_or_commit="latest",
        python_version="3.12",
        hardware="cpu",
        build_pypi_package=True,
        output_dir=str(tmp_path / "output")
    )
    seeder.seed_environment()

    # Assert all mocks were called
    assert mock_download.called
    assert mock_generate_pyproject.called
    assert mock_build_env.called
    assert mock_build_pypi.called
    assert mock_seeder_instance.download_seed_lock_requirement.called

def test_seed_environment_local_file_not_found(mocker, tmp_path):
    mocker.patch.dict("seed_env.core.SEEDER_REGISTRY", {"jax": mocker.Mock()})
    seeder = EnvironmentSeeder(
        host_name="myproj",
        host_source_type="local",
        host_github_org_repo="",
        host_requirements_file_path="not_exist.txt",
        host_commit="",
        seed_project="jax",
        seed_tag_or_commit="latest",
        python_version="3.12",
        hardware="cpu",
        build_pypi_package=False,
        output_dir=str(tmp_path / "output")
    )
    with pytest.raises(FileNotFoundError):
        seeder.seed_environment()
